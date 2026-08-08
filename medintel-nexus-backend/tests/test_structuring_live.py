"""Field separation, against the real local model.

The structuring prompt's job is to split a prescription line into fields
that stay in their lanes — the rhythm in `frequency`, the course length in
`duration_days`, everything else in `instructions`. A small local model gets
this wrong without explicit instruction: before the prompt carried worked
examples it returned frequency="1-0-1 xS5Sdays after food", swallowing two
other fields.

Keeping `frequency` verbatim matters beyond tidiness. Field confidence is
measured by matching the value back to the words Tesseract read, so a
paraphrase ("2 times a day" for a page that says "BD") has nothing on the
page supporting it and scores 0 — every frequency would be flagged.

Skipped unless both Tesseract and the model are actually available; this is
the one test that needs inference running, so it stays opt-in rather than
becoming a broken build on a machine without it.
"""

import asyncio
import shutil

import pytest

from app import llm, ocr

_FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"

# Deliberately shares nothing with the worked examples in the prompt —
# different drugs, different notation (BD/OD/TDS rather than 1-0-1), a
# liquid dosed in ml. A prompt tuned onto its own examples passes those and
# fails this.
_LINES = [
    "APOLLO POLYCLINIC",
    "1)  Tab Metformin 850 mg          BD          for 30 days   with meals",
    "2)  Cap Omeprazole 20 mg          TDS         for 14 days   empty stomach",
    "3)  Syp Lactulose 15 ml           0-0-1       SOS constipation",
]


def _model_available() -> bool:
    if shutil.which("tesseract") is None:
        return False
    try:
        return asyncio.run(llm.health())
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _model_available(),
    reason="Needs Tesseract and a running local model (`ollama serve`)",
)


@pytest.fixture(scope="module")
def medicines(tmp_path_factory):
    Image = pytest.importorskip("PIL.Image", reason="Pillow not installed")
    from PIL import ImageDraw, ImageFont

    try:
        font = ImageFont.truetype(_FONT, 30)
    except OSError:
        pytest.skip("No TrueType font available to render a test prescription")

    image = Image.new("RGB", (1300, 60 + len(_LINES) * 54), "white")
    draw = ImageDraw.Draw(image)
    for i, line in enumerate(_LINES):
        draw.text((36, 28 + i * 54), line, fill="black", font=font)

    path = tmp_path_factory.mktemp("rx") / "prescription.png"
    image.save(path)

    extracted = asyncio.run(ocr.structure_medicines(ocr.extract(str(path)).text))
    assert extracted, "the model returned no medicines at all"
    return {
        (m.get("normalized_name") or "").lower(): m for m in extracted
    }


def _get(medicines, name):
    match = next((m for k, m in medicines.items() if name in k), None)
    if match is None:
        pytest.fail(f"{name!r} was not extracted; got {list(medicines)}")
    return match


def test_frequency_holds_only_the_dosing_rhythm(medicines):
    """The regression this prompt was tuned for: no duration, no food
    instruction, no trailing remainder of the line."""
    for name, expected in (("metformin", "BD"), ("omeprazole", "TDS")):
        frequency = (_get(medicines, name).get("frequency") or "")
        assert expected.lower() in frequency.lower()
        for leaked in ("day", "meal", "stomach", "constipation"):
            assert leaked not in frequency.lower(), (
                f"{name} frequency={frequency!r} swallowed another field"
            )


def test_course_length_lands_in_duration_days(medicines):
    assert _get(medicines, "metformin")["duration_days"] == 30
    assert _get(medicines, "omeprazole")["duration_days"] == 14


def test_an_open_ended_course_has_no_duration(medicines):
    """"SOS" is not a course length — guessing one would invent a fact."""
    assert _get(medicines, "lactulose")["duration_days"] is None


def test_a_liquid_keeps_its_volume_unit(medicines):
    """Syrups are dosed in ml, not mg. The prompt originally implied mg and
    this came back null."""
    assert "15" in (_get(medicines, "lactulose").get("strength") or "")


def test_the_form_prefix_is_dropped_from_the_drug_name(medicines):
    """"Tab"/"Cap"/"Syp" are packaging, not the drug — and they drag the
    confidence score down when left in a field that gates."""
    for name in ("metformin", "omeprazole", "lactulose"):
        normalized = (_get(medicines, name).get("normalized_name") or "").lower()
        assert not normalized.startswith(("tab", "cap", "syp"))
