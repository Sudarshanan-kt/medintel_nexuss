"""Drug-drug interaction checking.

The verdict — whether two drugs interact, and how severely — comes from a
local dataset (`app/interactions_db.py`), never from a language model. A
model cannot cite a source for a clinical claim, and during testing two
scans of the same prescription produced different primary interactions;
that non-determinism is disqualifying for a safety check.

The model's only job here is to explain, in plain language, a pair the
dataset has already confirmed and already graded. It cannot introduce an
interaction, remove one, or change a severity. If it's unavailable the
verdict is unaffected and the explanation falls back to fixed text.

`checked: false` means the check could not run at all. It must never be
confused with "checked and found nothing", which is why the dataset being
absent produces the former rather than an empty result.
"""

import logging
from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app import interactions_db, llm
from app.envelope import ApiError, success
from app.security import get_current_user_id
from app.store import get_prescription

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/interactions", tags=["interactions"])

_CHECKED_DISCLAIMER = (
    "Checked against a drug-interaction database. This is not a substitute "
    "for professional medical advice."
)
_UNAVAILABLE_DISCLAIMER = (
    "Interaction check unavailable right now — please consult a pharmacist "
    "or doctor before combining these medicines."
)

_EXPLAIN_PROMPT = """You explain a drug-drug interaction to a patient in \
plain language.

You will be given two medicines and the severity a clinical database has \
ALREADY established for that pair. Your job is only to explain and advise. \
Do not dispute, re-grade, or second-guess the severity you are given, and \
do not mention any other medicines.

Write:
- mechanism: one or two sentences on why these two interact, in everyday \
words. Name the process if it's clear (e.g. "Drug A blocks the liver enzyme \
that clears Drug B, so Drug B can build up"). If you are not confident about \
the mechanism for this specific pair, say plainly that the database records \
an interaction without giving a reason — do not invent biochemistry.
- recommendation: one short, practical sentence on what the patient should \
do. Always defer dosing decisions to their doctor or pharmacist.

You are not a doctor and must not tell the patient to stop or change a \
medicine on your own authority.

Respond with ONLY a JSON object:
{"mechanism": "<string>", "recommendation": "<string>"}"""

# Used when the model is unavailable or its answer can't be parsed. Says
# less, but nothing that isn't true.
_FALLBACK_RECOMMENDATION = (
    "Ask your doctor or pharmacist before taking these two together."
)


def _fallback_mechanism(interaction: interactions_db.Interaction) -> str:
    return (
        f"A drug-interaction database records a "
        f"{interaction.level.lower()}-severity interaction between "
        f"{interaction.canonical_a} and {interaction.canonical_b}."
    )


class InteractionCheckRequest(BaseModel):
    medicine_names: List[str] = []
    # When set, the check runs against the medicines stored on that
    # prescription rather than the names in this request — see
    # [_names_for_prescription] for why that indirection matters.
    prescription_id: Optional[str] = None


class InteractionEntry(BaseModel):
    medicines: List[str]
    risk: str
    # The database's own grading (Major / Moderate / Minor), kept verbatim
    # so a verdict stays traceable to its source. `risk` is the app's
    # three-level vocabulary that drives the badge.
    level: str
    mechanism: str
    recommendation: str
    # False when the plain-language text is the fixed fallback rather than
    # a generated explanation. The verdict above it is unaffected either way.
    explained: bool = True


class InteractionCheckResponse(BaseModel):
    # False when the check genuinely couldn't run — the client must never
    # treat that the same as "checked and safe". overall_risk is null then.
    checked: bool
    overall_risk: Optional[str]
    interactions: List[InteractionEntry]
    disclaimer: str
    # Medicines the database doesn't know. Nothing was checked for these, so
    # an empty `interactions` list says nothing about them and the client
    # has to surface this.
    unrecognized: List[str] = []
    # Pairs the database lists with no established severity. Not shown as
    # warnings — they are 19% of the table and would bury the real ones —
    # but disclosed so the count is never silently zero.
    ungraded_pair_count: int = 0
    source: Optional[str] = None


def _unavailable() -> InteractionCheckResponse:
    return InteractionCheckResponse(
        checked=False,
        overall_risk=None,
        interactions=[],
        disclaimer=_UNAVAILABLE_DISCLAIMER,
    )


def _names_for_prescription(prescription_id: str, user_id: str) -> List[str]:
    """The confirmed medicine names for a prescription, or a 409 if it hasn't
    been confirmed yet.

    The names come from the stored record rather than from the request body
    on purpose: a client that skipped the review step could otherwise post
    the unverified names directly and get a risk verdict anyway, which would
    make the gate decorative. Reading server-side state is what makes it a
    real block.
    """
    prescription = get_prescription(prescription_id)
    if prescription is None or prescription.user_id != user_id:
        raise ApiError(404, "Prescription not found.")
    if not prescription.verified:
        raise ApiError(
            409,
            "Confirm the medicines read from this prescription before "
            "running a safety check — a misread name would make the result "
            "meaningless.",
        )
    return [
        str(m.get("normalized_name") or m.get("raw_name") or "").strip()
        for m in prescription.medicines
        if (m.get("normalized_name") or m.get("raw_name"))
    ]


async def _explain(interaction: interactions_db.Interaction) -> InteractionEntry:
    """Wraps a dataset verdict in plain-language text.

    The severity is passed to the model as settled fact and copied into the
    response from the dataset, not from whatever the model says back — the
    model cannot influence the grading even if it argues with it.
    """
    # Explained against the dataset's canonical names — those are what the
    # entry is actually about, and a brand name would invite the model to
    # reason about the wrong thing.
    parsed = await llm.chat_json(
        _EXPLAIN_PROMPT,
        f"Medicines: {interaction.canonical_a} and {interaction.canonical_b}. "
        f"Established severity: {interaction.level}.",
        temperature=0.2,
        max_tokens=300,
    )

    mechanism = (parsed or {}).get("mechanism")
    recommendation = (parsed or {}).get("recommendation")
    explained = bool(
        isinstance(mechanism, str) and mechanism.strip()
    )

    return InteractionEntry(
        medicines=interaction.pair,
        risk=interaction.risk,
        level=interaction.level,
        mechanism=mechanism.strip() if explained else _fallback_mechanism(interaction),
        recommendation=(
            recommendation.strip()
            if isinstance(recommendation, str) and recommendation.strip()
            else _FALLBACK_RECOMMENDATION
        ),
        explained=explained,
    )


@router.post("/check")
async def check_interactions(
    body: InteractionCheckRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    if body.prescription_id:
        names = _names_for_prescription(body.prescription_id, user_id)
    else:
        names = [n.strip() for n in body.medicine_names if n.strip()]

    # Fewer than 2 medicines: nothing can interact — skip the lookup.
    if len(names) < 2:
        return success(
            InteractionCheckResponse(
                checked=True,
                overall_risk="none",
                interactions=[],
                disclaimer=_CHECKED_DISCLAIMER,
                source=interactions_db.metadata().get("source"),
            ).model_dump()
        )

    result = interactions_db.check(names)
    if result is None:
        logger.error(
            "Interaction dataset is missing — build it with "
            "`python scripts/import_ddinter.py`."
        )
        return success(_unavailable().model_dump())

    entries = [await _explain(i) for i in result.interactions]

    return success(
        InteractionCheckResponse(
            checked=True,
            overall_risk=result.overall_risk,
            interactions=entries,
            disclaimer=_CHECKED_DISCLAIMER,
            unrecognized=result.unrecognized,
            ungraded_pair_count=len(result.ungraded),
            source=interactions_db.metadata().get("source"),
        ).model_dump()
    )
