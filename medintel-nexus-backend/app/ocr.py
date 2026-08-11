"""Real prescription OCR: Tesseract for text extraction, a local LLM for
structuring the raw text into medicine fields.

Why this split instead of one OCR-and-structure call: Tesseract reads pixels
into text but has no idea what a "frequency" or "duration" is — it just
extracts what's printed. An LLM is good at the opposite job (turning messy
free text into a fixed schema) but not at reading pixels at all. Chaining
them plays to what each is actually good at, and both run on this machine —
no per-request cost, and no prescription image or its contents leaving the
box. See `app/llm.py`.

Honest limitation, not a bug to "fix" later: Tesseract (like every OCR
engine, including paid ones) is unreliable on messy handwriting. It works
well on printed/typed prescriptions and pharmacy labels; a doctor's fast
cursive handwriting will often come out garbled, the same way it would with
Google Cloud Vision or AWS Textract. There's no free-vs-paid fix for that —
it's a fundamental limit of OCR on handwriting, not a quality gap this code
should try to paper over with a fake confidence number.

What this module does instead is *measure* that uncertainty and hand it
upward, so the app can ask the patient to confirm the fields the pipeline
isn't sure about rather than silently acting on a misread drug name. See
[field_confidence] for how a per-field number is derived.
"""

import json
import logging
import re
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Dict, List, Optional, Sequence

import pytesseract
from PIL import Image

from app import llm

logger = logging.getLogger(__name__)

_STRUCTURE_SYSTEM_PROMPT = """You extract structured medicine entries from \
raw OCR text of a prescription. The text may be messy, have OCR errors, or \
be missing punctuation — do your best with what's there.

A prescription line typically reads:
  <form> <drug> <strength>  <rhythm>  <duration>  <instruction>
e.g.  "1. Tab Amoxicillin 500mg   1-0-1   x 5 days   after food"

Split each line into these fields, and keep them strictly separate:

- raw_name: the medicine as it literally appears, including the strength if \
written together (e.g. "Tab Amoxicillin 500mg").
- normalized_name: the drug name ALONE. Drop the form prefix (Tab, Tablet, \
Cap, Capsule, Syp, Inj) and drop the strength. -> "Amoxicillin"
- strength: the dose per unit, with its unit. Usually mg ("500mg", "850 mg"), \
but liquids are dosed by volume ("15 ml", "5ml") and some drugs by IU or mcg \
— take whichever unit the line actually uses. Else null.
- frequency: ONLY the dosing rhythm. Nothing else may appear in this field. \
Valid contents are things like "1-0-1", "0-0-1", "1-1-1", "SOS", "OD", \
"BD", "TDS", "QID", "twice daily", "every 6 hours". Indian prescriptions \
write the rhythm as morning-afternoon-night, so "1-0-1" means one in the \
morning and one at night. NEVER put a duration, a food instruction, or any \
other words in this field.
- duration_days: how many DAYS the course runs, as an integer. Written as \
"x 5 days", "for 5 days", "5/7", "x5d". OCR frequently mangles this — \
"x 5 days" can arrive as "xS5Sdays" or "x5doys" — so read through the noise \
and pull out the number. If the course is open-ended ("continue", "SOS", \
"as needed") or no duration is stated, use null.
- instructions: everything else that is a real instruction — "after food", \
"before breakfast", "fever only", "continue", "with water". Anything on the \
line that is not the name, strength, rhythm or duration belongs HERE, not \
in frequency.

Never invent a medicine that isn't actually in the text, and never invent a \
field value that isn't stated or clearly implied — use null rather than \
guessing. If the text doesn't look like a prescription at all, or no \
medicines can be identified, return an empty list.

Worked examples of the split:

"1. Tab Amoxicillin 500mg   1-0-1   x 5 days   after food"
-> raw_name "Tab Amoxicillin 500mg", normalized_name "Amoxicillin",
   strength "500mg", frequency "1-0-1", duration_days 5,
   instructions "after food"

"2. Tab Paracetamol 650mg   SOS   fever only"
-> raw_name "Tab Paracetamol 650mg", normalized_name "Paracetamol",
   strength "650mg", frequency "SOS", duration_days null,
   instructions "fever only"

"4. Tab Warfarin 5mg   0-0-1   continue"
-> raw_name "Tab Warfarin 5mg", normalized_name "Warfarin",
   strength "5mg", frequency "0-0-1", duration_days null,
   instructions "continue"

Respond with ONLY a JSON object, no other text, matching exactly this shape:
{
  "medicines": [
    {
      "raw_name": "<string>",
      "normalized_name": "<string or null>",
      "strength": "<string or null>",
      "frequency": "<string or null>",
      "duration_days": <integer or null>,
      "instructions": "<string or null>"
    }
  ]
}"""


