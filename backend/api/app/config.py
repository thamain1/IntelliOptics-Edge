import os

from pydantic import BaseModel


def _env_flag(name: str, default: bool = False) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "on"}


class Settings(BaseModel):
    api_base_path: str = os.getenv("API_BASE_PATH", "/v1")
    allowed_origins: str = os.getenv("ALLOWED_ORIGINS", "*")

    # Azure AD auth
    azure_tenant_id: str | None = os.getenv("AZURE_AD_TENANT_ID") or os.getenv("AZ_TENANT_ID")
    azure_audience: str | None = os.getenv("AZURE_AD_AUDIENCE") or os.getenv("AZURE_AD_CLIENT_ID")
    azure_openid_config: str | None = os.getenv("AZURE_AD_OPENID_CONFIG")

    # IntelliOptics
    io_token: str | None = os.getenv("INTELLIOPTICS_API_TOKEN") or os.getenv("INTELLOPTICS_API_TOKEN")
    io_endpoint: str | None = os.getenv("INTELLIOPTICS_ENDPOINT") or os.getenv("INTELLOPTICS_API_BASE")

    # Service Bus
    sb_namespace: str | None = os.getenv("AZ_SB_NAMESPACE")
    sb_conn_str: str | None = os.getenv("AZ_SB_CONN_STR") or os.getenv("SERVICE_BUS_CONN")
    sb_image_queue: str = os.getenv("SB_QUEUE_LISTEN", "image-queries")
    sb_results_queue: str = os.getenv("SB_QUEUE_SEND", "inference-results")
    sb_feedback_queue: str = os.getenv("SB_QUEUE_FEEDBACK", "feedback")
    sb_use_dev_send_override: bool = _env_flag("SB_USE_DEV_SEND_OVERRIDE")

    # Storage
    blob_account: str = os.getenv("AZ_BLOB_ACCOUNT", "")
    blob_container: str = os.getenv("AZ_BLOB_CONTAINER", "images")
    blob_conn_str: str | None = os.getenv("AZ_BLOB_CONN_STR")

    # Postgres
    pg_dsn: str | None = os.getenv("POSTGRES_DSN")
    pg_host: str = os.getenv("PG_HOST", "localhost")
    pg_db: str = os.getenv("PG_DB", "intellioptics")
    pg_user: str = os.getenv("PG_USER", "postgres")
    pg_password: str = os.getenv("PG_PASSWORD", "")
    pg_sslmode: str = os.getenv("PG_SSLMODE", "require")


settings = Settings()
