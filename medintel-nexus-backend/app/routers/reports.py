from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.envelope import ApiError, success
from app.security import get_current_user_id
from app.store import ReportRecord
from app.store import complete_report_upload as _complete_report_upload
from app.store import create_upload
from app.store import get_report as _get_report
from app.store import get_upload
from app.store import reprocess_report as _reprocess_report

router = APIRouter(prefix="/reports", tags=["reports"])

# Report *storage* (the patient's saved library) stays exactly where it is —
# straight from the Flutter app's Supabase client (table `reports`, JSONB
# `payload`). These routes are the *analysis* pipeline only: turn an
# uploaded photo into real structured metrics/findings/advice, the same
# signed-URL upload shape /prescriptions/uploads already uses. The client
# saves the result to Supabase itself once analysis completes.


@router.get("")
def list_reports(user_id: str = Depends(get_current_user_id)) -> dict:
    return success({"reports": []})


def _owned_report(report_id: str, user_id: str) -> ReportRecord:
    report = _get_report(report_id)
    if report is None or report.user_id != user_id:
        raise ApiError(404, "Report not found.")
    return report


class ReportStatusOut(BaseModel):
    id: str
    status: str
    ocr_confidence: Optional[float] = None


class CreateUploadRequest(BaseModel):
    file_name: str
    mime_type: str
    size_bytes: int


@router.post("/uploads")
def create_report_upload(
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
async def complete_report_upload_route(
    upload_id: str,
    body: CompleteUploadRequest,
    user_id: str = Depends(get_current_user_id),
) -> dict:
    upload = get_upload(upload_id)
    if upload is None or upload.user_id != user_id:
        raise ApiError(404, "Upload not found.")
    report = _complete_report_upload(upload_id, user_id)
    return success({"report": ReportStatusOut(**report.__dict__).model_dump()})


@router.get("/{report_id}")
def get_report_status(
    report_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    report = _owned_report(report_id, user_id)
    return success({"report": ReportStatusOut(**report.__dict__).model_dump()})


class MetricOut(BaseModel):
    label: str
    value: Optional[float] = None
    unit: Optional[str] = None
    ref_low: Optional[float] = None
    ref_high: Optional[float] = None


class FindingOut(BaseModel):
    severity: str
    text: str
    explanation: Optional[str] = None


class AdviceOut(BaseModel):
    label: str
    direction: str
    advice: str


@router.get("/{report_id}/analysis")
def get_report_analysis(
    report_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    report = _owned_report(report_id, user_id)
    return success(
        {
            "summary": report.summary,
            "metrics": [MetricOut(**m).model_dump() for m in report.metrics],
            "findings": [FindingOut(**f).model_dump() for f in report.findings],
            "advice": [AdviceOut(**a).model_dump() for a in report.advice],
        }
    )


@router.post("/{report_id}/reprocess")
async def reprocess_report_route(
    report_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    _owned_report(report_id, user_id)
    report = _reprocess_report(report_id)
    return success({"report": ReportStatusOut(**report.__dict__).model_dump()})
