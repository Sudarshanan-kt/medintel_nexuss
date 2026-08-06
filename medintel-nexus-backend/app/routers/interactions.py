import json
from typing import List, Optional

import httpx
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.config import settings
from app.envelope import success
from app.security import get_current_user_id

router = APIRouter(prefix="/interactions", tags=["interactions"])

_GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
_GROQ_MODEL = "llama-3.3-70b-versatile"

_VALID_RISK = {"none", "moderate", "severe"}

_CHECKED_DISCLAIMER = (
    "This is an AI-generated safety check, not a substitute for "
    "professional medical advice."
)
_UNAVAILABLE_DISCLAIMER = (
    "Interaction check unavailable right now — please consult a pharmacist "
    "or doctor before combining these medicines."
)

_SYSTEM_PROMPT = """You are a clinical pharmacology assistant embedded in a \
patient-facing app. Given a list of medicine names, identify clinically \
significant drug-drug interactions between them.

For each interacting pair, explain the interaction mechanism in one or two \
plain-language sentences (e.g. "Drug A inhibits the CYP3A4 enzyme that \
normally breaks down Drug B, so Drug B can build up to unsafe levels"), and \
give a short practical recommendation. Rate each interaction's risk as \
exactly one of: none, moderate, severe.

If a name isn't a real/recognizable medicine, ignore it rather than \
guessing. If there are no clinically significant interactions among the \
given medicines, return an empty interactions list and overall_risk "none".

Respond with ONLY a JSON object, no other text, matching exactly this shape:
{
  "overall_risk": "none" | "moderate" | "severe",
  "interactions": [
    {
      "medicines": ["<name>", "<name>"],
      "risk": "none" | "moderate" | "severe",
      "mechanism": "<one or two sentence explanation>",
      "recommendation": "<short practical advice>"
    }
  ]
}
overall_risk must equal the highest risk level among the interactions found \
(or "none" if the list is empty)."""


class InteractionCheckRequest(BaseModel):
    medicine_names: List[str] = []


class InteractionEntry(BaseModel):
    medicines: List[str]
    risk: str
    mechanism: str
    recommendation: str


class InteractionCheckResponse(BaseModel):
    # False when the check genuinely couldn't run (no API key / LLM
    # failure) — the client must never treat that the same as "checked and
    # safe". overall_risk is null in that case, not "none".
    checked: bool
    overall_risk: Optional[str]
    interactions: List[InteractionEntry]
    disclaimer: str


def _unavailable() -> InteractionCheckResponse:
    return InteractionCheckResponse(
        checked=False,
        overall_risk=None,
        interactions=[],
        disclaimer=_UNAVAILABLE_DISCLAIMER,
    )


async def _call_groq(medicine_names: List[str]) -> Optional[dict]:
    if not settings.groq_api_key:
        return None
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            res = await client.post(
                _GROQ_ENDPOINT,
                headers={
                    "Authorization": f"Bearer {settings.groq_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": _GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": _SYSTEM_PROMPT},
                        {
                            "role": "user",
                            "content": "Medicines: " + ", ".join(medicine_names),
                        },
                    ],
                    "temperature": 0.2,
                    "max_tokens": 900,
                    "response_format": {"type": "json_object"},
                },
            )
        res.raise_for_status()
        content = res.json()["choices"][0]["message"]["content"]
        return json.loads(content)
    except Exception:
        return None


@router.post("/check")
async def check_interactions(
    body: InteractionCheckRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    names = [n.strip() for n in body.medicine_names if n.strip()]

    # Fewer than 2 medicines: nothing can interact — skip the LLM call.
    if len(names) < 2:
        return success(
            InteractionCheckResponse(
                checked=True,
                overall_risk="none",
                interactions=[],
                disclaimer=_CHECKED_DISCLAIMER,
            ).model_dump()
        )

    raw = await _call_groq(names)
    if raw is None:
        return success(_unavailable().model_dump())

    try:
        interactions = []
        for item in raw.get("interactions", []):
            risk = item.get("risk", "none")
            if risk not in _VALID_RISK:
                risk = "moderate"
            interactions.append(
                InteractionEntry(
                    medicines=[str(m) for m in item.get("medicines", [])],
                    risk=risk,
                    mechanism=str(item.get("mechanism", "")).strip(),
                    recommendation=str(item.get("recommendation", "")).strip(),
                )
            )

        overall_risk = raw.get("overall_risk")
        if overall_risk not in _VALID_RISK:
            if any(i.risk == "severe" for i in interactions):
                overall_risk = "severe"
            elif any(i.risk == "moderate" for i in interactions):
                overall_risk = "moderate"
            else:
                overall_risk = "none"

        return success(
            InteractionCheckResponse(
                checked=True,
                overall_risk=overall_risk,
                interactions=interactions,
                disclaimer=_CHECKED_DISCLAIMER,
            ).model_dump()
        )
    except Exception:
        return success(_unavailable().model_dump())