@dataclass
class OcrWord:
    """One word Tesseract read, with its own confidence rescaled to 0–1."""

    text: str
    confidence: float


@dataclass
class OcrResult:
    text: str
    words: List[OcrWord]


# A PDF page carrying at least this much text is treated as having a real
# text layer. Below it the "text" is usually just a header or a stray label
# stamped on a scan, and rasterising to OCR reads far more.
_PDF_TEXT_LAYER_MIN_CHARS = 120

# Lab PDFs are vector text at heart; 200 DPI is enough for Tesseract without
# producing huge bitmaps for a multi-page panel.
_PDF_RASTER_DPI = 200

# A report longer than this is almost certainly an appendix-heavy export,
# and the structuring model's context window is the real limit anyway.
_PDF_MAX_PAGES = 10


def _is_pdf(path: str) -> bool:
    """Sniffs the magic bytes rather than trusting the extension — the app
    uploads with a generated file name and the real type is what matters.
    """
    try:
        with open(path, "rb") as fh:
            return fh.read(5) == b"%PDF-"
    except OSError:
        return False


def _extract_pdf(pdf_path: str) -> OcrResult:
    """Reads a PDF, preferring its text layer over OCR.

    Most lab reports arrive as digitally generated PDFs, which carry the
    values as real text. Reading that layer is exact and instant — running
    Tesseract over a rasterised page instead would only introduce OCR errors
    into numbers that were already perfect. Scans (no text layer) fall back
    to rasterise-then-OCR.

    Text-layer words get a confidence of 1.0 because they were not guessed:
    the character codes are what the generator wrote.
    """
    try:
        import fitz  # PyMuPDF
    except ImportError:
        logger.error(
            "PDF upload received but PyMuPDF isn't installed. "
            "Run `pip install -r requirements.txt`."
        )
        return OcrResult(text="", words=[])

    try:
        doc = fitz.open(pdf_path)
    except Exception:
        logger.exception("Could not open PDF %s", pdf_path)
        return OcrResult(text="", words=[])

    pages: List[str] = []
    words: List[OcrWord] = []
    try:
        for page in doc[:_PDF_MAX_PAGES]:
            text = (page.get_text() or "").strip()
            if len(text) >= _PDF_TEXT_LAYER_MIN_CHARS:
                pages.append(text)
                words.extend(
                    OcrWord(text=tok, confidence=1.0)
                    for tok in text.split()
                )
                continue

            # No usable text layer — this page is a scan. Rasterise it and
            # hand it to Tesseract like any other photo.
            pix = page.get_pixmap(dpi=_PDF_RASTER_DPI)
            img = Image.frombytes(
                "RGB", (pix.width, pix.height), pix.samples
            )
            page_result = _extract_pil(img)
            if page_result.text:
                pages.append(page_result.text)
                words.extend(page_result.words)
    except Exception:
        logger.exception("PDF extraction failed for %s", pdf_path)
        return OcrResult(text="", words=[])
    finally:
        doc.close()

    return OcrResult(text="\n".join(pages), words=words)


def _extract_pil(img: "Image.Image") -> OcrResult:
    """Tesseract over an already-open image. Shared by the photo path and
    the rasterised-PDF-page path."""
    try:
        data = pytesseract.image_to_data(
            img, output_type=pytesseract.Output.DICT
        )
    except Exception:
        logger.exception("Tesseract OCR failed")
        return OcrResult(text="", words=[])
    return _rows_to_result(data)


def extract(image_path: str) -> OcrResult:
    """Runs Tesseract on the image at [image_path], keeping the per-word
    confidences alongside the joined text.

    PDFs are handled by [_extract_pdf] — Pillow's PDF support is
    write-only, so `Image.open` on one raises, which is exactly how every
    uploaded lab-report PDF used to end up as "nothing readable".

    Returns an empty result (not an exception) on any failure — callers
    treat empty text as "nothing readable" rather than crashing the whole
    pipeline over one bad image.
    """
    if _is_pdf(image_path):
        return _extract_pdf(image_path)

    try:
        with Image.open(image_path) as img:
            data = pytesseract.image_to_data(
                img, output_type=pytesseract.Output.DICT
            )
    except Exception:
        logger.exception("Tesseract OCR failed for %s", image_path)
        return OcrResult(text="", words=[])

    return _rows_to_result(data)


