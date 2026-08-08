"""Per-field OCR confidence: does a shaky read get flagged, and does a
clean one get through without nagging the patient?"""

from app import ocr


def _words(*pairs: tuple[str, int]) -> list[ocr.OcrWord]:
    """Tesseract-shaped words, confidences given as percentages."""
    return [ocr.OcrWord(text, conf / 100) for text, conf in pairs]


def test_clean_read_needs_no_confirmation() -> None:
    words = _words(("Paracetamol", 96), ("650", 97), ("mg", 95))
    scored = ocr.medicine_field_confidence(
        {"raw_name": "Paracetamol 650 mg", "normalized_name": "Paracetamol",
         "strength": "650 mg"},
        words,
    )

    assert ocr.blocking_fields(scored) == []
    assert scored["normalized_name"] > ocr.STRICT_THRESHOLD


def test_garbled_name_blocks() -> None:
    """Tesseract itself reported low confidence on the drug name — that has
    to reach the patient rather than being averaged away."""
    words = _words(("Tab.", 95), ("Amoxycillin", 42), ("500mg", 88))
    scored = ocr.medicine_field_confidence(
        {"raw_name": "Amoxicillin 500mg", "normalized_name": "Amoxicillin",
         "strength": "500 mg"},
        words,
    )

    assert "normalized_name" in ocr.blocking_fields(scored)


def test_strength_matches_across_ocr_word_boundaries() -> None:
    """"500mg" on the page becomes the field value "500 mg"; both tokens are
    too short to match alone, so the run-together comparison has to carry it."""
    scored = ocr.medicine_field_confidence(
        {"raw_name": "X", "strength": "500 mg"}, _words(("500mg", 88))
    )

    assert scored["strength"] > ocr.STRICT_THRESHOLD


def test_rephrased_frequency_is_flagged_but_never_blocks() -> None:
    """"1-0-1" legitimately becomes "twice daily" with nothing on the page
    textually supporting the new wording. Worth a look, not worth a gate —
    blocking here would fire on nearly every real prescription."""
    scored = ocr.medicine_field_confidence(
        {"raw_name": "Paracetamol", "frequency": "twice daily"},
        _words(("Paracetamol", 96), ("1-0-1", 92)),
    )

    assert "frequency" in ocr.low_confidence_fields(scored)
    assert "frequency" not in ocr.blocking_fields(scored)


def test_fields_the_prescription_never_stated_are_not_scored() -> None:
    """"Not stated" is not the same problem as "stated but unreadable", and
    only the latter is something a patient can resolve."""
    scored = ocr.medicine_field_confidence(
        {"raw_name": "Paracetamol", "instructions": None, "strength": ""},
        _words(("Paracetamol", 96)),
    )

    assert "instructions" not in scored
    assert "strength" not in scored


def test_confidence_is_zero_when_nothing_was_read() -> None:
    scored = ocr.medicine_field_confidence(
        {"raw_name": "Paracetamol", "normalized_name": "Paracetamol"}, []
    )

    assert scored["normalized_name"] == 0.0
    assert ocr.blocking_fields(scored) == ["normalized_name"]


def test_a_noise_word_in_the_printed_phrase_cannot_gate_the_scan() -> None:
    """`raw_name` is the whole printed line — "Cap Pantoprazole 40mg" — so
    weakest-token scoring would hand the verdict to "Cap" rather than to the
    drug. On a real clean render that dropped raw_name to 0.28 while the drug
    name itself sat at 0.71, which held up a prescription that had been read
    perfectly well. It's averaged and non-gating for exactly that reason."""
    words = _words(("Cap", 28), ("Pantoprazole", 91), ("40mg", 95))
    scored = ocr.medicine_field_confidence(
        {
            "raw_name": "Cap Pantoprazole 40mg",
            "normalized_name": "Pantoprazole",
            "strength": "40 mg",
        },
        words,
    )

    # The low-confidence prefix is averaged out, not amplified...
    assert scored["raw_name"] > 0.5
    # ...and either way it can never be what holds up the safety check.
    assert "raw_name" not in ocr.blocking_fields(scored)
    assert ocr.blocking_fields(scored) == []
