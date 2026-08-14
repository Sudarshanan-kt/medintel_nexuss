"""Records have to outlive the process that made them.

A restart used to drop every parsed prescription and, worse, every
verification a patient had typed in by hand. These tests stand in for a
restart by opening the same database file fresh — nothing is cached in
memory, so a new read is exactly what a new process would see.
"""

import pytest

from app import records_db
from app.records_db import PrescriptionRecord, ReportRecord, UploadRecord


@pytest.fixture
def db(tmp_path, monkeypatch):
    """A database of this test's own, restored afterwards."""
    original = records_db.db_path()
    records_db.use(tmp_path / "records.sqlite3")
    yield
    records_db.use(original)


def test_a_verified_prescription_survives_a_restart(db):
    records_db.put_prescription(
        PrescriptionRecord(
            id="rx_1",
            user_id="u1",
            status="analyzed",
            ocr_confidence=0.82,
            medicines=[
                {
                    "id": "m_1",
                    "raw_name": "Warfarin 5mg",
                    "normalized_name": "Warfarin",
                    "field_confidence": {"normalized_name": 1.0},
                    "low_confidence_fields": [],
                    "blocking_fields": [],
                    "user_corrected": True,
                }
            ],
            verified=True,
            verified_at=1_700_000_000.0,
            verified_by_user=True,
        )
    )

    reloaded = records_db.get_prescription("rx_1")

    assert reloaded is not None
    # The confirmation is the part that cannot be regenerated — reproducing
    # it means asking the patient to read their prescription again.
    assert reloaded.verified is True
    assert reloaded.verified_by_user is True
    assert reloaded.verified_at == 1_700_000_000.0
    assert reloaded.ocr_confidence == 0.82
    assert reloaded.medicines[0]["normalized_name"] == "Warfarin"
    assert reloaded.medicines[0]["user_corrected"] is True


def test_report_analysis_survives_a_restart(db):
    records_db.put_report(
        ReportRecord(
            id="rpt_1",
            user_id="u1",
            status="analyzed",
            summary="Cholesterol slightly raised.",
            metrics=[{"label": "LDL", "value": 3.9, "unit": "mmol/L"}],
            findings=[{"severity": "caution", "text": "LDL above range"}],
            advice=[{"label": "LDL", "direction": "Lower", "advice": "Less fried food"}],
        )
    )

    reloaded = records_db.get_report("rpt_1")

    assert reloaded is not None
    assert reloaded.summary == "Cholesterol slightly raised."
    assert reloaded.metrics[0]["value"] == 3.9
    assert reloaded.findings[0]["severity"] == "caution"
    assert reloaded.advice[0]["direction"] == "Lower"


def test_an_upload_keeps_where_its_bytes_landed(db):
    records_db.put_upload(
        UploadRecord(
            id="up_1",
            user_id="u1",
            file_name="rx.jpg",
            mime_type="image/jpeg",
            size_bytes=1234,
            signed_url="http://host/dev-storage/up_1",
            storage_path="/tmp/uploads/up_1.jpg",
        )
    )

    assert records_db.get_upload("up_1").storage_path == "/tmp/uploads/up_1.jpg"


def test_a_missing_record_is_none_not_an_error(db):
    assert records_db.get_prescription("rx_nope") is None
    assert records_db.get_report("rpt_nope") is None
    assert records_db.get_upload("up_nope") is None


def test_put_overwrites_rather_than_duplicating(db):
    record = PrescriptionRecord(id="rx_1", user_id="u1", status="processing")
    records_db.put_prescription(record)
    record.status = "analyzed"
    records_db.put_prescription(record)

    assert records_db.get_prescription("rx_1").status == "analyzed"
    assert len(records_db.list_prescriptions("u1")) == 1


