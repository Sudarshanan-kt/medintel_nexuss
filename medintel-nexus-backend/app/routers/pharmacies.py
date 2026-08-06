from fastapi import APIRouter, Depends, Query

from app.envelope import success
from app.security import get_current_user_id

router = APIRouter(prefix="/pharmacies", tags=["pharmacies"])

# The Flutter app currently queries OpenStreetMap's Overpass API directly for
# this feature — nothing calls this route yet. Stubbed so the path exists
# ahead of proxying that lookup server-side.


@router.get("/nearby")
def nearby_pharmacies(
    lat: float = Query(...),
    lon: float = Query(...),
    radius_m: int = Query(3000),
    user_id: str = Depends(get_current_user_id),
) -> dict:
    return success({"center": {"lat": lat, "lon": lon}, "pharmacies": []})
