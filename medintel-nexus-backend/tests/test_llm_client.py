"""The local-LLM client, exercised against a stand-in server.

These cover the failure paths deliberately, because every LLM-backed feature
in this app degrades quietly by design — if `chat` returned something
truthy on an outage, a drug-interaction check would silently report "no
interactions found" when it never ran.
"""

import functools
import json

import httpx
import pytest

from app import llm
from app.config import settings


def _serve(handler):
    """Points the client at an in-process server implementing [handler]."""
    original = httpx.AsyncClient

    def factory(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    return factory


def _reply(content: str, status: int = 200) -> httpx.Response:
    return httpx.Response(
        status,
        json={"choices": [{"message": {"content": content}}]},
    )


@pytest.fixture
def local_server(monkeypatch):
    """Installs a handler as the local model, and hands back the requests it
    saw so tests can assert on what was actually sent."""
    seen = []

    def install(handler):
        @functools.wraps(handler)
        def recording(request: httpx.Request) -> httpx.Response:
            seen.append(request)
            return handler(request)

        monkeypatch.setattr(httpx, "AsyncClient", _serve(recording))
        return seen

    return install


@pytest.mark.asyncio
async def test_posts_to_the_configured_local_endpoint(local_server, monkeypatch):
    monkeypatch.setattr(settings, "llm_base_url", "http://localhost:11434/v1")
    monkeypatch.setattr(settings, "llm_model", "qwen2.5:7b-instruct")
    seen = local_server(lambda request: _reply("hello"))

    result = await llm.chat([{"role": "user", "content": "hi"}])

    assert result == "hello"
    assert str(seen[0].url) == "http://localhost:11434/v1/chat/completions"
    assert json.loads(seen[0].content)["model"] == "qwen2.5:7b-instruct"


@pytest.mark.asyncio
async def test_a_trailing_slash_on_the_base_url_does_not_double_up(
    local_server, monkeypatch
):
    monkeypatch.setattr(settings, "llm_base_url", "http://localhost:11434/v1/")
    seen = local_server(lambda request: _reply("hello"))

    await llm.chat([{"role": "user", "content": "hi"}])

    assert str(seen[0].url) == "http://localhost:11434/v1/chat/completions"


@pytest.mark.asyncio
async def test_no_auth_header_unless_a_key_is_configured(
    local_server, monkeypatch
):
    """Ollama wants none; llama.cpp and LM Studio can be set to want one."""
    monkeypatch.setattr(settings, "llm_api_key", "")
    seen = local_server(lambda request: _reply("hello"))

    await llm.chat([{"role": "user", "content": "hi"}])

    assert "authorization" not in seen[0].headers

    monkeypatch.setattr(settings, "llm_api_key", "local-token")
    await llm.chat([{"role": "user", "content": "hi"}])

    assert seen[1].headers["authorization"] == "Bearer local-token"


@pytest.mark.asyncio
async def test_json_mode_is_only_requested_when_asked_for(
    local_server, monkeypatch
):
    seen = local_server(lambda request: _reply("{}"))

    await llm.chat([{"role": "user", "content": "hi"}])
    await llm.chat([{"role": "user", "content": "hi"}], json_mode=True)

    assert "response_format" not in json.loads(seen[0].content)
    assert json.loads(seen[1].content)["response_format"] == {
        "type": "json_object"
    }


@pytest.mark.asyncio
async def test_a_server_that_is_not_running_returns_none(
    local_server, monkeypatch
):
    def refuse(request):
        raise httpx.ConnectError("connection refused", request=request)

    local_server(refuse)

    assert await llm.chat([{"role": "user", "content": "hi"}]) is None


@pytest.mark.asyncio
async def test_a_model_that_was_never_pulled_returns_none(local_server):
    """Ollama answers 404 when the server is up but the model isn't there —
    the most likely first-run failure."""
    local_server(lambda request: httpx.Response(404, json={"error": "model not found"}))

    assert await llm.chat([{"role": "user", "content": "hi"}]) is None


@pytest.mark.asyncio
async def test_a_timeout_returns_none(local_server):
    def stall(request):
        raise httpx.ReadTimeout("too slow", request=request)

    local_server(stall)

    assert await llm.chat([{"role": "user", "content": "hi"}]) is None


@pytest.mark.asyncio
async def test_an_unexpected_response_shape_returns_none(local_server):
    local_server(lambda request: httpx.Response(200, json={"unexpected": True}))

    assert await llm.chat([{"role": "user", "content": "hi"}]) is None


@pytest.mark.asyncio
async def test_chat_json_parses_a_plain_object(local_server):
    local_server(lambda request: _reply('{"medicines": [{"raw_name": "Amoxicillin"}]}'))

    result = await llm.chat_json("system", "user")

    assert result == {"medicines": [{"raw_name": "Amoxicillin"}]}


@pytest.mark.asyncio
async def test_chat_json_survives_a_markdown_fence(local_server):
    """Smaller local models wrap JSON in a code fence despite being told not
    to. That's recoverable, so it shouldn't read as an outage."""
    local_server(lambda request: _reply('```json\n{"overall_risk": "none"}\n```'))

    assert await llm.chat_json("system", "user") == {"overall_risk": "none"}


@pytest.mark.asyncio
async def test_chat_json_returns_none_on_unparseable_output(local_server):
    local_server(lambda request: _reply("I'm sorry, I can't help with that."))

    assert await llm.chat_json("system", "user") is None


@pytest.mark.asyncio
async def test_health_reports_whether_the_model_answers(local_server):
    local_server(lambda request: _reply("ok"))
    assert await llm.health() is True


@pytest.mark.asyncio
async def test_health_is_false_when_the_server_is_down(local_server):
    def refuse(request):
        raise httpx.ConnectError("connection refused", request=request)

    local_server(refuse)
    assert await llm.health() is False