def _rows_to_result(data: dict) -> OcrResult:
    """Folds Tesseract's per-word table into text plus confidences."""
    words: List[OcrWord] = []
    # Line structure carries meaning the LLM stage depends on — one medicine
    # (or one lab value and its reference range) per line — so it's rebuilt
    # from Tesseract's own layout numbering rather than flattening the page
    # into one run of words.
    lines: Dict[tuple, List[str]] = {}
    rows = zip(
        data.get("text", []),
        data.get("conf", []),
        data.get("block_num", []),
        data.get("par_num", []),
        data.get("line_num", []),
    )
    for raw_text, raw_conf, block, par, line in rows:
        text = (raw_text or "").strip()
        if not text:
            continue
        try:
            conf = float(raw_conf)
        except (TypeError, ValueError):
            continue
        # Tesseract reports -1 for boxes it found no text in; those rows are
        # layout blocks, not words, so they carry no confidence signal.
        if conf < 0:
            continue
        words.append(OcrWord(text=text, confidence=conf / 100.0))
        lines.setdefault((block, par, line), []).append(text)

    text = "\n".join(" ".join(line) for line in lines.values())
    return OcrResult(text=text, words=words)


def extract_text(image_path: str) -> str:
    """Text-only view of [extract], for callers that don't need confidence."""
    return extract(image_path).text


# ── Per-field confidence ────────────────────────────────────────────────
#
# Tesseract scores *words*; the pipeline emits *fields* that an LLM rewrote
# out of those words. [field_confidence] bridges the two by matching each
# token of a field value back to the OCR word it most likely came from and
# inheriting that word's confidence, discounted by how well the two match.
# A field the LLM inferred rather than read (no matching word at all) scores
# 0 — which is the honest answer: nothing on the page supports it.

_TOKEN_RE = re.compile(r"[a-z0-9]+")

# Below this the two tokens are different words, not an OCR variant of one
# word ("amoxycillin" vs "amoxicillin" passes; "aspirin" vs "atorvastatin"
# does not).
_MIN_TOKEN_MATCH = 0.72

# Short tokens fuzzy-match almost anything, so they must match exactly.
_EXACT_MATCH_MAX_LEN = 3

# A misread drug name or strength is the dangerous failure mode of this
# whole feature, so those are scored on their weakest token and held to a
# higher bar; everything else is scored on the average and held to a lower
# one.
#
# `raw_name` is deliberately NOT strict even though it is a name. It's the
# whole printed phrase — "Tab Amoxicillin 500mg", "3. Cap Pantoprazole 40mg"
# — so weakest-token scoring hands the verdict to the noise words around the
# drug, not the drug. Measured on a clean render: Pantoprazole scored 0.28 on
# `raw_name` against 0.71 on `normalized_name`, purely because Tesseract was
# unsure about "Cap". `normalized_name` is the field that carries the
# clinical meaning, and it's the one that gates.
STRICT_FIELDS = frozenset({"normalized_name", "strength"})

# Calibrated against real Tesseract output rather than picked a priori, and
# these numbers only mean anything relative to it. Over two end-to-end runs
# of the same prescription:
#
#   legible capture, all four names read correctly -> 0.71 … 0.95
#   degraded capture (one name genuinely misread)  -> 0.37 … 0.77
#
# 0.70 is the seam between those. Note what this signal is and isn't: it
# tracks how well the page supports the text, which is essentially image
# quality — in the degraded run a correctly-read name scored 0.37 while the
# misread one scored 0.58, so it does NOT rank correct above incorrect
# within a capture. What it does reliably is separate "nothing on the page
# supports this" (0.0, a fabricated medicine) from a real read, and flag
# regions the OCR struggled with. Asking the patient about a hard-to-read
# region is the whole point; predicting which specific letter went wrong is
# beyond any confidence number.
STRICT_THRESHOLD = 0.70
LOOSE_THRESHOLD = 0.60


def _tokens(value: str) -> List[str]:
    return _TOKEN_RE.findall(value.lower())


def _match_ratio(a: str, b: str) -> float:
    """Similarity of two alphanumeric runs, 0 when they're too short to
    fuzzy-match safely (a 2–3 character token resembles far too much)."""
    if len(a) <= _EXACT_MATCH_MAX_LEN or len(b) <= _EXACT_MATCH_MAX_LEN:
        return 1.0 if a == b else 0.0
    return SequenceMatcher(None, a, b).ratio()


