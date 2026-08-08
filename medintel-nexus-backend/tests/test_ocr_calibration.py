"""End-to-end calibration against a real Tesseract run.

The thresholds in `ocr.py` are only meaningful relative to the confidence
numbers Tesseract actually produces, and those aren't something unit tests
with hand-written scores can pin down. This renders a legible prescription,
runs the real engine over it, and asserts the two properties the whole
feature rests on:

  * a medicine that IS on the page doesn't nag the patient, and
  * a medicine that ISN'T on the page cannot slip through unconfirmed.

Skipped where the Tesseract binary isn't installed, so it doesn't turn into
a broken build on a machine that only runs the Flutter side.
"""

import shutil

import pytest

from app import ocr

pytestmark = pytest.mark.skipif(
    shutil.which("tesseract") is None, reason="Tesseract binary not installed"
)

_FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"


@pytest.fixture(scope="module")
def prescription(tmp_path_factory):
    Image = pytest.importorskip("PIL.Image", reason="Pillow not installed")
    from PIL import ImageDraw, ImageFont

    try:
        font = ImageFont.truetype(_FONT, 28)
    except OSError:
        pytest.skip("No TrueType font available to render a test prescription")

    image = Image.new("RGB", (1100, 340), "white")
    draw = ImageDraw.Draw(image)
    for i, line in enumerate(
        [
            "City Care Clinic",
            "1. Tab Amoxicillin 500mg  1-0-1  x 5 days",
            "2. Tab Paracetamol 650mg  SOS  after food",
            "3. Cap Pantoprazole 40mg  1-0-0  before breakfast",
        ]
    ):
        draw.text((30, 30 + i * 60), line, fill="black", font=font)

    path = tmp_path_factory.mktemp("ocr") / "prescription.png"
    image.save(path)
    return ocr.extract(str(path))


def test_legible_medicine_does_not_ask_for_confirmation(prescription):
    """The cost of a gate is that patients click through it. It has to stay
    quiet on the reads that were fine."""
    scored = ocr.medicine_field_confidence(
        {
            "raw_name": "Amoxicillin 500mg",
            "normalized_name": "Amoxicillin",
            "strength": "500 mg",
        },
        prescription.words,
    )

    assert ocr.blocking_fields(scored) == []


def test_medicine_absent_from_the_page_always_blocks(prescription):
    """The failure this feature exists for: the LLM emits a drug that was
    never on the prescription. Nothing supports it, so it cannot pass."""
    scored = ocr.medicine_field_confidence(
        {"raw_name": "Warfarin 5mg", "normalized_name": "Warfarin",
         "strength": "5 mg"},
        prescription.words,
    )

    assert scored["normalized_name"] == 0.0
    assert "normalized_name" in ocr.blocking_fields(scored)


def test_line_structure_survives_extraction(prescription):
    """The LLM stage reads one medicine per line; flattening the page into a
    single run of words would lose that."""
    lines = [line for line in prescription.text.splitlines() if line.strip()]

    assert len(lines) == 4
    assert "Amoxicillin" in lines[1]
    assert "Pantoprazole" in lines[3]
