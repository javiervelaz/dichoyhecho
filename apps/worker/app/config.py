"""Configuración del worker. Los topes de gasto no tienen default: si faltan, no arranca."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    service_token: str

    # Topes mensuales en USD (obligatorios, sin default a propósito)
    llm_monthly_cap_usd: float
    tts_monthly_cap_usd: float
    stt_monthly_cap_usd: float

    anthropic_api_key: str = ""
    model_fast: str = "claude-haiku-5-5"
    model_analysis: str = "claude-sonnet-5-5"


def load_settings() -> Settings:
    return Settings()  # lanza ValidationError si falta algo obligatorio
