from fastapi import APIRouter, Depends

from app.envelope import success
from app.security import get_current_user_id

router = APIRouter(prefix="/patients", tags=["patients"])


@router.get("/me")
def get_current_patient(user_id: str = Depends(get_current_user_id)) -> dict:
    return success(
        {
            "id": user_id,
            "role": "patient",
            "onboarding_complete": True,
            "full_name": None,
            "phone": None,
            "email": None,
            "avatar_url": None,
        }
    )
