"""What a browser is allowed to do with this API.

The Android app is unaffected by all of it — CORS is enforced by browsers,
and a native HTTP client never sends an Origin. These exist because the
backend listens on the LAN, so "which websites can script requests at it"
is a question with a real answer.
"""

from fastapi import FastAPI
from fastapi.testclient import TestClient

from main import add_cors
from main import app as real_app

ALLOWED = "http://localhost:5000"
SOME_WEBSITE = "https://evil.example"


def _app_allowing(*origins: str) -> TestClient:
    app = FastAPI()
    add_cors(app, list(origins))

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok"}

    return TestClient(app)


def test_grants_nothing_by_default() -> None:
    """The shipped configuration. No browser origin is allowed, so a page
    can send a request but can never read the response."""
    response = TestClient(real_app).get(
        "/health", headers={"Origin": SOME_WEBSITE}
    )

    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers


def test_allows_a_configured_origin() -> None:
    response = _app_allowing(ALLOWED).get(
        "/health", headers={"Origin": ALLOWED}
    )

    assert response.headers["access-control-allow-origin"] == ALLOWED


def test_ignores_an_origin_that_was_not_configured() -> None:
    response = _app_allowing(ALLOWED).get(
        "/health", headers={"Origin": SOME_WEBSITE}
    )

    assert "access-control-allow-origin" not in response.headers


def test_never_allows_credentials() -> None:
    """Cookies and client certs are not how this API authenticates, and the
    header is what makes a wildcard dangerous."""
    response = _app_allowing(ALLOWED).get(
        "/health", headers={"Origin": ALLOWED}
    )

    assert "access-control-allow-credentials" not in response.headers


def test_a_wildcard_cannot_become_a_per_origin_grant() -> None:
    """A "*" put back into CORS_ORIGINS is permissive, but it stays a
    literal "*" — the form browsers refuse to send credentials to — instead
    of being echoed back as the caller's own origin."""
    response = _app_allowing("*").get(
        "/health", headers={"Origin": SOME_WEBSITE}
    )

    assert response.headers["access-control-allow-origin"] == "*"
    assert "access-control-allow-credentials" not in response.headers


def test_preflight_from_an_unknown_origin_is_not_approved() -> None:
    response = _app_allowing(ALLOWED).options(
        "/health",
        headers={
            "Origin": SOME_WEBSITE,
            "Access-Control-Request-Method": "GET",
        },
    )

    assert "access-control-allow-origin" not in response.headers
