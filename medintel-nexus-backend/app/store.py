"""The prescription and lab-report analysis pipelines.

Orchestration only — OCR, structuring, and the review gate. Where the
resulting records are kept is `app/records_db.py`'s problem; this module
loads a record, works on it, and hands it back to be saved.

That handing-back is the one thing to keep in mind when editing here. These
records used to be dicts in this module, so mutating a dataclass was the
save. It no longer is: a mutation that never reaches `put_prescription` /
`put_report` is lost at the end of the request. The background workers below
save in a `finally` for exactly that reason, so every path out of them —
success, early return, exception — writes the state it decided on.
"""

import asyncio
import logging
import time
import uuid
from pathlib import Path
from typing import List, Optional

from app import ocr
from app.records_db import (
    PrescriptionRecord,
    ReportRecord,
    UploadRecord,
    delete_prescription,
    get_prescription,
    get_report,
    get_upload,
    put_prescription,
    put_report,
    put_upload,
)

logger = logging.getLogger(__name__)

# Re-exported so the routers and tests keep importing records from `store`,
# which is the seam they have always used.
__all__ = [
    "PrescriptionRecord",
    "ReportRecord",
    "UploadRecord",
    "complete_report_upload",
    "complete_upload",
    "create_upload",
    "delete_prescription",
    "get_prescription",
    "get_report",
    "get_upload",
    "put_prescription",
    "put_report",
    "reprocess",
    "reprocess_report",
    "save_upload_bytes",
    "verify_prescription",
]

# Raw uploaded bytes stay on the filesystem rather than in the database —
# they are the one part of a record that is large, immutable, and never
# queried. Swap for real object storage (S3/GCS/Supabase Storage) if this
# backend ever runs as more than one instance.
_UPLOADS_DIR = Path(__file__).resolve().parent.parent / "uploads"
_UPLOADS_DIR.mkdir(exist_ok=True)


def create_upload(
    user_id: str,
    file_name: str,
    mime_type: str,
    size_bytes: int,
    base_url: str = "http://localhost:8000",
) -> UploadRecord:
    """Issues an upload ticket.

    [base_url] must be the address the *client* can reach this server on,
    not the address the server knows itself by. Hardcoding localhost here
    worked from a simulator on the same machine and silently broke every
    upload from a real phone, where "localhost" is the phone itself — the
    client PUTs the bytes to this URL, so it has to be routable from there.
    Callers pass the incoming request's own base URL, which is by definition
    an address the client just reached.
    """
    upload_id = f"up_{uuid.uuid4().hex[:12]}"
    return put_upload(
        UploadRecord(
            id=upload_id,
            user_id=user_id,
            file_name=file_name,
            mime_type=mime_type,
            size_bytes=size_bytes,
            signed_url=f"{base_url.rstrip('/')}/dev-storage/{upload_id}",
        )
    )


def save_upload_bytes(upload_id: str, data: bytes) -> None:
    """Called by the /dev-storage PUT handler once the raw image bytes
    arrive, so the OCR stage in [complete_upload] has something to read.
    """
    upload = get_upload(upload_id)
    if upload is None:
        return
    suffix = Path(upload.file_name).suffix or ".jpg"
    path = _UPLOADS_DIR / f"{upload_id}{suffix}"
    path.write_bytes(data)
    upload.storage_path = str(path)
    put_upload(upload)


