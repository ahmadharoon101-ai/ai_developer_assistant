import secrets

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    ai_provider: str = "gemini"
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-sonnet-5"

    gemini_models: str = "gemini-2.5-flash,gemini-2.5-pro"
    anthropic_models: str = "claude-sonnet-5,claude-opus-5,claude-haiku-4-5-20251001"

    github_client_id: str = ""
    github_client_secret: str = ""
    github_redirect_uri: str = "http://localhost:8000/github/oauth/callback"
    github_scope: str = "repo read:user"

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = "AI Developer Assistant <noreply@example.com>"

    jwt_secret: str = ""
    jwt_expire_minutes: int = 60 * 24 * 7
    database_path: str = "app.db"
    cors_origins: str = "*"

    @property
    def active_key(self) -> str:
        return self.anthropic_api_key if self.ai_provider == "anthropic" else self.gemini_api_key

    @property
    def active_model(self) -> str:
        return self.anthropic_model if self.ai_provider == "anthropic" else self.gemini_model


    @property
    def available_models(self) -> list[str]:
        raw = self.anthropic_models if self.ai_provider == "anthropic" else self.gemini_models
        models = [m.strip() for m in raw.split(",") if m.strip()]
        if self.active_model not in models:
            models.insert(0, self.active_model)
        return models


settings = Settings()
settings.ai_provider = settings.ai_provider.strip().lower()

if not settings.jwt_secret:
    settings.jwt_secret = secrets.token_urlsafe(48)
    print("WARNING: JWT_SECRET not set. Using a temporary secret; logins reset on restart.")
if not settings.active_key:
    print(f"WARNING: no API key set for provider '{settings.ai_provider}'. Chat will return an error until you add one to .env")
