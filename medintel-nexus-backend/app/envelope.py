import logging
from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class ApiError(Exception):
    """Raised by route handlers to produce the client's expected
    ``{"error": {"message": "..."}}`` body with a specific status code."""

    def __init__(self, status_code: int, message: str) -> None:
        self.status_code = status_code
        self.message = message


def success(data: Any) -> dict:
    return {"data": data}


def _error_body(message: str) -> dict:
    return {"error": {"message": message}}


async def api_error_handler(request: Request, exc: ApiError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content=_error_body(exc.message))


async def validation_error_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    first = exc.errors()[0]
    field = ".".join(str(part) for part in first["loc"] if part != "body")
    message = f"{field}: {first['msg']}" if field else first["msg"]
    return JSONResponse(status_code=422, content=_error_body(message))


async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    # The client is deliberately told nothing useful, so the traceback has to
    # go somewhere or a 500 is unattributable — which is exactly how a broken
    # reference-range parse looked identical to "the backend is down".
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500, content=_error_body("Something went wrong on our end.")
    )