async def _process_prescription(prescription_id: str, image_path: str) -> None:
    """Runs OCR + LLM structuring in the background, then updates the
    record — mirrors the async-worker shape the Flutter client's polling
    loop already expects (queued -> processing -> analyzed/failed).
    """
    record = get_prescription(prescription_id)
    if record is None:
        return
    try:
        ocr_result = await asyncio.to_thread(ocr.extract, image_path)
        medicines = await ocr.structure_medicines(ocr_result.text)

        if medicines is None:
            # LLM structuring unavailable (no key / request failed) — fail
            # loudly rather than silently falling back to fake data.
            record.status = "failed"
            return
        if not medicines:
            record.status = "failed"
            return

        record.medicines = [
            _to_medicine_out(m, i, ocr_result.words)
            for i, m in enumerate(medicines)
        ]
        record.ocr_confidence = ocr.aggregate_confidence(
            [m["field_confidence"] for m in record.medicines]
        )
        record.status = "analyzed"

        # Auto-verify only when no drug name or strength is in doubt.
        # Anything less certain than that leaves the record unverified until
        # the patient confirms it through POST /prescriptions/{id}/verify.
        if record.blocking_field_count == 0:
            record.verified = True
            record.verified_at = time.time()
            record.verified_by_user = False
    except Exception:
        logger.exception("Prescription processing failed for %s", prescription_id)
        record.status = "failed"
    finally:
        # Every branch above decided a status, including the early returns.
        # This is what makes that decision outlive the task.
        put_prescription(record)


def _to_medicine_out(raw: dict, index: int, words) -> dict:
    raw_name = str(raw.get("raw_name") or "").strip()
    medicine = {
        "id": f"m_{index + 1}",
        "raw_name": raw_name or "Unknown medicine",
        "normalized_name": raw.get("normalized_name"),
        "strength": raw.get("strength"),
        "frequency": raw.get("frequency"),
        "duration_days": raw.get("duration_days"),
        "instructions": raw.get("instructions"),
    }
    scored = ocr.medicine_field_confidence(medicine, words)
    medicine["field_confidence"] = scored
    medicine["low_confidence_fields"] = ocr.low_confidence_fields(scored)
    medicine["blocking_fields"] = ocr.blocking_fields(scored)
    # Whether this specific entry was typed by the patient rather than read
    # off the page — a corrected field is trusted absolutely.
    medicine["user_corrected"] = False
    return medicine


def complete_upload(upload_id: str, user_id: str) -> PrescriptionRecord:
    prescription_id = f"rx_{uuid.uuid4().hex[:12]}"
    upload = get_upload(upload_id)
    record = PrescriptionRecord(
        id=prescription_id,
        user_id=user_id,
        status="processing",
        image_path=upload.storage_path if upload else None,
    )

    if upload is None or upload.storage_path is None:
        record.status = "failed"
        return put_prescription(record)

    # Saved before the task starts, not after: the task looks the record up
    # by id, and a client polling this id must find it either way.
    put_prescription(record)

    # Fire-and-forget: the client polls GET /prescriptions/{id} for the
    # terminal status rather than waiting on this request.
    asyncio.create_task(_process_prescription(prescription_id, upload.storage_path))
    return record


def reprocess(prescription_id: str) -> Optional[PrescriptionRecord]:
    """Re-runs OCR + structuring on the same stored image — for when a
    result came back wrong and the user wants another attempt rather than
    re-uploading the same photo.
    """
    record = get_prescription(prescription_id)
    if record is None or record.image_path is None:
        return record
    record.status = "processing"
    # A re-read produces new medicines, so any earlier confirmation no
    # longer applies to what's in the record.
    record.verified = False
    record.verified_at = None
    record.verified_by_user = False
    put_prescription(record)
    asyncio.create_task(_process_prescription(prescription_id, record.image_path))
    return record


_VERIFIABLE_FIELDS = (
    "raw_name",
    "normalized_name",
    "strength",
    "frequency",
    "duration_days",
    "instructions",
)


