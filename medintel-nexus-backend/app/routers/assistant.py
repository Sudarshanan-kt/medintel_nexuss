"""Assistant, narration and symptom-triage, all served by the local model.

These prompts used to live in the Flutter client, which called a hosted API
directly with a key shipped inside the app bundle. Moving them here removes
that key from the client entirely and means conversations about a patient's
health never leave this machine.

Every route degrades the same way: when the model can't be reached, the
response says so explicitly (`generated: false`, `rephrased: false`, a null
step) rather than inventing content. The client keeps curated fallback copy
for exactly that case — it has to be able to tell the difference.
"""

import uuid
from typing import List

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app import llm
from app.envelope import success
from app.security import get_current_user_id

router = APIRouter(prefix="/assistant", tags=["assistant"])


# ── Language ────────────────────────────────────────────────────────────

_LANGUAGE_INSTRUCTIONS = {
    "en": "Respond in natural, conversational English.",
    "ta": (
        "Respond in spoken Tamil (தமிழ்) — the warm, everyday register "
        "people actually use, not literary Tamil. Mix in occasional English "
        "words only where natural (medicine names, units)."
    ),
    "hi": (
        "Respond in spoken Hindi (हिन्दी) — the warm, everyday register, "
        "not formal Hindi."
    ),
}


def _with_language(base: str, language: str) -> str:
    instruction = _LANGUAGE_INSTRUCTIONS.get(
        language, _LANGUAGE_INSTRUCTIONS["en"]
    )
    return f"{base}\n{instruction}"


# ── Chat ────────────────────────────────────────────────────────────────

_CHAT_SYSTEM_PROMPT = """You are MedIntel Nexus's clinical assistant — calm, \
warm, conversational and human. You talk to the patient like a thoughtful \
friend who happens to know medicine. Avoid robotic language. Vary your \
sentence structure. You may use contractions.

You help with: medicines, prescriptions, lab reports, risk flags, dosage \
schedules, adherence, side effects, drug interactions, and general health \
questions. Keep replies short by default (2-4 sentences) but go deeper if \
the user asks. Never invent specific lab values, dosages, or prescriptions \
you weren't told about; if you don't have the data, say so honestly.

You are not a doctor. For diagnosis, dosing changes, severe symptoms, or \
emergencies, point the user to their clinician. If the user describes chest \
pain, suicidal thoughts, severe bleeding, stroke symptoms, anaphylaxis or \
similar emergencies, urge them to call emergency services immediately."""


class ChatHistoryItem(BaseModel):
    role: str
    content: str


class SendMessageRequest(BaseModel):
    prompt: str
    history: List[ChatHistoryItem] = []
    language: str = "en"


@router.post("/messages")
async def send_message(
    body: SendMessageRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    messages = [
        {
            "role": "system",
            "content": _with_language(_CHAT_SYSTEM_PROMPT, body.language),
        }
    ]
    # Only the recent turns: a local model's context window is smaller than
    # a hosted one's, and the tail is what the next reply depends on.
    for item in body.history[-10:]:
        role = "user" if item.role == "user" else "assistant"
        messages.append({"role": role, "content": item.content})
    messages.append({"role": "user", "content": body.prompt})

    content = await llm.chat(messages, temperature=0.7, max_tokens=350)
    generated = content is not None and content.strip() != ""

    return success(
        {
            "id": f"msg_{uuid.uuid4().hex[:12]}",
            "role": "assistant",
            "content": content.strip() if generated else "",
            "language": body.language,
            "is_streaming": False,
            # False tells the client to show its own fallback copy rather
            # than an empty bubble.
            "generated": generated,
        }
    )


@router.get("/stream/{message_id}")
def stream_message(
    message_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    """Placeholder for token streaming. The client renders whole replies
    today, so nothing calls this; it stays declared so the route exists."""
    return success({"id": message_id, "content": "", "done": True})


# ── Narration ───────────────────────────────────────────────────────────

_NARRATOR_SYSTEM_PROMPT = """You rephrase a single already-verified factual \
health statement into 1-2 warm, natural, conversational sentences for a \
patient to read. You do NOT add any new fact, number, medicine name, or \
claim that isn't already in the input. You do NOT diagnose or give new \
advice beyond what's stated. Every number, medicine name, and measurement \
in the input must appear unchanged in your output. If you cannot rephrase \
it faithfully, repeat it verbatim. Reply with only the rephrased sentence — \
no preamble, no quotes."""


class NarrateRequest(BaseModel):
    statement: str
    language: str = "en"


@router.post("/narrate")
async def narrate(
    body: NarrateRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    """Restates an already-computed correlation insight more warmly.

    Deliberately narrow: this must never be asked to *decide* anything or
    add information, because a hallucinated addition to a health correlation
    is a safety risk rather than a style choice. The input is always a
    complete, correct answer on its own — this only makes it read better, so
    any failure returns it untouched.
    """
    content = await llm.chat(
        [
            {
                "role": "system",
                "content": _with_language(
                    _NARRATOR_SYSTEM_PROMPT, body.language
                ),
            },
            {"role": "user", "content": body.statement},
        ],
        temperature=0.3,
        max_tokens=120,
    )
    rephrased = content is not None and content.strip() != ""

    return success(
        {
            "text": content.strip() if rephrased else body.statement,
            "rephrased": rephrased,
        }
    )


# ── Symptom triage ──────────────────────────────────────────────────────

_TRIAGE_SYSTEM_PROMPT = """You run a short, adaptive symptom-triage \
questionnaire for a patient. You are NOT a doctor and must NEVER name a \
specific diagnosis or condition — only assess urgency and point to the right \
next step. Reply with ONLY one strict JSON object, nothing else — no \
markdown, no backticks, no text outside the JSON.

Shape 1 — to ask a follow-up question (use short, plain language):
{"type":"question","question":"<one short question>","options":["<opt1>","<opt2>","<opt3>"]}
"options" must have between 2 and 5 short, tappable choices — never leave it \
empty, never expect free-text input.

Shape 2 — to conclude the triage (do this within 5 questions total, sooner \
if you already have enough information):
{"type":"result","urgency":"self_care","summary":"<1-2 sentences, no diagnosis, just what to do next>"}
"urgency" must be exactly one of: "self_care", "see_doctor", "urgent", "emergency".

Rules:
- If at any point the description includes chest pain, severe or \
uncontrolled bleeding, difficulty breathing, stroke symptoms (face drooping, \
slurred speech, one-sided weakness), suicidal thoughts, or a severe allergic \
reaction, immediately return a result with urgency "emergency" — do not ask \
further questions.
- Never state or imply what condition the patient has. Only urgency and \
next-step guidance.
- Ask exactly one question per turn.

Keep the JSON keys and the urgency values in English exactly as specified, \
whatever language the patient-facing text is written in."""


class TriageStepRequest(BaseModel):
    transcript: str = ""
    language: str = "en"


@router.post("/triage")
async def triage_step(
    body: TriageStepRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    """One turn of the structured triage flow.

    Returns the model's raw JSON object under `step`, or null when the model
    couldn't be reached or didn't answer with JSON at all. The client still
    validates the shape — this only guarantees *some* object came back, not
    that it's a usable turn.
    """
    step = await llm.chat_json(
        _with_language(_TRIAGE_SYSTEM_PROMPT, body.language),
        body.transcript or "Begin the triage. Ask your first question.",
        temperature=0.2,
        max_tokens=300,
    )
    return success({"step": step if isinstance(step, dict) else None})
