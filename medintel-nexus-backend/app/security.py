import hashlib
import hmac
import ipaddress
from functools import lru_cache
from typing import Any

import jwt
from fastapi import Header
from jwt import PyJWKClient

from app.config import settings
from app.envelope import ApiError

DEV_USER_ID = "dev-user"

# What Supabase signs with now. Listed explicitly rather than passed through
# from the token, so a token can never nominate the algorithm it is checked
# under — including "none".
_ASYMMETRIC = ["ES256", "RS256"]


@lru_cache(maxsize=1)
def _jwks_client() -> PyJWKClient:
    """Supabase's public signing keys.

    Cached because this is consulted on every authenticated request and the
    keys change only when the project rotates them. PyJWKClient keeps its own
    key cache and refetches when a token arrives with an unfamiliar `kid`,
    which is what makes a rotation land without a restart.
    """
    base = settings.supabase_url.rstrip("/")
    if not base.startswith("http"):
        base = f"https://{base}"
    return PyJWKClient(f"{base}/auth/v1/.well-known/jwks.json")


def is_local_client(host: str | None) -> bool:
    """Whether a request came from this machine rather than off the network.

    A host that doesn't parse as an IP counts as local — the test client, a
    unix socket. That isn't a way in: anything arriving over TCP carries a
    real peer address, and a real address that isn't loopback is exactly what
    this is looking for.
    """
    if not host:
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return True

# Longest nonce worth answering. The proof route is unauthenticated by
# necessity — it is what the app uses to decide whether to authenticate at
# all — so it should not hash megabytes on a stranger's request.
_MAX_NONCE = 128


def discovery_proof(nonce: str) -> str | None:
    """Proof that this process holds the configured discovery secret.

    Returned to a client that offers a random ``nonce``, which is what makes
    it a proof rather than a password: the answer is different every time,
    so a host that overhears one learns nothing it can replay. Returns None
    when no secret is configured, which the app reads as "this backend can't
    be verified" and refuses to adopt.
    """
    if not settings.discovery_secret or not nonce:
        return None
    if len(nonce) > _MAX_NONCE:
        return None
    return hmac.new(
        settings.discovery_secret.encode(),
        nonce.encode(),
        hashlib.sha256,
    ).hexdigest()


def get_current_user_id(authorization: str = Header(default="")) -> str:
    """Verifies the Supabase-issued JWT sent as a Bearer token and returns
    the Supabase auth user id (the token's ``sub`` claim).

    The backend never issues its own tokens — auth stays entirely on the
    Supabase client SDK side; this only validates what it was handed.
    """
    if not authorization.startswith("Bearer "):
        raise ApiError(401, "Missing bearer token.")
    token = authorization.removeprefix("Bearer ").strip()

    if settings.auth_disabled:
        return DEV_USER_ID

    try:
        algorithm = jwt.get_unverified_header(token).get("alg", "")
    except jwt.PyJWTError as exc:
        raise ApiError(401, "That isn't a readable token.") from exc

    key, algorithms = _verification_key(token, algorithm)

    try:
        payload = jwt.decode(
            token, key, algorithms=algorithms, audience="authenticated"
        )
    except jwt.PyJWTError as exc:
        raise ApiError(401, "Your session has expired.") from exc

    return payload["sub"]


def _verification_key(token: str, algorithm: str) -> tuple[Any, list[str]]:
    """The key to check a token's signature against, chosen by how the token
    was signed rather than by configuration.

    Supabase projects sign with an asymmetric key (ES256) and publish the
    public half at a JWKS endpoint; older ones used a single shared HS256
    secret. A project that has rotated holds both — the new key signing
    today's sessions, the old one still listed so tokens issued before the
    rotation keep working until they expire. Reading the algorithm off each
    token covers that overlap with no setting to get wrong.

    Reading it off the token is safe here because the algorithm only selects
    which key is used, and each branch pins the algorithms `jwt.decode` will
    accept to match. What it can't do is talk the server into a weaker check:
    an ES256 token cannot ask to be verified as HS256 against a secret, which
    is the confusion this pattern is usually warned about.
    """
    if algorithm == "HS256":
        if not settings.supabase_jwt_secret:
            raise ApiError(
                401,
                "This token was signed with the legacy HS256 secret, which "
                "this server doesn't have. Signing in again will issue a "
                "current one.",
            )
        return settings.supabase_jwt_secret, ["HS256"]

    if not settings.supabase_url:
        raise ApiError(500, "SUPABASE_URL is not configured on the server.")

    try:
        return _jwks_client().get_signing_key_from_jwt(token).key, _ASYMMETRIC
    except jwt.PyJWTError as exc:
        raise ApiError(401, "That token wasn't signed by this project.") from exc
    except Exception as exc:
        # Reaching Supabase is a dependency of verifying anything, so a
        # network failure is the server's problem, not a bad token.
        raise ApiError(503, "Couldn't reach Supabase to verify the token.") from exc
