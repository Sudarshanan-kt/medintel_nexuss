import asyncio
import logging
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app import records_db
from app.config import settings
from app.envelope import (
    ApiError,
    api_error_handler,
    error_body,
    unhandled_error_handler,
    validation_error_handler,
)
from app.security import discovery_proof, is_local_client
from app.routers import (
    assistant,
    interactions,
    patients,
    pharmacies,
    prescriptions,
    reports,
    savings,
)
from app import llm, store

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Cleans up after whatever the last process was in the middle of.

    Records outlive the process now, but the background tasks working on
    them do not. A scan left saying "processing" by a restart would be
    polled forever, so it is reset to `failed` — a state the client already
    offers Try again on, which re-runs the pipeline over the image still
    sitting in `uploads/`. See `records_db.fail_interrupted_processing`.
    """
    interrupted = records_db.fail_interrupted_processing()
    if interrupted:
        logger.info(
            "Reset %d scan(s) left mid-processing by the previous run; "
            "they can be retried from the app.",
            interrupted,
        )

    warm_task = None
    if settings.llm_warm_interval_seconds > 0:
        warm_task = asyncio.create_task(_keep_model_warm())

    try:
        yield
    finally:
        if warm_task is not None:
            warm_task.cancel()
            with suppress(asyncio.CancelledError):
                await warm_task


async def _keep_model_warm() -> None:
    """Holds the model in memory for as long as this process runs.

    Ollama unloads an idle model, and the reload costs seconds the app has
    no way to distinguish from being broken — the LLM-backed features
    degrade quietly by design, so a slow first call and a dead server look
    identical from the phone. Paying that cost here, on a timer, means the
    user never pays it.

    Runs on startup as well as on the interval, so the model is resident
    before the first scan rather than after it.
    """
    while True:
        await llm.warm()
        await asyncio.sleep(settings.llm_warm_interval_seconds)


app = FastAPI(title="MedIntel Nexus API", version="0.1.0", lifespan=lifespan)

def add_cors(app: FastAPI, origins: list[str]) -> None:
    """Grants browser access to [origins], and to nothing if that is empty.

    Empty is the default and is right for the Android app: CORS is a browser
    rule and a native HTTP client never sends an Origin, so there is nothing
    to grant. It matters only when the Flutter web build is pointed here.

    Credentials stay off. `Access-Control-Allow-Credentials` is about cookies
    and TLS client certs, and this API authenticates from a Bearer header,
    which allow_headers already covers. Off also caps the damage of a "*"
    finding its way back into CORS_ORIGINS: with credentials disabled a
    wildcard can only ever be a literal "*", which browsers refuse to use for
    credentialed requests. With them enabled, Starlette quietly upgrades the
    same wildcard into an echo of whichever origin asked, which is a real
    grant to every site on the internet.
    """
    if not origins:
        return
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )


add_cors(app, settings.cors_origins)


@app.middleware("http")
async def confine_disabled_auth_to_this_machine(request: Request, call_next):
    """Keeps AUTH_DISABLED from becoming an open door onto the network.

    The flag treats every caller as `dev-user`, which is a reasonable way to
    work before Supabase is wired up — and the server binds 0.0.0.0, because
    a phone has to reach it. Together those mean anyone on the same Wi-Fi
    can read and write patient records with any string in the Authorization
    header. On café, hospital or campus Wi-Fi that is everyone.

    The two settings are individually fine and only dangerous combined, so
    this refuses the combination rather than either half: with auth off, the
    API serves this machine only. Checked per request rather than at startup
    because it should hold however uvicorn was launched, including by hand.
    """
    if settings.auth_disabled:
        client = request.client.host if request.client else None
        if not is_local_client(client):
            return JSONResponse(
                status_code=403,
                content=error_body(
                    "This server is running with authentication disabled, so "
                    "it only answers requests from the machine it runs on. "
                    "Set SUPABASE_JWT_SECRET and AUTH_DISABLED=false to reach "
                    "it from a phone."
                ),
            )
    return await call_next(request)


app.add_exception_handler(ApiError, api_error_handler)
app.add_exception_handler(RequestValidationError, validation_error_handler)
app.add_exception_handler(Exception, unhandled_error_handler)

app.include_router(patients.router, prefix="/api/v1")
app.include_router(prescriptions.router, prefix="/api/v1")
app.include_router(reports.router, prefix="/api/v1")
app.include_router(assistant.router, prefix="/api/v1")
app.include_router(interactions.router, prefix="/api/v1")
app.include_router(pharmacies.router, prefix="/api/v1")
app.include_router(savings.router, prefix="/api/v1")


@app.get("/health")
def health(nonce: str = "") -> dict:
    """Liveness, and — given a nonce — proof of which backend this is.

    Plain `curl localhost:8000/health` still answers `{"status": "ok"}`.
    The nonce is for the app's LAN sweep: it has to pick one host out of a
    subnet, and every impostor can return "ok" too. See
    `security.discovery_proof`.
    """
    body = {"status": "ok"}
    proof = discovery_proof(nonce)
    if proof is not None:
        body["proof"] = proof
    return body


@app.get("/health/llm")
async def llm_health() -> dict:
    """Whether the local model is actually up and loaded.

    Worth its own route because every LLM-backed feature degrades quietly by
    design — a scan that comes back "couldn't read this" looks identical
    whether the image was bad or `ollama serve` isn't running. This says
    which.
    """
    reachable = await llm.health()
    return {
        "status": "ok" if reachable else "unavailable",
        "base_url": settings.llm_base_url,
        "model": settings.llm_model,
        "hint": None
        if reachable
        else (
            f"Start the local model with `ollama serve`, then "
            f"`ollama pull {settings.llm_model}`."
        ),
    }


@app.put("/dev-storage/{upload_id}")
async def dev_storage_put(upload_id: str, request: Request) -> dict:
    """Stand-in for a real signed-URL storage target (S3/GCS/Supabase
    Storage). The prescription-uploads flow issues a `signed_url` pointing
    here and PUTs the raw image bytes to it directly (no auth header — this
    mirrors real presigned-URL behavior). Bytes are saved to disk so the
    OCR pipeline in app/store.py has something to read.
    """
    body = await request.body()
    store.save_upload_bytes(upload_id, body)
    return {"status": "ok"}
