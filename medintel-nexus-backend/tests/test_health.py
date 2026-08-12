import hashlib
import hmac

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from main import app

client = TestClient(app)


@pytest.fixture
def discovery_secret(monkeypatch: pytest.MonkeyPatch) -> str:
    secret = "0123456789abcdef0123456789abcdef"
    monkeypatch.setattr(settings, "discovery_secret", secret)
    return secret


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_proves_it_holds_the_discovery_secret(discovery_secret: str) -> None:
    response = client.get("/health", params={"nonce": "abc123"})
    assert response.status_code == 200
    assert response.json()["proof"] == hmac.new(
        discovery_secret.encode(), b"abc123", hashlib.sha256
    ).hexdigest()


def test_health_proof_changes_with_the_nonce(discovery_secret: str) -> None:
    """What stops a host that overheard one exchange from replaying it."""
    first = client.get("/health", params={"nonce": "one"}).json()["proof"]
    second = client.get("/health", params={"nonce": "two"}).json()["proof"]
    assert first != second


def test_health_omits_proof_without_a_configured_secret(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The app reads a missing proof as "unverifiable" and declines to adopt
    this server, rather than falling back to trusting whatever answered."""
    monkeypatch.setattr(settings, "discovery_secret", "")
    assert "proof" not in client.get("/health", params={"nonce": "abc"}).json()


def test_health_refuses_to_hash_an_oversized_nonce(discovery_secret: str) -> None:
    assert "proof" not in client.get("/health", params={"nonce": "x" * 129}).json()


def test_patients_me_requires_auth() -> None:
    response = client.get("/api/v1/patients/me")
    assert response.status_code == 401
    assert "error" in response.json()


def _caller_at(host: str) -> httpx.AsyncClient:
    """A client the app sees as connecting from [host], which is the only
    thing separating the developer's own machine from the rest of the Wi-Fi.
    TestClient always looks local, so it can't express this."""
    return httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app, client=(host, 51000)),
        base_url="http://testserver",
    )


@pytest.mark.asyncio
async def test_disabled_auth_serves_this_machine_only(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """AUTH_DISABLED treats any bearer string as `dev-user`. Bound to
    0.0.0.0 so a phone can reach it, that would hand patient records to
    everyone on the Wi-Fi, so off-machine callers are refused outright."""
    monkeypatch.setattr(settings, "auth_disabled", True)

    async with _caller_at("192.168.0.42") as from_lan:
        response = await from_lan.get(
            "/api/v1/patients/me", headers={"Authorization": "Bearer anything"}
        )

    assert response.status_code == 403
    assert "authentication disabled" in response.json()["error"]["message"]


@pytest.mark.asyncio
async def test_disabled_auth_still_works_from_localhost(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The point of the flag — developing before Supabase is wired up —
    is untouched."""
    monkeypatch.setattr(settings, "auth_disabled", True)

    async with _caller_at("127.0.0.1") as local:
        response = await local.get(
            "/api/v1/patients/me", headers={"Authorization": "Bearer anything"}
        )

    assert response.status_code == 200
    assert response.json()["data"]["id"] == "dev-user"


@pytest.mark.asyncio
async def test_lan_callers_are_fine_once_auth_is_on(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The guard is about the combination, not about blocking the phone:
    with real auth configured, a LAN caller gets the normal 401 and can
    authenticate past it."""
    monkeypatch.setattr(settings, "auth_disabled", False)

    async with _caller_at("192.168.0.42") as from_lan:
        response = await from_lan.get("/api/v1/patients/me")

    assert response.status_code == 401
