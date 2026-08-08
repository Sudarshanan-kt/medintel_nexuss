"""Nearby-pharmacy search, proxied so the patient's device never talks to
OpenStreetMap directly.

Two things this buys beyond moving the call:

**The exact location never leaves.** The query centre is snapped to a coarse
grid before it goes to Overpass, so what a third party sees is a ~600 m cell
rather than where someone is standing. The search radius is widened by the
cell's reach so nothing genuinely nearby is lost, and the client still
measures distances from its own precise position — the results are as
accurate as before.

**Repeat searches stop hitting Overpass at all.** Grid snapping makes the
cache key coarse on purpose: everyone in a neighbourhood shares one entry.
Pharmacies do not move, and Overpass is donated infrastructure whose usage
policy asks callers to cache rather than re-query.

Overpass is still contacted, just at arm's length. Removing it entirely
means self-hosting an OSM extract — a real option, and a much larger one.
"""

import logging
import math
import time
from typing import Dict, List, Optional, Tuple

import httpx
from fastapi import APIRouter, Depends, Query

from app.envelope import success
from app.security import get_current_user_id

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/pharmacies", tags=["pharmacies"])

_ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)

# ~0.005 degrees of latitude is roughly 550 m, so a snapped centre is at
# most ~390 m from the real one. Against a multi-kilometre search radius
# that is noise; against an attempt to locate someone it is the difference
# between a doorstep and a neighbourhood.
_GRID_DEGREES = 0.005

# Worst-case distance from a real position to its snapped centre, added to
# the radius so snapping can never hide a pharmacy that was in range.
_GRID_SLACK_METRES = 400

# Pharmacies open and close on a timescale of months.
_CACHE_TTL_SECONDS = 24 * 60 * 60
_MAX_CACHE_ENTRIES = 512

# Overpass asks that clients identify themselves.
_USER_AGENT = "MedIntelNexus/1.0 (patient pharmacy finder)"

_cache: Dict[Tuple[float, float, int], Tuple[float, List[dict]]] = {}


def _snap(value: float) -> float:
    return round(round(value / _GRID_DEGREES) * _GRID_DEGREES, 6)


def _cached(key: Tuple[float, float, int]) -> Optional[List[dict]]:
    entry = _cache.get(key)
    if entry is None:
        return None
    stored_at, pharmacies = entry
    if time.time() - stored_at > _CACHE_TTL_SECONDS:
        _cache.pop(key, None)
        return None
    return pharmacies


def _store(key: Tuple[float, float, int], pharmacies: List[dict]) -> None:
    if len(_cache) >= _MAX_CACHE_ENTRIES:
        # Drop the oldest entry. A plain dict is enough at this size and
        # keeps the module dependency-free.
        oldest = min(_cache, key=lambda k: _cache[k][0])
        _cache.pop(oldest, None)
    _cache[key] = (time.time(), pharmacies)


def _build_query(lat: float, lon: float, radius_m: int) -> str:
    return f"""[out:json][timeout:25];
(
  node["amenity"="pharmacy"](around:{radius_m},{lat},{lon});
  way["amenity"="pharmacy"](around:{radius_m},{lat},{lon});
  node["healthcare"="pharmacy"](around:{radius_m},{lat},{lon});
);
out center 60;"""


def _address_of(tags: dict) -> Optional[str]:
    parts = [
        tags.get("addr:housenumber"),
        tags.get("addr:street"),
        tags.get("addr:suburb") or tags.get("addr:neighbourhood"),
        tags.get("addr:city"),
    ]
    joined = ", ".join(p.strip() for p in parts if isinstance(p, str) and p.strip())
    return joined or None


def _parse(payload: dict) -> List[dict]:
    pharmacies = []
    for element in payload.get("elements") or []:
        if not isinstance(element, dict):
            continue
        lat = element.get("lat")
        lon = element.get("lon")
        if lat is None or lon is None:
            centre = element.get("center") or {}
            lat, lon = centre.get("lat"), centre.get("lon")
        if lat is None or lon is None:
            continue

        tags = element.get("tags") or {}
        name = (tags.get("name") or "").strip()
        # Unnamed nodes are useless to a patient trying to find a shop.
        if not name:
            continue

        pharmacies.append(
            {
                "name": name,
                "lat": float(lat),
                "lon": float(lon),
                "address": _address_of(tags),
            }
        )
    return pharmacies


async def _query_overpass(lat: float, lon: float, radius_m: int) -> Optional[List[dict]]:
    """Returns None when every mirror failed, so the caller can say the
    search didn't run rather than that there are no pharmacies nearby."""
    query = _build_query(lat, lon, radius_m)
    async with httpx.AsyncClient(timeout=30) as client:
        for url in _ENDPOINTS:
            try:
                response = await client.post(
                    url,
                    content=f"data={query}",
                    headers={
                        "Content-Type": "application/x-www-form-urlencoded",
                        "User-Agent": _USER_AGENT,
                    },
                )
                response.raise_for_status()
                return _parse(response.json())
            except Exception:
                logger.warning("Overpass mirror failed: %s", url, exc_info=True)
    return None


def _haversine_metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6_371_000.0
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    h = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lon / 2) ** 2
    )
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))


@router.get("/nearby")
async def nearby_pharmacies(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    radius_m: int = Query(3000, ge=100, le=20000),
    user_id: str = Depends(get_current_user_id),
) -> dict:
    snapped_lat, snapped_lon = _snap(lat), _snap(lon)
    key = (snapped_lat, snapped_lon, radius_m)

    pharmacies = _cached(key)
    cached = pharmacies is not None

    if not cached:
        pharmacies = await _query_overpass(
            snapped_lat, snapped_lon, radius_m + _GRID_SLACK_METRES
        )
        if pharmacies is None:
            # Distinguishable from "searched, found none" — the client shows
            # an error rather than an empty list.
            return success(
                {
                    "searched": False,
                    "pharmacies": [],
                    "cached": False,
                }
            )
        _store(key, pharmacies)

    # Distance is measured from the caller's real position, which stays on
    # this server. Only the snapped centre was ever sent onward.
    results = sorted(
        (
            {**p, "distance_m": round(_haversine_metres(lat, lon, p["lat"], p["lon"]))}
            for p in pharmacies
        ),
        key=lambda p: p["distance_m"],
    )
    # Snapping widened the search, so trim back to what was actually asked for.
    results = [p for p in results if p["distance_m"] <= radius_m]

    return success(
        {
            "searched": True,
            "cached": cached,
            "pharmacies": results,
        }
    )