def verify_prescription(
    prescription_id: str, medicines: List[dict]
) -> Optional[PrescriptionRecord]:
    """Records the patient's confirmation of what the prescription says.

    [medicines] is the full confirmed list as the patient left it — entries
    they edited, entries they accepted untouched, entries they added, and
    (by omission) entries they deleted. Every field on it is treated as
    ground truth from here on: a human read the page, which beats any OCR
    score, so confidences go to 1.0 and the review list empties.

    This is the record it matters most to persist. It is the one thing here
    a person did by hand, reading their own prescription line by line, and
    the only way to reproduce it after a restart is to ask them to do it
    again.
    """
    record = get_prescription(prescription_id)
    if record is None:
        return None

    previous = {m["id"]: m for m in record.medicines}
    confirmed: List[dict] = []
    for index, incoming in enumerate(medicines):
        medicine_id = str(incoming.get("id") or f"m_{index + 1}")
        original = previous.get(medicine_id, {})
        entry = {
            "id": medicine_id,
            "raw_name": str(incoming.get("raw_name") or "").strip()
            or "Unknown medicine",
        }
        for name in _VERIFIABLE_FIELDS[1:]:
            entry[name] = incoming.get(name)
        entry["field_confidence"] = {
            name: 1.0
            for name in _VERIFIABLE_FIELDS
            if entry.get(name) is not None and str(entry.get(name)).strip() != ""
        }
        entry["low_confidence_fields"] = []
        entry["blocking_fields"] = []
        entry["user_corrected"] = any(
            original.get(name) != entry.get(name) for name in _VERIFIABLE_FIELDS
        )
        confirmed.append(entry)

    record.medicines = confirmed
    record.ocr_confidence = ocr.aggregate_confidence(
        [m["field_confidence"] for m in confirmed]
    )
    record.verified = True
    record.verified_at = time.time()
    record.verified_by_user = True
    return put_prescription(record)


# ── Lab/diagnostic reports — same shape as the prescriptions pipeline
# above, structuring into metrics/findings/advice instead of medicines. ──


async def _process_report(report_id: str, image_path: str) -> None:
    record = get_report(report_id)
    if record is None:
        return
    try:
        raw_text = await asyncio.to_thread(ocr.extract_text, image_path)
        analysis = await ocr.structure_report(raw_text)

        if analysis is None:
            # LLM structuring unavailable — fail loudly rather than
            # silently falling back to fake data.
            record.status = "failed"
            return

        metrics = analysis.get("metrics") or []
        record.summary = str(analysis.get("summary") or "")
        record.metrics = [_to_metric_out(m) for m in metrics]
        record.findings = [_to_finding_out(f) for f in (analysis.get("findings") or [])]
        record.advice = [_to_advice_out(a) for a in (analysis.get("advice") or [])]
        record.ocr_confidence = ocr.estimate_report_confidence(raw_text, metrics)
        record.status = "analyzed"
    except Exception:
        logger.exception("Report processing failed for %s", report_id)
        record.status = "failed"
    finally:
        put_report(record)


def _to_metric_out(raw: dict) -> dict:
    return {
        "label": str(raw.get("label") or "").strip(),
        "value": raw.get("value"),
        "unit": raw.get("unit"),
        "ref_low": raw.get("ref_low"),
        "ref_high": raw.get("ref_high"),
    }


def _to_finding_out(raw: dict) -> dict:
    severity = raw.get("severity")
    if severity not in {"info", "caution", "severe"}:
        severity = "info"
    return {
        "severity": severity,
        "text": str(raw.get("text") or "").strip(),
        "explanation": raw.get("explanation"),
    }


def _to_advice_out(raw: dict) -> dict:
    direction = raw.get("direction")
    if direction not in {"Lower", "Raise"}:
        direction = "Lower"
    return {
        "label": str(raw.get("label") or "").strip(),
        "direction": direction,
        "advice": str(raw.get("advice") or "").strip(),
    }


def complete_report_upload(upload_id: str, user_id: str) -> ReportRecord:
    report_id = f"rpt_{uuid.uuid4().hex[:12]}"
    upload = get_upload(upload_id)
    record = ReportRecord(
        id=report_id,
        user_id=user_id,
        status="processing",
        image_path=upload.storage_path if upload else None,
    )

    if upload is None or upload.storage_path is None:
        record.status = "failed"
        return put_report(record)

    put_report(record)
    asyncio.create_task(_process_report(report_id, upload.storage_path))
    return record


def reprocess_report(report_id: str) -> Optional[ReportRecord]:
    record = get_report(report_id)
    if record is None or record.image_path is None:
        return record
    record.status = "processing"
    put_report(record)
    asyncio.create_task(_process_report(report_id, record.image_path))
    return record
