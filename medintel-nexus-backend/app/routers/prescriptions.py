from typing import Dict, Optional

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
        {"prescription": PrescriptionSummary(**prescription.__dict__).model_dump()}
    )


class MedicineOut(BaseModel):
    id: str
    raw_name: str
    normalized_name: Optional[str] = None
    strength: Optional[str] = None
    frequency: Optional[str] = None
    duration_days: Optional[int] = None
    instructions: Optional[str] = None
    field_confidence: Dict[str, float] = Field(default_factory=dict)


@router.get("/{prescription_id}/medicines")
def get_prescription_medicines(
    prescription_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    prescription = _owned_prescription(prescription_id, user_id)
    medicines = [MedicineOut(**m).model_dump() for m in prescription.medicines]
    return success({"medicines": medicines})


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
        {"prescription": PrescriptionSummary(**prescription.__dict__).model_dump()}
    )


@router.get("/{prescription_id}")
def get_prescription_status(
    prescription_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    prescription = _owned_prescription(prescription_id, user_id)
    return success(
        {"prescription": PrescriptionSummary(**prescription.__dict__).model_dump()}
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
