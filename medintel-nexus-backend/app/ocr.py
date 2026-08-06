"""Real prescription OCR: Tesseract for text extraction, Groq for
structuring the raw text into medicine fields.

Why this split instead of one OCR-and-structure call: Tesseract reads pixels
into text but has no idea what a "frequency" or "duration" is — it just
extracts what's printed. An LLM is good at the opposite job (turning messy
free text into a fixed schema) but not at reading pixels at all. Chaining
them plays to what each is actually good at, and both are free — Tesseract
runs locally (no per-request cost), and this reuses the same Groq account
the Flutter assistant and the /interactions/check route already use.

Honest limitation, not a bug to "fix" later: Tesseract (like every OCR
engine, including paid ones) is unreliable on messy handwriting. It works
well on printed/typed prescriptions and pharmacy labels; a doctor's fast
cursive handwriting will often come out garbled, the same way it would with
Google Cloud Vision or AWS Textract. There's no free-vs-paid fix for that —
it's a fundamental limit of OCR on handwriting, not a quality gap this code
should try to paper over with a fake confidence number.
"""

import json
import logging
from typing import List, Optional

import httpx
import pytesseract
from PIL import Image

from app.config import settings

logger = logging.getLogger(__name__)

_GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
_GROQ_MODEL = "llama-3.3-70b-versatile"

_STRUCTURE_SYSTEM_PROMPT = """You extract structured medicine entries from \
raw OCR text of a prescription. The text may be messy, have OCR errors, or \
be missing punctuation — do your best with what's there.

For each distinct medicine you can identify, extract:
- raw_name: the medicine name as it literally appears (including strength \
if written together, e.g. "Amoxicillin 500mg")
- normalized_name: just the drug name, no strength/dosage (e.g. "Amoxicillin")
- strength: the dose per unit if stated (e.g. "500 mg"), else null
- frequency: how often it's taken if stated (e.g. "3 times a day", "twice \
daily"), else null
- duration_days: number of days if stated, else null
- instructions: any other instruction if stated (e.g. "after food"), else null

Never invent a medicine that isn't actually in the text, and never invent a \
field value that isn't stated or clearly implied — use null rather than \
guessing. If the text doesn't look like a prescription at all, or no \
medicines can be identified, return an empty list.

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


def extract_text(image_path: str) -> str:
    """Runs Tesseract on the image at [image_path]. Returns "" (not an
    exception) on any failure — callers treat empty text as "nothing
    readable" rather than crashing the whole pipeline over one bad image.
    """
    try:
        with Image.open(image_path) as img:
            return pytesseract.image_to_string(img)
    except Exception:
        logger.exception("Tesseract OCR failed for %s", image_path)
        return ""


async def structure_medicines(raw_text: str) -> Optional[List[dict]]:
    """Calls Groq to turn [raw_text] into structured medicine dicts. Returns
    None (not an empty list) when the call itself failed, so callers can
    tell "LLM unavailable" apart from "genuinely no medicines found" — the
    same checked/unchecked distinction /interactions/check already makes.
    """
    if not settings.groq_api_key:
        return None
    if not raw_text.strip():
        return []

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            res = await client.post(
                _GROQ_ENDPOINT,
                headers={
                    "Authorization": f"Bearer {settings.groq_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": _GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": _STRUCTURE_SYSTEM_PROMPT},
                        {"role": "user", "content": raw_text},
                    ],
                    "temperature": 0.1,
                    "max_tokens": 1200,
                    "response_format": {"type": "json_object"},
                },
            )
        res.raise_for_status()
        content = res.json()["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        return parsed.get("medicines", [])
    except Exception:
        logger.exception("Groq medicine structuring failed")
        return None


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


async def structure_report(raw_text: str) -> Optional[dict]:
    """Calls Groq to turn [raw_text] into a structured report analysis.
    Returns None when the call itself failed (no key / request error) —
    same checked/unchecked distinction as [structure_medicines].
    """
    if not settings.groq_api_key:
        return None
    if not raw_text.strip():
        return {"summary": "", "metrics": [], "findings": [], "advice": []}

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            res = await client.post(
                _GROQ_ENDPOINT,
                headers={
                    "Authorization": f"Bearer {settings.groq_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": _GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": _REPORT_SYSTEM_PROMPT},
                        {"role": "user", "content": raw_text},
                    ],
                    "temperature": 0.1,
                    "max_tokens": 1800,
                    "response_format": {"type": "json_object"},
                },
            )
        res.raise_for_status()
        content = res.json()["choices"][0]["message"]["content"]
        return json.loads(content)
    except Exception:
        logger.exception("Groq report structuring failed")
        return None


def estimate_confidence(raw_text: str, medicines: List[dict]) -> float:
    """Rough, honest confidence signal — not from Tesseract (whose own
    per-word confidence API is noisy) but from a simple heuristic: found
    at least one medicine, from non-trivial text. This deliberately isn't
    dressed up as more precise than it is.
    """
    if not medicines:
        return 0.0
    return 0.85 if len(raw_text.strip()) > 20 else 0.5


def estimate_report_confidence(raw_text: str, metrics: List[dict]) -> float:
    """Same honest-heuristic approach as [estimate_confidence], applied to
    report metrics instead of medicines."""
    if not metrics:
        return 0.0
    return 0.85 if len(raw_text.strip()) > 20 else 0.5
