from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    supabase_url: str = ""
    supabase_jwt_secret: str = ""
    # Dev-only escape hatch for running the API before a Supabase project is
    # wired up. Never enable this outside local development.
    auth_disabled: bool = False
    cors_origins: List[str] = ["*"]

    # ── Local LLM ────────────────────────────────────────────────────────
    # Inference runs on this machine, not a hosted API. The default targets
    # Ollama's OpenAI-compatible server (`ollama serve`, then
    # `ollama pull qwen2.5:7b-instruct`), but any local server speaking the
    # same shape works unchanged — llama.cpp's `llama-server`, LM Studio,
    # vLLM — by pointing llm_base_url at it.
    llm_base_url: str = "http://localhost:11434/v1"
    llm_model: str = "qwen2.5:7b-instruct"
    # Ollama ignores auth; llama.cpp and LM Studio can be configured to want
    # a token, so it's sent when set.
    llm_api_key: str = ""
    # Generous by design: a 7B model on CPU takes tens of seconds for a long
    # structured response, where a hosted 70B took two. Everything calling
    # into it is already asynchronous and polled.
    llm_timeout_seconds: float = 180.0


settings = Settings()
