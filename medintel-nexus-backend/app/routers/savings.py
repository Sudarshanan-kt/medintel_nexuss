"""Generic-substitute lookup for scanned medicines.

Moved off the client for the same reason as the assistant: it used to call a
hosted API directly with a bundled key. The client keeps its small curated
brand -> generic table as an offline fallback, so `checked: false` here has
to be distinguishable from "checked, and there's nothing to save".
"""

from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app import llm
from app.envelope import success
from app.security import get_current_user_id

router = APIRouter(prefix="/savings", tags=["savings"])

_SYSTEM_PROMPT = """You are a pharmacology reference assistant. For each \
medicine given (by brand or generic name), identify its generic (INN) name \
and a realistic typical cost-saving percentage range if the patient switched \
from a common branded version to the generic version, in a typical retail \
pharmacy market.

Respond with ONLY a JSON object of this exact shape, no prose:
{"swaps": [
  {"id": "<the id given>", "generic_name": "<INN name>", "savings_low": <int 0-90>, "savings_high": <int 0-90>, "note": "<one short plain-language sentence>"}
]}

If the medicine given is already a generic/INN name with no distinct brand \
premium to speak of, still return an entry with savings_low and savings_high \
both 0, and a short reassuring note that it's already the generic form.
Never invent a specific currency price — percentages only."""


class MedicineIn(BaseModel):
    id: str
    name: str
    strength: str = ""


class GenericsRequest(BaseModel):
    medicines: List[MedicineIn] = []


class SwapOut(BaseModel):
    id: str
    generic_name: str
    savings_low: int
    savings_high: int
    note: str


def _clamp_percent(value: object) -> int:
    try:
        number = int(float(value))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0
    return max(0, min(90, number))


def _to_swap(raw: dict, known_ids: set) -> Optional[SwapOut]:
    """Drops entries that don't map back to a medicine that was asked
    about — a swap for a drug the patient isn't on is worse than a gap."""
    medicine_id = str(raw.get("id") or "")
    if medicine_id not in known_ids:
        return None

    generic = str(raw.get("generic_name") or "").strip()
    if not generic:
        return None

    return SwapOut(
        id=medicine_id,
        generic_name=generic,
        savings_low=_clamp_percent(raw.get("savings_low")),
        savings_high=_clamp_percent(raw.get("savings_high")),
        note=str(raw.get("note") or "").strip()
        or "Ask your pharmacist if a generic version is available.",
    )


@router.post("/generics")
async def find_generics(
    body: GenericsRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    if not body.medicines:
        return success({"checked": True, "swaps": []})

    listing = "\n".join(
        f'- id="{m.id}" name="{m.name}" strength="{m.strength}"'
        for m in body.medicines
    )
    raw = await llm.chat_json(
        _SYSTEM_PROMPT, f"Medicines:\n{listing}", temperature=0.2, max_tokens=800
    )
    if raw is None:
        return success({"checked": False, "swaps": []})

    known_ids = {m.id for m in body.medicines}
    swaps = []
    for entry in raw.get("swaps") or []:
        if not isinstance(entry, dict):
            continue
        swap = _to_swap(entry, known_ids)
        if swap is not None:
            swaps.append(swap)

    # An answer that mapped onto nothing is indistinguishable from no
    # answer, and the client's curated table is better than an empty list.
    if not swaps:
        return success({"checked": False, "swaps": []})

    return success(
        {"checked": True, "swaps": [s.model_dump() for s in swaps]}
    )
