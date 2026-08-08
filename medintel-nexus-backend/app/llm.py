"""The one place this backend talks to a language model.

Inference is local — Ollama by default (see `settings.llm_base_url`) — so
prescriptions, lab reports and chat messages never leave the machine. That
is the point: this is patient health data, and posting it to a hosted API
would mean a third party holds it.

Everything here returns None rather than raising when the model can't be
reached or its answer can't be trusted. Callers already distinguish "the
check couldn't run" from "the check ran and found nothing" — that
distinction is a safety property in this app, not a style preference, so
this module must never paper over an outage with an empty result.

Practical note: a local 7B model is meaningfully weaker at clinical
reasoning than a hosted 70B. It is good at the jobs asked of it here —
restructuring text into a fixed schema, rephrasing, conversational replies —
and should not be relied on for interaction verdicts; see the drug-data
route for that.
"""

import json
import logging
from typing import Any, Dict, List, Optional

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

Message = Dict[str, str]

# Ollama returns this when the server is up but the model was never pulled.
# It's the single most likely first-run failure, so it gets its own message.
_MODEL_MISSING_HINT = (
    "Model %r is not available on the local LLM server. Pull it first: "
    "`ollama pull %s`"
)


def _endpoint() -> str:
    return f"{settings.llm_base_url.rstrip('/')}/chat/completions"


def _headers() -> Dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if settings.llm_api_key:
        headers["Authorization"] = f"Bearer {settings.llm_api_key}"
    return headers


async def chat(
    messages: List[Message],
    *,
    temperature: float = 0.2,
    max_tokens: int = 800,
    json_mode: bool = False,
    timeout: Optional[float] = None,
) -> Optional[str]:
    """Runs a chat completion locally and returns the reply text.

    [json_mode] asks the server to constrain the reply to a JSON object.
    Returns None on any failure — server down, model not pulled, timeout,
    malformed response.
    """
    payload: Dict[str, Any] = {
        "model": settings.llm_model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    if json_mode:
        payload["response_format"] = {"type": "json_object"}

    try:
        async with httpx.AsyncClient(
            timeout=timeout or settings.llm_timeout_seconds
        ) as client:
            res = await client.post(_endpoint(), headers=_headers(), json=payload)
    except httpx.ConnectError:
        logger.error(
            "Local LLM server is not reachable at %s. Start it with "
            "`ollama serve`.",
            settings.llm_base_url,
        )
        return None
    except httpx.TimeoutException:
        logger.error(
            "Local LLM timed out after %ss. A larger model on CPU may need "
            "llm_timeout_seconds raised.",
            timeout or settings.llm_timeout_seconds,
        )
        return None
    except Exception:
        logger.exception("Local LLM request failed")
        return None

    if res.status_code == 404:
        logger.error(_MODEL_MISSING_HINT, settings.llm_model, settings.llm_model)
        return None
    if res.status_code >= 400:
        logger.error(
            "Local LLM returned %s: %s", res.status_code, res.text[:400]
        )
        return None

    try:
        content = res.json()["choices"][0]["message"]["content"]
    except Exception:
        logger.exception("Local LLM returned an unexpected response shape")
        return None

    return content if isinstance(content, str) else None


async def chat_json(
    system_prompt: str,
    user_content: str,
    *,
    temperature: float = 0.1,
    max_tokens: int = 800,
    timeout: Optional[float] = None,
) -> Optional[dict]:
    """Convenience wrapper for the structured-extraction calls: one system
    prompt, one user message, a JSON object back.

    Smaller local models sometimes wrap their JSON in a markdown fence
    despite being asked not to, so that gets stripped before parsing rather
    than being thrown away as a failure.
    """
    content = await chat(
        [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ],
        temperature=temperature,
        max_tokens=max_tokens,
        json_mode=True,
        timeout=timeout,
    )
    if content is None:
        return None

    try:
        return json.loads(_strip_code_fence(content))
    except json.JSONDecodeError:
        logger.error("Local LLM did not return valid JSON: %s", content[:400])
        return None


def _strip_code_fence(content: str) -> str:
    text = content.strip()
    if not text.startswith("```"):
        return text
    # ```json\n{...}\n```  ->  {...}
    body = text.split("\n", 1)[1] if "\n" in text else ""
    return body.rsplit("```", 1)[0].strip()


async def health() -> bool:
    """Whether the local model is loaded and answering. Used by /health so a
    misconfigured setup is obvious before a scan silently fails."""
    return await chat(
        [{"role": "user", "content": "ok"}], max_tokens=1, timeout=10
    ) is not None