def _token_confidence(token: str, words: Sequence[OcrWord]) -> float:
    """Best confidence-weighted match for [token] across the OCR words."""
    best = 0.0
    for word in words:
        for word_token in _tokens(word.text):
            ratio = _match_ratio(token, word_token)
            if ratio < _MIN_TOKEN_MATCH:
                continue
            best = max(best, word.confidence * ratio)
    return best


def _joined_confidence(tokens: Sequence[str], words: Sequence[OcrWord]) -> float:
    """Best match for the field value with word boundaries ignored.

    OCR splits and merges words unpredictably — "500mg" on the page becomes
    the field value "500 mg", whose tokens ("500", "mg") are both too short
    to match anything on their own. Comparing the run-together forms of both
    sides recovers those cases.
    """
    if not tokens:
        return 0.0
    joined = "".join(tokens)
    best = 0.0
    # Single words plus adjacent pairs, which covers the merge/split in
    # either direction without quadratic blowup on a full page of text.
    for i, word in enumerate(words):
        spans = [(_tokens(word.text), word.confidence)]
        if i + 1 < len(words):
            nxt = words[i + 1]
            spans.append(
                (
                    _tokens(word.text) + _tokens(nxt.text),
                    min(word.confidence, nxt.confidence),
                )
            )
        for span_tokens, confidence in spans:
            ratio = _match_ratio(joined, "".join(span_tokens))
            if ratio < _MIN_TOKEN_MATCH:
                continue
            best = max(best, confidence * ratio)
    return best


def field_confidence(
    value: object, words: Sequence[OcrWord], *, strict: bool
) -> float:
    """Confidence (0–1) that [value] is what the page actually says.

    [strict] picks the aggregate: the weakest token for fields where one
    wrong token changes the drug or the dose, the mean for descriptive
    fields where the LLM legitimately paraphrases ("TDS" -> "3 times a
    day") and a partial match is still a good sign.
    """
    tokens = _tokens(str(value)) if value is not None else []
    if not tokens or not words:
        return 0.0
    scores = [_token_confidence(t, words) for t in tokens]
    per_token = min(scores) if strict else sum(scores) / len(scores)
    return max(per_token, _joined_confidence(tokens, words))


def medicine_field_confidence(
    medicine: dict, words: Sequence[OcrWord]
) -> Dict[str, float]:
    """Per-field confidence for one structured medicine. Fields the LLM left
    null are omitted rather than scored 0 — "not stated" is not the same
    problem as "stated but unreadable", and only the latter needs review.
    """
    scored: Dict[str, float] = {}
    for name in (
        "raw_name",
        "normalized_name",
        "strength",
        "frequency",
        "duration_days",
        "instructions",
    ):
        value = medicine.get(name)
        if value is None or str(value).strip() == "":
            continue
        scored[name] = round(
            field_confidence(value, words, strict=name in STRICT_FIELDS), 3
        )
    return scored


def low_confidence_fields(scored: Dict[str, float]) -> List[str]:
    """Every field the patient should be asked to look at. Drives the
    highlighting in the review UI."""
    return [
        name
        for name, value in scored.items()
        if value < (STRICT_THRESHOLD if name in STRICT_FIELDS else LOOSE_THRESHOLD)
    ]


def blocking_fields(scored: Dict[str, float]) -> List[str]:
    """The subset of [low_confidence_fields] that actually holds up risk
    analysis: an uncertain drug name or strength.

    Descriptive fields are deliberately excluded. A frequency written
    "1-0-1" is legitimately restructured into "twice daily" with nothing on
    the page textually supporting the new wording, so those score low on
    almost every real prescription — blocking on them would make the gate
    fire constantly and train patients to click through it, which is worse
    than not having a gate. A wrong *name* is the failure that matters.

    They stay in [low_confidence_fields] regardless, so the review UI still
    highlights them; the difference is only whether risk analysis waits.
    """
    return [name for name in low_confidence_fields(scored) if name in STRICT_FIELDS]


