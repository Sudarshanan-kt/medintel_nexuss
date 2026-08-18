"""Numeric coercion of model-supplied lab metrics.

Reference ranges are the field the model most often answers in prose: a
report that prints "< 200" comes back as the string ``"< 200"``, because
that is genuinely what the bound is. ``MetricOut`` types the bound as
``Optional[float]``, and one ValidationError fails the whole response — so
a single cholesterol row used to turn ``GET /reports/{id}/analysis`` into a
500 with every other metric on the report collapsing alongside it.
"""

import pytest

from app.routers.reports import MetricOut
from app.store import _to_metric_out, _to_number


@pytest.mark.parametrize(
    "raw, expected",
    [
        # The shapes that actually broke it: an upper bound written as a
        # comparison. The number is the bound either way round, so taking
        # the first one is right for ref_high ("< 200") and ref_low ("> 40").
        ("< 200", 200.0),
        ("<100", 100.0),
        ("> 40", 40.0),
        ("≤ 150", 150.0),
        # Grouped digits and trailing units, both common in lab printouts.
        ("145,000", 145000.0),
        ("11.2 g/dL", 11.2),
        # Already numeric — the common case, unchanged.
        (243, 243.0),
        (11.2, 11.2),
        (-1.5, -1.5),
        # Nothing measurable in it: an absent bound, which the field allows.
        (None, None),
        ("", None),
        ("normal", None),
        ("N/A", None),
        # bool is an int subclass, so this would otherwise coerce to 1.0.
        (True, None),
    ],
)
def test_to_number(raw, expected) -> None:
    assert _to_number(raw) == expected


def test_comparison_bound_survives_the_response_model() -> None:
    """The exact row that used to 500 the endpoint."""
    row = _to_metric_out(
        {
            "label": "Total Cholesterol",
            "value": 243,
            "unit": "mg/dL",
            "ref_low": None,
            "ref_high": "< 200",
        }
    )

    assert MetricOut(**row).model_dump() == {
        "label": "Total Cholesterol",
        "value": 243.0,
        "unit": "mg/dL",
        "ref_low": None,
        "ref_high": 200.0,
    }


def test_unparseable_bound_does_not_sink_the_metric() -> None:
    """A bound the model wrote as prose costs that bound, not the row."""
    row = _to_metric_out(
        {"label": "Hemoglobin", "value": "11.2", "unit": "g/dL",
         "ref_low": "see notes", "ref_high": "see notes"}
    )
    metric = MetricOut(**row)

    assert metric.value == 11.2
    assert metric.ref_low is None
    assert metric.ref_high is None
