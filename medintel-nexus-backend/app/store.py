import asyncio
import logging
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

from app import ocr

logger = logging.getLogger(__name__)

# Real (if simple) file-based storage for scaffolding — good enough for a
# single-instance dev/demo backend. Swap for real object storage (S3/GCS/
# Supabase Storage) if this backend ever needs to run as more than one
# instance or survive a restart without losing in-flight uploads.
_UPLOADS_DIR = Path(__file__).resolve().parent.parent / "uploads"
_UPLOADS_DIR.mkdir(exist_ok=True)


@dataclass
class UploadRecord:
    id: str
    user_id: str
    file_name: str
    mime_type: str
    size_bytes: int
    signed_url: str
    storage_path: Optional[str] = None


@dataclass
class PrescriptionRecord:
    id: str
    user_id: str
    status: str = "queued"
    ocr_confidence: Optional[float] = None
    medicines: List[dict] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    image_path: Optional[str] = None
    # Human-in-the-loop gate. A prescription is only "verified" once either
    # the OCR read every field confidently enough to stand on its own, or
    # the patient confirmed/corrected the uncertain ones. Risk analysis
    # refuses to run against an unverified record — acting on a misread drug
    # name is the worst failure this pipeline has.
    verified: bool = False
    verified_at: Optional[float] = None
    # True when the patient (not the OCR) settled the uncertain fields.
    verified_by_user: bool = False

    @property
    def needs_review(self) -> bool:
        return self.status == "analyzed" and not self.verified

    @property
    def review_field_count(self) -> int:
        """How many fields the review UI should highlight."""
        return sum(len(m.get("low_confidence_fields") or []) for m in self.medicines)

    @property
    def blocking_field_count(self) -> int:
        """How many of those are uncertain enough to hold up risk analysis."""
        return sum(len(m.get("blocking_fields") or []) for m in self.medicines)


@dataclass
class ReportRecord:
    id: str
    user_id: str
    status: str = "queued"
    ocr_confidence: Optional[float] = None
    summary: str = ""
    metrics: List[dict] = field(default_factory=list)
    findings: List[dict] = field(default_factory=list)
    advice: List[dict] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    image_path: Optional[str] = None


_uploads: Dict[str, UploadRecord] = {}
_prescriptions: Dict[str, PrescriptionRecord] = {}
_reports: Dict[str, ReportRecord] = {}


def create_upload(
    user_id: str, file_name: str, mime_type: str, size_bytes: int
) -> UploadRecord:
    upload_id = f"up_{uuid.uuid4().hex[:12]}"
    record = UploadRecord(
        id=upload_id,
        user_id=user_id,
        file_name=file_name,
        mime_type=mime_type,
        size_bytes=size_bytes,
        signed_url=f"http://localhost:8000/dev-storage/{upload_id}",
    )
    _uploads[upload_id] = record
    return record


def get_upload(upload_id: str) -> Optional[UploadRecord]:
    return _uploads.get(upload_id)


def save_upload_bytes(upload_id: str, data: bytes) -> None:
    """Called by the /dev-storage PUT handler once the raw image bytes
    arrive, so the OCR stage in [complete_upload] has something to read.
    """
    upload = _uploads.get(upload_id)
    if upload is None:
        return
    suffix = Path(upload.file_name).suffix or ".jpg"
    path = _UPLOADS_DIR / f"{upload_id}{suffix}"
    path.write_bytes(data)
    upload.storage_path = str(path)


async def _process_prescription(prescription_id: str, image_path: str) -> None:
    """Runs OCR + LLM structuring in the background, then updates the
    record in place — mirrors the async-worker shape the Flutter client's
    polling loop already expects (queued -> processing -> analyzed/failed).
    """
    record = _prescriptions.get(prescription_id)
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
    upload = _uploads.get(upload_id)
    record = PrescriptionRecord(
        id=prescription_id,
        user_id=user_id,
        status="processing",
        image_path=upload.storage_path if upload else None,
    )
    _prescriptions[prescription_id] = record

    if upload is None or upload.storage_path is None:
        record.status = "failed"
        return record

    # Fire-and-forget: the client polls GET /prescriptions/{id} for the
    # terminal status rather than waiting on this request.
    asyncio.create_task(_process_prescription(prescription_id, upload.storage_path))
    return record


def get_prescription(prescription_id: str) -> Optional[PrescriptionRecord]:
    return _prescriptions.get(prescription_id)


def reprocess(prescription_id: str) -> Optional[PrescriptionRecord]:
    """Re-runs OCR + structuring on the same stored image — for when a
    result came back wrong and the user wants another attempt rather than
    re-uploading the same photo.
    """
    record = _prescriptions.get(prescription_id)
    if record is None or record.image_path is None:
        return record
    record.status = "processing"
    # A re-read produces new medicines, so any earlier confirmation no
    # longer applies to what's in the record.
    record.verified = False
    record.verified_at = None
    record.verified_by_user = False
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
    """
    record = _prescriptions.get(prescription_id)
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
    return record


# ── Lab/diagnostic reports — same shape as the prescriptions pipeline
# above, structuring into metrics/findings/advice instead of medicines. ──


async def _process_report(report_id: str, image_path: str) -> None:
    record = _reports.get(report_id)
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
    upload = _uploads.get(upload_id)
    record = ReportRecord(
        id=report_id,
        user_id=user_id,
        status="processing",
        image_path=upload.storage_path if upload else None,
    )
    _reports[report_id] = record

    if upload is None or upload.storage_path is None:
        record.status = "failed"
        return record

    asyncio.create_task(_process_report(report_id, upload.storage_path))
    return record


def get_report(report_id: str) -> Optional[ReportRecord]:
    return _reports.get(report_id)


def reprocess_report(report_id: str) -> Optional[ReportRecord]:
    record = _reports.get(report_id)
    if record is None or record.image_path is None:
        return record
    record.status = "processing"
    asyncio.create_task(_process_report(report_id, record.image_path))
    return record