async def structure_medicines(raw_text: str) -> Optional[List[dict]]:
    """Turns [raw_text] into structured medicine dicts using the local model.

    Returns None (not an empty list) when the call itself failed, so callers
    can tell "LLM unavailable" apart from "genuinely no medicines found" —
    the same checked/unchecked distinction /interactions/check makes.
    """
    if not raw_text.strip():
        return []

    parsed = await llm.chat_json(
        _STRUCTURE_SYSTEM_PROMPT, raw_text, max_tokens=1200
    )
    if parsed is None:
        return None

    medicines = parsed.get("medicines")
    if not isinstance(medicines, list):
        logger.error("Medicine structuring returned no usable list: %s", parsed)
        return None
    return [m for m in medicines if isinstance(m, dict)]


_REPORT_SYSTEM_PROMPT = """You extract structured data from raw OCR text of \
a lab/diagnostic report (blood test, lipid panel, thyroid panel, etc). The \
text may be messy, have OCR errors, or be missing punctuation — do your \
best with what's there.

For each test value you can identify, extract:
- label: the test name as it appears (e.g. "LDL Cholesterol", "TSH", "HbA1c")
- value: the numeric result (a number, not a string)
- unit: the unit if stated (e.g. "mg/dL", "mIU/L"), else null
- ref_low: the lower bound of the reference/normal range if stated, else null
- ref_high: the upper bound of the reference/normal range if stated, else null

Then write:
- summary: one or two plain-language sentences describing the overall \
picture (e.g. "Most values are within range; cholesterol is mildly elevated.")
- findings: a list of notable results, each with a severity of exactly \
"info", "caution", or "severe" (only use "severe" for values seriously \
outside the reference range or a critical flag on the report itself), a \
short text description, and an optional one-sentence explanation of what \
it means
- advice: for EVERY value that falls outside its own stated reference \
range, one practical, specific, actionable recommendation grounded in that \
exact value and how far out of range it is — not generic boilerplate. \
Include a "label" (which value this is about), "direction" ("Lower" or \
"Raise"), and "advice" (1-2 sentences of concrete, practical guidance: \
diet, lifestyle, or when to see a doctor). If nothing is out of range, \
return an empty advice list.

Never invent a value, reference range, or finding that isn't actually in \
the text — use null rather than guessing at a reference range if the report \
doesn't state one, and skip the finding/advice for that value rather than \
fabricating a threshold. This is health information a patient will read, \
so precision matters more than completeness. If the text doesn't look like \
a lab report at all, return empty lists for metrics/findings/advice and say \
so plainly in the summary.

You are not a doctor and must never state or imply a diagnosis — describe \
what the numbers show and general next steps, always deferring anything \
that sounds like a medical decision to the patient's own doctor.

Respond with ONLY a JSON object, no other text, matching exactly this shape:
{
  "summary": "<string>",
  "metrics": [
    {"label": "<string>", "value": <number>, "unit": "<string or null>",
     "ref_low": <number or null>, "ref_high": <number or null>}
  ],
  "findings": [
    {"severity": "info" | "caution" | "severe", "text": "<string>",
     "explanation": "<string or null>"}
  ],
  "advice": [
    {"label": "<string>", "direction": "Lower" | "Raise", "advice": "<string>"}
  ]
}"""


# How much report text goes into one structuring call.
#
# This is the most important number in this module. A real multi-page lab PDF
# runs to ~12k characters, and handing all of it over in one call returns an
# *empty* result: the model is served a context window far smaller than its
# 32k maximum (Ollama's default), the input is silently truncated, and what
# survives isn't a report any more. It fails quietly — valid JSON with empty
# arrays — which is indistinguishable from "this document has no lab values"
# unless you go looking.
#
# Measured on a real 6-page panel: 12,010 chars -> 0 metrics; 3,000 -> 3;
# 1,500 -> 2. Small inputs also extract more densely, because the model isn't
# trying to hold six pages at once.
#
# Chunking rather than raising the server's context window keeps this working
# against any OpenAI-compatible backend (vLLM, LM Studio, llama.cpp), which is
# the portability `config.py` is explicitly written for.
_MAX_REPORT_CHARS_PER_CALL = 2800

_SUMMARY_SYSTEM_PROMPT = """You write one or two plain-language sentences \
describing the overall picture of a set of lab results. You are given the \
already-extracted values as JSON. Say what is outside its reference range and \
what is normal. Be accurate about direction: a value above its reference high \
is HIGH, below its reference low is LOW — never describe a high value as low. \
You are not a doctor and must never state or imply a diagnosis. Respond with \
ONLY a JSON object: {"summary": "<string>"}"""