def test_scans_left_mid_processing_are_failed_not_left_hanging(db):
    """The task that was working on these died with the last process, and
    nothing restarts it. A record still claiming "processing" is a client
    polling forever; `failed` is a state it can retry from."""
    records_db.put_prescription(
        PrescriptionRecord(id="rx_stuck", user_id="u1", status="processing")
    )
    records_db.put_prescription(
        PrescriptionRecord(id="rx_queued", user_id="u1", status="queued")
    )
    records_db.put_prescription(
        PrescriptionRecord(id="rx_done", user_id="u1", status="analyzed")
    )
    records_db.put_report(
        ReportRecord(id="rpt_stuck", user_id="u1", status="processing")
    )

    reset = records_db.fail_interrupted_processing()

    assert reset == 3
    assert records_db.get_prescription("rx_stuck").status == "failed"
    assert records_db.get_prescription("rx_queued").status == "failed"
    assert records_db.get_report("rpt_stuck").status == "failed"
    # A finished analysis is not work in progress and must be left alone.
    assert records_db.get_prescription("rx_done").status == "analyzed"


class TestPharmacyCache:
    """The cache is the part that keeps this feature off donated
    infrastructure, so it has to survive the restart that used to empty it."""

    DAY = 24 * 60 * 60
    SHOPS = [{"name": "Apollo Pharmacy", "lat": 12.97, "lon": 77.59, "address": None}]

    def test_a_stored_cell_is_readable_again(self, db):
        records_db.put_cached_pharmacies(
            12.97, 77.595, 3000, self.SHOPS, max_age_seconds=self.DAY, max_entries=512
        )

        hit = records_db.get_cached_pharmacies(
            12.97, 77.595, 3000, max_age_seconds=self.DAY
        )

        assert hit == self.SHOPS

    def test_a_different_cell_is_a_miss(self, db):
        records_db.put_cached_pharmacies(
            12.97, 77.595, 3000, self.SHOPS, max_age_seconds=self.DAY, max_entries=512
        )

        # Different cell, and same cell at a different radius: neither may
        # answer with the other's results.
        assert (
            records_db.get_cached_pharmacies(13.5, 77.595, 3000, max_age_seconds=self.DAY)
            is None
        )
        assert (
            records_db.get_cached_pharmacies(12.97, 77.595, 5000, max_age_seconds=self.DAY)
            is None
        )

    def test_a_stale_entry_is_a_miss(self, db):
        records_db.put_cached_pharmacies(
            12.97, 77.595, 3000, self.SHOPS, max_age_seconds=self.DAY, max_entries=512
        )

        # Nothing waits a day in a test: asking for a max age of zero is the
        # same question the TTL asks tomorrow.
        assert (
            records_db.get_cached_pharmacies(12.97, 77.595, 3000, max_age_seconds=0)
            is None
        )

    def test_the_cache_is_bounded(self, db):
        for i in range(8):
            records_db.put_cached_pharmacies(
                12.0 + i * 0.005,
                77.0,
                3000,
                self.SHOPS,
                max_age_seconds=self.DAY,
                max_entries=5,
            )

        assert records_db.count_cached_pharmacy_cells() == 5
        # Eviction is oldest-first, so the most recent write must be the one
        # that survived.
        assert (
            records_db.get_cached_pharmacies(
                12.0 + 7 * 0.005, 77.0, 3000, max_age_seconds=self.DAY
            )
            is not None
        )

    def test_snapped_coordinates_round_trip_as_keys(self, db):
        """The key is a float produced by `_snap`, and a lookup only hits if
        that float stores and compares exactly."""
        from app.routers.pharmacies import _snap

        lat, lon = _snap(13.08268), _snap(80.27072)
        records_db.put_cached_pharmacies(
            lat, lon, 3400, self.SHOPS, max_age_seconds=self.DAY, max_entries=512
        )

        # A neighbouring doorstep snaps to the same cell and must hit.
        assert (
            records_db.get_cached_pharmacies(
                _snap(13.0829), _snap(80.2708), 3400, max_age_seconds=self.DAY
            )
            == self.SHOPS
        )


def test_records_are_listed_per_user_newest_first(db):
    records_db.put_prescription(
        PrescriptionRecord(id="rx_old", user_id="u1", created_at=100.0)
    )
    records_db.put_prescription(
        PrescriptionRecord(id="rx_new", user_id="u1", created_at=200.0)
    )
    records_db.put_prescription(
        PrescriptionRecord(id="rx_theirs", user_id="u2", created_at=300.0)
    )

    mine = records_db.list_prescriptions("u1")

    assert [r.id for r in mine] == ["rx_new", "rx_old"]
