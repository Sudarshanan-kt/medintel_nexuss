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

The cache is on disk (`app/records_db.py`) rather than in memory, because a
restart used to throw away a day's worth of it and send the next search
straight back to Overpass. That is the opposite of what the usage policy
asks, and it is slow exactly when it is most visible: mirrors fail
independently, so on a network that can only route to one of them a cold
lookup takes seconds or doesn't finish at all.

Overpass is still contacted, just at arm's length. Removing it entirely
means self-hosting an OSM extract — a real option, and a much larger one.
"""

import asyncio
import logging
import math
import time
from typing import List, Optional, Tuple

import httpx
from fastapi import APIRouter, Depends, Query

from app import records_db
from app.envelope import success
from app.security import get_current_user_id

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/pharmacies", tags=["pharmacies"])

_ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
)

# Per-mirror budget. Overpass is donated infrastructure and its mirrors fail
# in two ways: a fast 503/504 when overloaded, or no answer at all when the
# caller's network can't route to them (some ISPs reach only one of these).
# A generous per-request timeout means one unroutable mirror consumes the
# whole search, so each gets a short slice instead.
_MIRROR_TIMEOUT_SECONDS = 10.0

# Ceiling for the entire lookup, mirrors and retries included. Must stay
# comfortably under the client's own receive timeout — a backend that is
# still trying after the app has given up helps nobody. See
# `PharmacyService.findNearby`.
_TOTAL_BUDGET_SECONDS = 32.0

# Overloaded mirrors are the normal case, not an exceptional one, so the
# healthy mirror is worth asking twice before declaring the search failed.
_ATTEMPTS_PER_MIRROR = 2

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

def _snap(value: float) -> float:
    return round(round(value / _GRID_DEGREES) * _GRID_DEGREES, 6)


def _cached(key: Tuple[float, float, int]) -> Optional[List[dict]]:
    lat, lon, radius_m = key
    return records_db.get_cached_pharmacies(
        lat, lon, radius_m, max_age_seconds=_CACHE_TTL_SECONDS
    )


def _store(key: Tuple[float, float, int], pharmacies: List[dict]) -> None:
    lat, lon, radius_m = key
    records_db.put_cached_pharmacies(
        lat,
        lon,
        radius_m,
        pharmacies,
        max_age_seconds=_CACHE_TTL_SECONDS,
        max_entries=_MAX_CACHE_ENTRIES,
    )


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


async def _ask_mirror(
    client: httpx.AsyncClient, url: str, query: str, attempt: int
) -> Optional[List[dict]]:
    """One mirror, once. None means it didn't answer usefully."""
    try:
        response = await client.post(
            url,
            # Let httpx form-encode it. The query contains characters that
            # have meaning in a form body.
            data={"data": query},
            headers={"User-Agent": _USER_AGENT},
        )
        response.raise_for_status()
        return _parse(response.json())
    except Exception as exc:
        logger.warning(
            "Overpass mirror failed (attempt %d): %s — %s: %s",
            attempt + 1,
            url,
            # A timeout's str() is empty, which used to make these lines read
            # as though nothing had gone wrong.
            type(exc).__name__,
            exc or "no detail",
        )
        return None


async def _race_mirrors(
    client: httpx.AsyncClient, query: str, attempt: int, budget: float
) -> Optional[List[dict]]:
    """Asks every mirror at once and returns the first usable answer.

    Sequentially, a mirror that hangs costs the full per-mirror timeout
    before the next one is even tried, so one dead mirror delays a healthy
    one that would have answered in a second. Overpass mirrors fail
    independently and unpredictably — which one is up varies by network and
    by minute — so there is no useful order to try them in. Asking all three
    together makes a round cost the *fastest* answer instead of the sum of
    the failures.

    The extra load is three small queries against donated infrastructure,
    once per uncached lookup, which is why the result is cached and the
    coordinates are snapped to a grid before it gets here.
    """
    tasks = {
        asyncio.create_task(_ask_mirror(client, url, query, attempt))
        for url in _ENDPOINTS
    }
    pending = tasks
    try:
        while pending:
            done, pending = await asyncio.wait(
                pending, timeout=budget, return_when=asyncio.FIRST_COMPLETED
            )
            if not done:
                return None
            for task in done:
                result = task.result()
                if result is not None:
                    return result
        return None
    finally:
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)


async def _query_overpass(lat: float, lon: float, radius_m: int) -> Optional[List[dict]]:
    """Returns None when every mirror failed, so the caller can say the
    search didn't run rather than that there are no pharmacies nearby.

    Every mirror is asked at once, and the whole round is repeated if none
    answers. A 504 from Overpass means it was too busy this second, not that
    the data is missing, and a single one used to be enough to fail the whole
    search — the user saw "pharmacy search is unavailable" for something that
    succeeds on the next attempt.
    """
    query = _build_query(lat, lon, radius_m)
    deadline = time.monotonic() + _TOTAL_BUDGET_SECONDS

    async with httpx.AsyncClient(timeout=_MIRROR_TIMEOUT_SECONDS) as client:
        for attempt in range(_ATTEMPTS_PER_MIRROR):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                logger.warning(
                    "Overpass lookup out of time after %ss", _TOTAL_BUDGET_SECONDS
                )
                return None
            found = await _race_mirrors(client, query, attempt, remaining)
            if found is not None:
                return found
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
