import jwt
from fastapi import Header

from app.config import settings
from app.envelope import ApiError

DEV_USER_ID = "dev-user"


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

    if not settings.supabase_jwt_secret:
        raise ApiError(500, "SUPABASE_JWT_SECRET is not configured on the server.")

    try:
        payload = jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.PyJWTError as exc:
        raise ApiError(401, "Your session has expired.") from exc

    return payload["sub"]
