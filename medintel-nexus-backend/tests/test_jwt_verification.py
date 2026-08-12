"""Verifying Supabase tokens across a signing-key rotation.

This project's Supabase has an ES256 key signing new sessions and a legacy
HS256 secret listed as the previous key, so both shapes have to verify and
neither may be usable to weaken the other.
"""

import base64
import hashlib
import hmac
import json
import time

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app import security
from app.config import settings
from app.envelope import ApiError
from app.security import DEV_USER_ID, get_current_user_id

USER_ID = "8f14e45f-cea1-4b2c-9d3e-000000000001"


@pytest.fixture(autouse=True)
def _real_auth(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "auth_disabled", False)
    monkeypatch.setattr(settings, "supabase_url", "https://project.supabase.co")
    security._jwks_client.cache_clear()


@pytest.fixture
def signing_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


def _es256(key: ec.EllipticCurvePrivateKey, **claims) -> str:
    payload = {
        "sub": USER_ID,
        "aud": "authenticated",
        "exp": int(time.time()) + 3600,
        **claims,
    }
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": "test-key"})


class _FakeJWKS:
    """Stands in for Supabase's JWKS endpoint."""

    def __init__(self, key: ec.EllipticCurvePrivateKey | None) -> None:
        self._key = key

    def get_signing_key_from_jwt(self, token: str):
        if self._key is None:
            raise jwt.PyJWTError("no key for that kid")
        return type("Key", (), {"key": self._key.public_key()})()


def _serve_jwks(monkeypatch: pytest.MonkeyPatch, key) -> None:
    monkeypatch.setattr(security, "_jwks_client", lambda: _FakeJWKS(key))


def _hs256_token_signed_with(secret: bytes, claims: dict) -> str:
    """A JWT built without PyJWT, so it can hold combinations PyJWT declines
    to produce."""
    part = lambda obj: base64.urlsafe_b64encode(  # noqa: E731
        json.dumps(obj).encode()
    ).rstrip(b"=")
    signing_input = b".".join(
        [part({"alg": "HS256", "typ": "JWT"}), part(claims)]
    )
    signature = base64.urlsafe_b64encode(
        hmac.new(secret, signing_input, hashlib.sha256).digest()
    ).rstrip(b"=")
    return b".".join([signing_input, signature]).decode()


def test_accepts_an_es256_token_signed_by_the_project(
    monkeypatch: pytest.MonkeyPatch, signing_key
) -> None:
    _serve_jwks(monkeypatch, signing_key)

    assert get_current_user_id(f"Bearer {_es256(signing_key)}") == USER_ID


def test_rejects_an_es256_token_signed_by_someone_else(
    monkeypatch: pytest.MonkeyPatch, signing_key
) -> None:
    someone_else = ec.generate_private_key(ec.SECP256R1())
    _serve_jwks(monkeypatch, signing_key)

    with pytest.raises(ApiError) as raised:
        get_current_user_id(f"Bearer {_es256(someone_else)}")

    assert raised.value.status_code == 401


def test_rejects_an_expired_token(
    monkeypatch: pytest.MonkeyPatch, signing_key
) -> None:
    _serve_jwks(monkeypatch, signing_key)
    stale = _es256(signing_key, exp=int(time.time()) - 60)

    with pytest.raises(ApiError) as raised:
        get_current_user_id(f"Bearer {stale}")

    assert raised.value.status_code == 401


def test_still_accepts_a_legacy_hs256_token(monkeypatch: pytest.MonkeyPatch) -> None:
    """Sessions issued before the project rotated keep working until they
    expire, which is why the previous key is still listed."""
    monkeypatch.setattr(settings, "supabase_jwt_secret", "legacy-shared-secret")
    token = jwt.encode(
        {"sub": USER_ID, "aud": "authenticated", "exp": int(time.time()) + 3600},
        "legacy-shared-secret",
        algorithm="HS256",
    )

    assert get_current_user_id(f"Bearer {token}") == USER_ID


def test_an_hs256_token_cannot_be_verified_against_the_public_key(
    monkeypatch: pytest.MonkeyPatch, signing_key
) -> None:
    """The classic confusion attack: sign with the public key as if it were
    a shared secret and hope the server checks it that way. It doesn't —
    HS256 is only ever checked against the configured secret, and with none
    configured there is nothing to check against."""
    monkeypatch.setattr(settings, "supabase_jwt_secret", "")
    _serve_jwks(monkeypatch, signing_key)
    public_pem = signing_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    # Assembled by hand: PyJWT won't encode this, which is a defence of its
    # own, but an attacker isn't using PyJWT.
    forged = _hs256_token_signed_with(
        public_pem,
        {"sub": "attacker", "aud": "authenticated", "exp": int(time.time()) + 3600},
    )

    with pytest.raises(ApiError) as raised:
        get_current_user_id(f"Bearer {forged}")

    assert raised.value.status_code == 401


def test_rejects_an_unsigned_token(monkeypatch: pytest.MonkeyPatch, signing_key) -> None:
    _serve_jwks(monkeypatch, signing_key)
    unsigned = jwt.encode(
        {"sub": "attacker", "aud": "authenticated"}, None, algorithm="none"
    )

    with pytest.raises(ApiError) as raised:
        get_current_user_id(f"Bearer {unsigned}")

    assert raised.value.status_code == 401


def test_reports_a_jwks_outage_as_a_server_problem(
    monkeypatch: pytest.MonkeyPatch, signing_key
) -> None:
    """A token nobody could check is not the same as a bad token, and a 401
    would send the app into a pointless sign-out loop."""

    def unreachable() -> None:
        raise OSError("network down")

    monkeypatch.setattr(security, "_jwks_client", unreachable)

    with pytest.raises(ApiError) as raised:
        get_current_user_id(f"Bearer {_es256(signing_key)}")

    assert raised.value.status_code == 503


def test_auth_disabled_still_short_circuits(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "auth_disabled", True)

    assert get_current_user_id("Bearer anything") == DEV_USER_ID


def test_missing_header_is_still_a_401() -> None:
    with pytest.raises(ApiError) as raised:
        get_current_user_id("")

    assert raised.value.status_code == 401
