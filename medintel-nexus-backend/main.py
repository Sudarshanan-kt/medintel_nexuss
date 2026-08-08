from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.envelope import ApiError, api_error_handler, unhandled_error_handler, validation_error_handler
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

app = FastAPI(title="MedIntel Nexus API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
def health() -> dict:
    return {"status": "ok"}


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
