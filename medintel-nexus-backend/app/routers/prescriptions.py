from typing import Dict, List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.envelope import ApiError, success
from app.security import get_current_user_id
from app.store import (
    PrescriptionRecord,
    complete_upload,
    create_upload,
    get_prescription,
    get_upload,
    reprocess,
    verify_prescription,
)

router = APIRouter(prefix="/prescriptions", tags=["prescriptions"])


def _owned_prescription(prescription_id: str, user_id: str) -> PrescriptionRecord:
    prescription = get_prescription(prescription_id)
    if prescription is None or prescription.user_id != user_id:
        raise ApiError(404, "Prescription not found.")
    return prescription


class PrescriptionSummary(BaseModel):
    id: str
    status: str
    ocr_confidence: Optional[float] = None
    # The human-in-the-loop gate: `needs_review` tells the client to ask the
    # patient to confirm the uncertain fields, and nothing downstream (risk
    # analysis especially) may act on the medicines until `verified`.
    needs_review: bool = False
    verified: bool = False
    review_field_count: int = 0
    blocking_field_count: int = 0

    @classmethod
    def of(cls, record: PrescriptionRecord) -> "PrescriptionSummary":
        return cls(
            id=record.id,
            status=record.status,
            ocr_confidence=record.ocr_confidence,
            needs_review=record.needs_review,
            verified=record.verified,
            review_field_count=record.review_field_count,
            blocking_field_count=record.blocking_field_count,
        )


# --- Async signed-URL upload pipeline (the flow the app actually drives) ---


class CreateUploadRequest(BaseModel):
    file_name: str
    mime_type: str
    size_bytes: int


@router.post("/uploads")
def create_prescription_upload(
    body: CreateUploadRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    upload = create_upload(user_id, body.file_name, body.mime_type, body.size_bytes)
    return success(
        {
            "upload_id": upload.id,
            "signed_url": upload.signed_url,
            "content_type": upload.mime_type,
        }
    )


class CompleteUploadRequest(BaseModel):
    source: str = "camera"
    captured_at: Optional[str] = None
    note: Optional[str] = None


@router.post("/uploads/{upload_id}/complete")
async def complete_prescription_upload(
    upload_id: str,
    body: CompleteUploadRequest,
    user_id: str = Depends(get_current_user_id),
) -> dict:
    upload = get_upload(upload_id)
    if upload is None or upload.user_id != user_id:
        raise ApiError(404, "Upload not found.")
    prescription = complete_upload(upload_id, user_id)
    return success(
        {"prescription": PrescriptionSummary.of(prescription).model_dump()}
    )


class MedicineOut(BaseModel):
    id: str
    raw_name: str
    normalized_name: Optional[str] = None
    strength: Optional[str] = None
    frequency: Optional[str] = None
    duration_days: Optional[int] = None
    instructions: Optional[str] = None
    # Per-field 0–1 score for how well this value is supported by what
    # Tesseract actually read off the page, and the subset of those the
    # patient should be asked to confirm before anything acts on them.
    field_confidence: Dict[str, float] = Field(default_factory=dict)
    low_confidence_fields: List[str] = Field(default_factory=list)
    # The subset of the above that holds up risk analysis — an uncertain
    # name or strength, as opposed to a rephrased dosage instruction.
    blocking_fields: List[str] = Field(default_factory=list)
    user_corrected: bool = False


@router.get("/{prescription_id}/medicines")
def get_prescription_medicines(
    prescription_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    prescription = _owned_prescription(prescription_id, user_id)
    medicines = [MedicineOut(**m).model_dump() for m in prescription.medicines]
    return success({"medicines": medicines})


class VerifyMedicineIn(BaseModel):
    """One medicine as the patient confirmed it. `id` ties the entry back to
    what OCR produced so corrections can be told apart from acceptances;
    entries the patient added themselves may omit it."""

    id: Optional[str] = None
    raw_name: str
    normalized_name: Optional[str] = None
    strength: Optional[str] = None
    frequency: Optional[str] = None
    duration_days: Optional[int] = None
    instructions: Optional[str] = None


class VerifyRequest(BaseModel):
    medicines: List[VerifyMedicineIn]


@router.post("/{prescription_id}/verify")
def verify(
    prescription_id: str,
    body: VerifyRequest,
    user_id: str = Depends(get_current_user_id),
) -> dict:
    """Records the patient's confirmation of the extracted medicines, which
    is what unlocks risk analysis for this prescription.

    The full confirmed list is sent, not a diff — entries dropped from it
    are dropped from the record, which is how the patient removes something
    OCR hallucinated.
    """
    prescription = _owned_prescription(prescription_id, user_id)
    if prescription.status != "analyzed":
        raise ApiError(
            409,
            "This prescription hasn't finished processing yet — "
            "there's nothing to confirm.",
        )
    if not body.medicines:
        raise ApiError(
            422,
            "Confirm at least one medicine, or delete the scan instead.",
        )

    updated = verify_prescription(
        prescription_id, [m.model_dump() for m in body.medicines]
    )
    return success(
        {
            "prescription": PrescriptionSummary.of(updated).model_dump(),
            "medicines": [MedicineOut(**m).model_dump() for m in updated.medicines],
        }
    )


@router.get("/{prescription_id}/ocr")
def get_prescription_ocr(
    prescription_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    prescription = _owned_prescription(prescription_id, user_id)
    return success({"prescription_id": prescription.id, "status": prescription.status})


@router.post("/{prescription_id}/reprocess")
async def reprocess_prescription(
    prescription_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    _owned_prescription(prescription_id, user_id)
    prescription = reprocess(prescription_id)
    return success(
        {"prescription": PrescriptionSummary.of(prescription).model_dump()}
    )


@router.get("/{prescription_id}")
def get_prescription_status(
    prescription_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    prescription = _owned_prescription(prescription_id, user_id)
    return success(
        {"prescription": PrescriptionSummary.of(prescription).model_dump()}
    )


# --- Routes declared in the client's endpoint registry but not yet used by
# any screen. Stubbed out so the route exists; replace once the direct-create
# flow (as opposed to the uploads pipeline above) is actually designed. ---


@router.post("")
def create_prescription(user_id: str = Depends(get_current_user_id)) -> dict:
    raise ApiError(
        501, "Direct prescription creation isn't implemented — use /prescriptions/uploads."
    )


@router.post("/upload-url")
def prescription_upload_url(user_id: str = Depends(get_current_user_id)) -> dict:
    raise ApiError(501, "Superseded by /prescriptions/uploads — use that endpoint instead.")
