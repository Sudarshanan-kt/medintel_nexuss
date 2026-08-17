from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    supabase_url: str = ""
    # Only for projects still signing with the legacy shared secret, and for
    # tokens issued before a project rotated away from one. Current Supabase
    # projects sign with ES256 and are verified against the public keys at
    # SUPABASE_URL's JWKS endpoint, which needs no secret here — see
    # `security._verification_key`.
    supabase_jwt_secret: str = ""
    # Dev-only escape hatch for running the API before a Supabase project is
    # wired up. Never enable this outside local development.
    auth_disabled: bool = False
    # Browser origins allowed to call this API. Empty by default, and empty
    # is right for the Android app: CORS governs browsers, and a native
    # client isn't one. It matters when the Flutter web build is pointed
    # here, which is the only reason it's configurable.
    #
    # Not "*". Starlette does not leave a wildcard inert when credentials
    # are allowed — it echoes back whichever Origin asked, which is a valid
    # credentialed grant to every site on the internet, against a server on
    # the developer's LAN.
    #
    #   CORS_ORIGINS=["http://localhost:5000"]
    cors_origins: List[str] = []

    # Shared secret that lets the app tell this backend apart from anything
    # else answering on the LAN. The app sweeps the subnet looking for a
    # `/health` that responds, and without a secret to check, "responds"
    # is all it can go on — any host on a café or campus network could
    # answer first and start receiving bearer tokens and patient data.
    # `scripts/run.sh` generates one into .env on first run and prints it;
    # the same string goes into the app's server settings, once, and stays
    # valid as the machine's IP moves between networks.
    discovery_secret: str = ""

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
    # How long Ollama should hold the model in memory after a request, and
    # how often to re-ask. The interval has to be shorter than the hold, or
    # the model unloads in the gap and the next real request pays the
    # reload; 4 minutes against 30 leaves plenty of overlap. Set
    # llm_warm_interval_seconds to 0 to switch pre-loading off entirely, on
    # a machine where 4.6GB of resident model is not a fair trade.
    llm_keep_alive: str = "30m"
    llm_warm_interval_seconds: float = 240.0
    # A cold load of a 7B model reads several GB off disk. This bounds the
    # warm-up call only — never a user-facing request.
    llm_warm_timeout_seconds: float = 300.0


settings = Settings()
