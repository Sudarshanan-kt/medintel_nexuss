import uuid
from typing import List

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.envelope import success
from app.security import get_current_user_id

router = APIRouter(prefix="/assistant", tags=["assistant"])

# The Flutter app currently talks to Groq's chat-completions API directly for
# the assistant feature — these routes have no caller yet. Stubbed so the
# path exists ahead of moving that call server-side.


class ChatHistoryItem(BaseModel):
    id: str
    role: str
    content: str
    language: str = "en"


class SendMessageRequest(BaseModel):
    prompt: str
    history: List[ChatHistoryItem] = []
    language: str = "en"


@router.post("/messages")
def send_message(
    body: SendMessageRequest, user_id: str = Depends(get_current_user_id)
) -> dict:
    return success(
        {
            "id": f"msg_{uuid.uuid4().hex[:12]}",
            "role": "assistant",
            "content": "The assistant backend isn't wired up yet — this is a stub response.",
            "language": body.language,
            "is_streaming": False,
        }
    )


@router.get("/stream/{message_id}")
def stream_message(
    message_id: str, user_id: str = Depends(get_current_user_id)
) -> dict:
    return success({"id": message_id, "content": "", "done": True})
