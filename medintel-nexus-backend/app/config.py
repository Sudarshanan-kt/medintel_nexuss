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

    # Same Groq account/key the Flutter assistant feature already uses
    # (console.groq.com/keys) — powers the real drug-interaction engine.
    groq_api_key: str = ""


settings = Settings()
