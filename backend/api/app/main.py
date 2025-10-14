# backend/api/app/main.py
import logging
import os
from typing import Any, Dict

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

log = logging.getLogger("intellioptics.api")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))


def env_bool(name: str, default: bool = False) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "y", "on"}


APP_ENV = os.getenv("APP_ENV", "prod")
DISABLE_OPENAPI = env_bool("DISABLE_OPENAPI", default=(APP_ENV != "dev"))

app = FastAPI(
    title="IntelliOptics API",
    version="dev" if APP_ENV == "dev" else "prod",
    openapi_url=None if DISABLE_OPENAPI else "/openapi.json",
    docs_url=None if DISABLE_OPENAPI else "/docs",
    redoc_url=None if DISABLE_OPENAPI else "/redoc",
)


# -------- Security/diagnostic middleware --------
@app.middleware("http")
async def _headers(request: Request, call_next):
    resp = await call_next(request)
    # Tighten common security headers; avoid mutating with .pop (Starlette MutableHeaders has no pop)
    for k, v in [
        ("X-Content-Type-Options", "nosniff"),
        ("Referrer-Policy", "no-referrer"),
        ("X-Frame-Options", "DENY"),
    ]:
        resp.headers[k] = v
    # Remove "server" header if present
    try:
        del resp.headers["server"]
    except KeyError:
        pass
    return resp


# -------- Health --------
@app.get("/", summary="Root")
async def root() -> Dict[str, Any]:
    return {"ok": True, "env": APP_ENV}


@app.get("/healthz", summary="Healthz")
async def healthz() -> Dict[str, Any]:
    return {"ok": True}


@app.get("/v1/health", summary="V1 Health")
async def v1_health() -> Dict[str, Any]:
    return {"status": "ok", "env": APP_ENV}


# -------- Routers (mount without extra prefix; routers define their own) --------
# Alerts
try:
    from app import alerts as alerts_module

    app.include_router(alerts_module.router)
    log.info("Mounted router: app.alerts")
except Exception as e:
    log.warning("Router 'alerts' not mounted (app.alerts): %s", e)

# Detectors
try:
    from app.features import detectors as detectors_module

    app.include_router(detectors_module.router)
    log.info("Mounted router: app.features.detectors")
except Exception as e:
    log.warning("Router 'detectors' not mounted (app.features.detectors): %s", e)

# Image Queries (NEW)
try:
    from app.routers.image_queries import router as image_queries_router  # /v1/image-queries

    app.include_router(image_queries_router)
    log.info("Mounted router: app.routers.image_queries")
except Exception as e:
    log.warning("Router 'image-queries' not mounted (app.routers.image_queries): %s", e)


# -------- Global error handler (optional, nicer 500s) --------
@app.exception_handler(Exception)
async def _unhandled_ex(e: Exception, req: Request):
    log.exception("Unhandled error: %s", e)
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})