def _chunk_report(text: str, limit: int) -> List[str]:
    """Splits [text] into chunks of at most [limit] characters, breaking only
    on line boundaries.

    Lab reports are line-oriented — one test, its value and its reference
    range per line — so splitting mid-line would hand the model a value whose
    range lives in the next chunk, and it would either invent one or drop the
    row entirely.
    """
    chunks: List[str] = []
    current: List[str] = []
    size = 0
    for line in text.splitlines():
        if size + len(line) + 1 > limit and current:
            chunks.append("\n".join(current))
            current, size = [], 0
        current.append(line)
        size += len(line) + 1
    if current:
        chunks.append("\n".join(current))
    return chunks or [text]


def _merge_report_parts(parts: List[dict]) -> dict:
    """Unions the per-chunk results, keeping the first occurrence of each.

    Pages repeat headers and footers, and a test can appear twice (once in a
    table, once in an interpretation block), so dedupe by the identity a
    reader would use: the test's own label.
    """
    metrics: List[dict] = []
    findings: List[dict] = []
    advice: List[dict] = []
    seen_metric: set = set()
    seen_finding: set = set()
    seen_advice: set = set()

    for part in parts:
        for m in part.get("metrics") or []:
            key = str(m.get("label") or "").strip().lower()
            if not key or key in seen_metric:
                continue
            seen_metric.add(key)
            metrics.append(m)
        for f in part.get("findings") or []:
            key = str(f.get("text") or "").strip().lower()
            if not key or key in seen_finding:
                continue
            seen_finding.add(key)
            findings.append(f)
        for a in part.get("advice") or []:
            key = str(a.get("label") or "").strip().lower()
            if not key or key in seen_advice:
                continue
            seen_advice.add(key)
            advice.append(a)

    return {
        "summary": "",
        "metrics": metrics,
        "findings": findings,
        "advice": advice,
    }


async def structure_report(raw_text: str) -> Optional[dict]:
    """Turns [raw_text] into a structured report analysis using the local
    model. Returns None when the call itself failed — same
    checked/unchecked distinction as [structure_medicines].

    Long reports are processed a chunk at a time and merged; see
    [_MAX_REPORT_CHARS_PER_CALL] for why one big call cannot work.
    """
    if not raw_text.strip():
        return {"summary": "", "metrics": [], "findings": [], "advice": []}

    chunks = _chunk_report(raw_text, _MAX_REPORT_CHARS_PER_CALL)

    if len(chunks) == 1:
        return await llm.chat_json(
            _REPORT_SYSTEM_PROMPT, raw_text, max_tokens=1800
        )

    logger.info(
        "Report is %s chars — structuring in %s chunks.",
        len(raw_text),
        len(chunks),
    )

    parts: List[dict] = []
    for index, chunk in enumerate(chunks):
        part = await llm.chat_json(
            _REPORT_SYSTEM_PROMPT, chunk, max_tokens=1800
        )
        if part is None:
            # One bad chunk shouldn't lose the whole report — the other pages
            # still carry real values.
            logger.warning(
                "Chunk %s of %s failed to structure.", index + 1, len(chunks)
            )
            continue
        parts.append(part)

    if not parts:
        return None

    merged = _merge_report_parts(parts)

    # The per-chunk summaries each describe one page, so they can't be
    # concatenated. One final pass over the merged values describes the report
    # as a whole — a small, fast call, because the input is now just numbers.
    if merged["metrics"]:
        summary = await llm.chat_json(
            _SUMMARY_SYSTEM_PROMPT,
            json.dumps({"metrics": merged["metrics"]}),
            max_tokens=300,
        )
        if summary:
            merged["summary"] = str(summary.get("summary") or "")

    if not merged["summary"]:
        # Rather than ship a blank summary, fall back to the first chunk that
        # produced one.
        for part in parts:
            text = str(part.get("summary") or "").strip()
            if text:
                merged["summary"] = text
                break

    return merged


def aggregate_confidence(scored_fields: Sequence[Dict[str, float]]) -> float:
    """Record-level confidence: the mean of every scored field across every
    medicine. Only a summary for display — the per-field numbers are what
    the review gate actually acts on.
    """
    values = [v for scored in scored_fields for v in scored.values()]
    if not values:
        return 0.0
    return round(sum(values) / len(values), 3)


def estimate_report_confidence(raw_text: str, metrics: List[dict]) -> float:
    """Same honest-heuristic approach as [estimate_confidence], applied to
    report metrics instead of medicines."""
    if not metrics:
        return 0.0
    return 0.85 if len(raw_text.strip()) > 20 else 0.5
