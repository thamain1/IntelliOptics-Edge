# backend/api/app/main.py
from __future__ import annotations

import os
import logging
from typing import List

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
log = logging.getLogger("intellioptics.api")

# ------------------------------------------------------------------------------
# Environment / App flags
# ------------------------------------------------------------------------------
APP_NAME = os.getenv("APP_NAME", "IntelliOptics API")
APP_ENV = os.getenv("APP_ENV", "dev").lower()  # dev | staging | prod

# Hide docs/openapi in prod (or when explicitly requested)
DISABLE_OPENAPI = os.getenv("DISABLE_OPENAPI", "auto").lower()  # auto|true|false
if DISABLE_OPENAPI not in {"auto", "true", "false"}:
    DISABLE_OPENAPI = "auto"

hide_docs = (DISABLE_OPENAPI == "true") or (
    DISABLE_OPENAPI == "auto" and APP_ENV == "prod"
)

docs_url = None if hide_docs else "/docs"
redoc_url = None if hide_docs else "/redoc"
openapi_url = None if hide_docs else "/openapi.json"

# CORS
_raw_origins = os.getenv("CORS_ALLOW_ORIGINS", "*")
ALLOW_ORIGINS: List[str] = (
    ["*"]
    if _raw_origins.strip() == "*"
    else [o.strip() for o in _raw_origins.split(",") if o.strip()]
)

# ------------------------------------------------------------------------------
# DB bootstrap (kept compatible with your existing setup)
# ------------------------------------------------------------------------------
DB_URL = os.getenv("DB_URL") or os.getenv("POSTGRES_DSN") or os.getenv(
    "DATABASE_URL", ""
)
if not DB_URL:
    DB_URL = "sqlite:///./data/dev.db"
if DB_URL.startswith("postgres://"):
    DB_URL = DB_URL.replace("postgres://", "postgresql://", 1)
log.info(f"DB_URL resolved to: {DB_URL}")

# ------------------------------------------------------------------------------
# Optional API-key dependency (enforced if INTELLIOPTICS_API_KEY is set)
# ------------------------------------------------------------------------------
try:
    from .security import require_api_key  # optional
    _has_security = True
    log.info("security.require_api_key available")
except Exception as e:  # pragma: no cover
    _has_security = False
    log.warning(f"security module not available: {e}")

ALERTS_REQUIRE_API_KEY = os.getenv("ALERTS_REQUIRE_API_KEY", "auto").lower()
if ALERTS_REQUIRE_API_KEY not in {"auto", "true", "false"}:
    ALERTS_REQUIRE_API_KEY = "auto"

INTELLIOPTICS_API_KEY = os.getenv("INTELLIOPTICS_API_KEY", "")

def _alerts_dependencies():
    if not _has_security:
        return []
    if ALERTS_REQUIRE_API_KEY == "true":
        return [Depends(require_api_key)]
    if ALERTS_REQUIRE_API_KEY == "false":
        return []
    # auto
    return [Depends(require_api_key)] if INTELLIOPTICS_API_KEY else []

# ------------------------------------------------------------------------------
# App
# ------------------------------------------------------------------------------
app = FastAPI(
    title=APP_NAME,
    version=os.getenv("APP_VERSION", "1.0.0"),
    docs_url=docs_url,
    redoc_url=redoc_url,
    openapi_url=openapi_url,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOW_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Tidy up headers safely
@app.middleware("http")
async def strip_server_header(request, call_next):
    response = await call_next(request)
    try:
        del response.headers["server"]
    except KeyError:
        pass
    response.headers["x-app"] = APP_NAME
    response.headers["x-env"] = APP_ENV
    return response

# ------------------------------------------------------------------------------
# Routers — mount priority: email, alerts, annotated, then iq_* (last)
# ------------------------------------------------------------------------------
def _mount_router(name: str, import_path: str, include_kwargs: dict | None = None):
    """
    Helper to import and mount a router with clearer error logs.
    """
    try:
        module = __import__(import_path, fromlist=["router"])
        router = getattr(module, "router")
        app.include_router(router, **(include_kwargs or {}))
        log.info(f"Mounted router: {name}")
    except Exception as e:
        # Log full exception string for easier diagnosis
        log.warning(f"{name} router not mounted: {e}")

# 1) Email first (independent of DB)
_mount_router("email", "app.emails")

# 2) Alerts next (our priority)
_mount_router(
    "alerts",
    "app.alerts",
    {"dependencies": _alerts_dependencies()},
)

# 3) Annotated snapshots server
_mount_router("annotated", "app.annotated")

# 4) iq_* last (these have historically caused circular-import warnings)
_mount_router("iq_read", "app.iq_read")
_mount_router("iq_create", "app.iq_create")

# ------------------------------------------------------------------------------
# Health Endpoints
# ------------------------------------------------------------------------------
@app.get("/v1/health")
def health_v1():
    return {
        "ok": True,
        "env": APP_ENV,
        "docs_hidden": hide_docs,
        "db_url_scheme": DB_URL.split(":", 1)[0],
    }

@app.get("/")
def root():
    return JSONResponse({"message": "IntelliOptics API running", "env": APP_ENV})
