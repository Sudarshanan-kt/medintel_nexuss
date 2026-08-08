"""The human-in-the-loop gate: risk analysis must not run on medicines the
patient hasn't confirmed."""

import pytest
from fastapi.testclient import TestClient

from app import store
from app.config import settings
from app.security import DEV_USER_ID
from main import app

client = TestClient(app)
AUTH = {"Authorization": "Bearer dev"}


@pytest.fixture(autouse=True)
def dev_auth(monkeypatch: pytest.MonkeyPatch):
    """Runs these tests as DEV_USER_ID; Supabase JWT verification is covered
    separately by test_health."""
    monkeypatch.setattr(settings, "auth_disabled", True)


@pytest.fixture
def unverified_prescription():
    record = store.PrescriptionRecord(
        id="rx_test_unverified",
        user_id=DEV_USER_ID,
        status="analyzed",
        medicines=[
            {
                "id": "m_1",
                "raw_name": "Amoxicillin 500mg",
                "normalized_name": "Amoxicillin",
                "strength": "500 mg",
                "frequency": None,
                "duration_days": None,
                "instructions": None,
                "field_confidence": {"normalized_name": 0.41},
                "low_confidence_fields": ["normalized_name"],
                "blocking_fields": ["normalized_name"],
                "user_corrected": False,
            },
            {
                "id": "m_2",
                "raw_name": "Warfarin 5mg",
                "normalized_name": "Warfarin",
                "strength": "5 mg",
                "frequency": None,
                "duration_days": None,
                "instructions": None,
                "field_confidence": {"normalized_name": 0.93},
                "low_confidence_fields": [],
                "blocking_fields": [],
                "user_corrected": False,
            },
        ],
    )
    store._prescriptions[record.id] = record
    yield record
    store._prescriptions.pop(record.id, None)


def test_unverified_prescription_reports_needing_review(unverified_prescription):
    res = client.get(f"/api/v1/prescriptions/{unverified_prescription.id}", headers=AUTH)

    assert res.status_code == 200
    summary = res.json()["data"]["prescription"]
    assert summary["needs_review"] is True
    assert summary["verified"] is False
    assert summary["blocking_field_count"] == 1


def test_interaction_check_refuses_unverified_prescription(unverified_prescription):
    res = client.post(
        "/api/v1/interactions/check",
        json={"prescription_id": unverified_prescription.id},
        headers=AUTH,
    )

    assert res.status_code == 409
    assert "confirm" in res.json()["error"]["message"].lower()


def test_client_cannot_route_around_the_gate_with_raw_names(unverified_prescription):
    """Passing prescription_id must not be optional-in-practice: a client
    that posts the names directly alongside it still gets refused, because
    the server reads its own record rather than the request body."""
    res = client.post(
        "/api/v1/interactions/check",
        json={
            "prescription_id": unverified_prescription.id,
            "medicine_names": ["Amoxicillin", "Warfarin"],
        },
        headers=AUTH,
    )

    assert res.status_code == 409


def test_verify_unlocks_the_check_and_records_corrections(unverified_prescription):
    res = client.post(
        f"/api/v1/prescriptions/{unverified_prescription.id}/verify",
        json={
            "medicines": [
                # The patient corrected what OCR misread...
                {"id": "m_1", "raw_name": "Amoxicillin 250mg",
                 "normalized_name": "Amoxicillin", "strength": "250 mg"},
                # ...and accepted the other untouched.
                {"id": "m_2", "raw_name": "Warfarin 5mg",
                 "normalized_name": "Warfarin", "strength": "5 mg"},
            ]
        },
        headers=AUTH,
    )

    assert res.status_code == 200
    data = res.json()["data"]
    assert data["prescription"]["verified"] is True
    assert data["prescription"]["needs_review"] is False

    corrected, accepted = data["medicines"]
    assert corrected["strength"] == "250 mg"
    assert corrected["user_corrected"] is True
    assert accepted["user_corrected"] is False
    # A human read the page; nothing is left flagged.
    assert corrected["low_confidence_fields"] == []
    assert corrected["field_confidence"]["normalized_name"] == 1.0


def test_dropped_medicine_is_removed_by_verification(unverified_prescription):
    """Omitting an entry is how the patient throws out something OCR
    invented, so the record must shrink to match."""
    res = client.post(
        f"/api/v1/prescriptions/{unverified_prescription.id}/verify",
        json={"medicines": [{"id": "m_2", "raw_name": "Warfarin 5mg",
                             "normalized_name": "Warfarin"}]},
        headers=AUTH,
    )

    assert res.status_code == 200
    assert len(res.json()["data"]["medicines"]) == 1
    assert store.get_prescription(unverified_prescription.id).verified is True


def test_verify_rejects_an_empty_confirmation(unverified_prescription):
    res = client.post(
        f"/api/v1/prescriptions/{unverified_prescription.id}/verify",
        json={"medicines": []},
        headers=AUTH,
    )

    assert res.status_code == 422
    assert store.get_prescription(unverified_prescription.id).verified is False


def test_verify_rejects_a_prescription_still_processing():
    record = store.PrescriptionRecord(
        id="rx_test_processing", user_id=DEV_USER_ID, status="processing"
    )
    store._prescriptions[record.id] = record
    try:
        res = client.post(
            f"/api/v1/prescriptions/{record.id}/verify",
            json={"medicines": [{"id": "m_1", "raw_name": "Amoxicillin"}]},
            headers=AUTH,
        )
        assert res.status_code == 409
    finally:
        store._prescriptions.pop(record.id, None)


def test_another_users_prescription_is_not_reachable(unverified_prescription):
    unverified_prescription.user_id = "someone-else"

    res = client.post(
        "/api/v1/interactions/check",
        json={"prescription_id": unverified_prescription.id},
        headers=AUTH,
    )

    assert res.status_code == 404


def test_reprocessing_reopens_the_gate(unverified_prescription, tmp_path):
    """A re-read produces different medicines, so an earlier confirmation no
    longer applies to what's in the record."""
    unverified_prescription.verified = True
    # Reprocessing is a no-op without a stored image, so give it one. It
    # isn't a real image; the background re-read fails harmlessly and this
    # asserts on the state change the request itself makes.
    image = tmp_path / "rx.jpg"
    image.write_bytes(b"not-an-image")
    unverified_prescription.image_path = str(image)

    res = client.post(
        f"/api/v1/prescriptions/{unverified_prescription.id}/reprocess",
        headers=AUTH,
    )

    assert res.status_code == 200
    assert res.json()["data"]["prescription"]["verified"] is False


def test_reprocessing_without_a_stored_image_changes_nothing(
    unverified_prescription,
):
    """Nothing to re-read means nothing to invalidate — the record must not
    be knocked out of its current state for no reason."""
    unverified_prescription.verified = True
    unverified_prescription.image_path = None

    store.reprocess(unverified_prescription.id)

    assert unverified_prescription.verified is True
    assert unverified_prescription.status == "analyzed"
