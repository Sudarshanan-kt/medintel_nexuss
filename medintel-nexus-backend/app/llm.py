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
    """Whether the local model server is up and holds the configured model.

    This used to run a one-token generation with a 10s timeout, which made
    the check lie in the most annoying way possible. Ollama unloads a model
    after a few idle minutes, and reloading 4.6GB takes far longer than ten
    seconds — so the probe timed out and the app announced "the AI model is
    not running" about a model that was fine and merely asleep. Whether it
    answers *right now* was never the useful question; whether it is there
    to answer is.

    Asking the model list instead is immediate, cannot be defeated by a cold
    load, and still catches the two failures worth catching: the server
    being down, and the model never having been pulled. Latency of an
    actual first request is handled where it belongs — by
    `llm_timeout_seconds` on the request itself, and by `warm()` keeping the
    model resident.
    """
    url = f"{settings.llm_base_url.rstrip('/')}/models"
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            res = await client.get(url, headers=_headers())
    except Exception:
        logger.error(
            "Local LLM server is not reachable at %s. Start it with "
            "`ollama serve`.",
            settings.llm_base_url,
        )
        return False

    if res.status_code >= 400:
        logger.error("Local LLM model list returned %s", res.status_code)
        return False

    try:
        ids = {m.get("id") for m in res.json().get("data", [])}
    except Exception:
        logger.exception("Local LLM returned an unexpected model list")
        return False

    # Ollama reports "qwen2.5:7b-instruct"; a server that tags differently
    # (":latest" appended, say) still counts as holding the model.
    wanted = settings.llm_model
    if any(i == wanted or i.startswith(f"{wanted}:") for i in ids if i):
        return True

    logger.error(_MODEL_MISSING_HINT, wanted, wanted)
    return False


async def warm() -> None:
    """Asks the server to load the model and hold it in memory.

    Ollama unloads after ~5 idle minutes, so the first request after a quiet
    spell pays a multi-second reload — which during a demo reads as the app
    hanging, or as the model being down. A periodic call with a keep_alive
    longer than the gap between calls keeps it resident.

    Ollama's own `/api/generate` carries `keep_alive`; the OpenAI-compatible
    surface this module otherwise speaks does not, so this reaches past it
    to the native endpoint and simply does nothing when pointed at a server
    that has no such route. Failure is never surfaced: a model that will not
    pre-load still works, just slowly, and `health()` reports the real state
    either way.
    """
    base = settings.llm_base_url.rstrip("/")
    if base.endswith("/v1"):
        base = base[: -len("/v1")]
    try:
        async with httpx.AsyncClient(timeout=settings.llm_warm_timeout_seconds) as c:
            await c.post(
                f"{base}/api/generate",
                json={
                    "model": settings.llm_model,
                    "prompt": "ok",
                    "stream": False,
                    "keep_alive": settings.llm_keep_alive,
                },
            )
    except Exception:
        logger.debug("Model warm-up did not complete", exc_info=True)
