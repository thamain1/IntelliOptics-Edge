from .routers import labels
# backend/app/main.py
from __future__ import annotations

import os
import json
import asyncio
import logging
from contextlib import suppress
from time import perf_counter
from uuid import uuid4
from typing import Any, Dict, Optional

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Request
from fastapi.middleware.cors import CORSMiddleware

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
try:
    # If you have a dedicated log setup module, use it.
    from .logsetup import setup_logging  # type: ignore
    setup_logging()
except Exception:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))

logger = logging.getLogger("intellioptics.api")

# -----------------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------------
class Settings:
    # Base path for all API routes
    api_base_path: str = os.getenv("API_BASE_PATH", "/v1")
    # Service Bus queues (the worker listens on SB_QUEUE_LISTEN and sends results to SB_QUEUE_SEND)
    sb_image_queue: str = os.getenv("SB_QUEUE_LISTEN", "image-queries")
    sb_results_queue: str = os.getenv("SB_QUEUE_SEND", "inference-results")
    # Sync wait timeout for `wait=true` requests
    sync_wait_timeout_s: float = float(os.getenv("SYNC_WAIT_TIMEOUT_S", "25"))

settings = Settings()

# -----------------------------------------------------------------------------
# DB (SQLAlchemy)
# -----------------------------------------------------------------------------
# Prefer your project db.py, but fall back to a minimal engine/session if needed.
SessionLocal = None
engine = None
Base = None

try:
    from .db import SessionLocal as _SessionLocal, engine as _engine, Base as _Base  # type: ignore
    SessionLocal = _SessionLocal
    engine = _engine
    Base = _Base
except Exception as e:
    logger.warning("db_import_failed; falling back to runtime URL", extra={"err": type(e).__name__})
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker, declarative_base

    _dsn = (
        os.getenv("DATABASE_URL")
        or os.getenv("POSTGRES_DSN")
        or os.getenv("DB_URL")
        or os.getenv("SQLALCHEMY_DATABASE_URI")
    )
    if not _dsn:
        # Default to a safe-but-obviously-wrong DSN to make failures explicit
        _dsn = "postgresql+psycopg://user:pass@127.0.0.1:5432/postgres?sslmode=require"

    engine = create_engine(_dsn, pool_pre_ping=True, future=True)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
    Base = declarative_base()

# ImageQuery ORM model (use your project's model if present)
ImageQueryRow = None
try:
    from .models import ImageQueryRow as _ImageQueryRow  # type: ignore
    ImageQueryRow = _ImageQueryRow
except Exception:
    # Minimal fallback model mapping to your existing table columns
    from sqlalchemy import Column, Text, Float, Integer, DateTime
    from sqlalchemy.sql import func
    from sqlalchemy.dialects.postgresql import JSONB

    class ImageQueryRow(Base):  # type: ignore
        __tablename__ = "image_queries"
        id = Column(Text, primary_key=True)
        detector_id = Column(Text, nullable=False)
        blob_url = Column(Text)
        status = Column(Text)               # 'QUEUED' | 'DONE' | 'ERROR'
        label = Column(Text, nullable=True) # YES|NO|COUNT|UNCLEAR
        confidence = Column(Float, nullable=True)
        result_type = Column(Text, nullable=True)  # 'binary'|'count'|...
        count = Column(Integer, nullable=True)
        extra = Column(JSONB, nullable=True)
        received_ts = Column(DateTime(timezone=True), server_default=func.now())

# -----------------------------------------------------------------------------
# Auth dependency
# -----------------------------------------------------------------------------
async def _noauth():
    return True

require_auth = _noauth
try:
    from .auth import require_auth as _require_auth  # type: ignore
    require_auth = _require_auth
except Exception:
    logger.info("auth_module_not_found; using no-op auth dependency")

# -----------------------------------------------------------------------------
# Storage (Azure Blob) & Queue (Service Bus)
# -----------------------------------------------------------------------------
BlobRef = None
upload_starlette_file = None
enqueue_image_query = None

try:
    # Preferred: your project storage helper
    from .storage.blob import BlobRef as _BlobRef, upload_starlette_file as _upload  # type: ignore
    BlobRef = _BlobRef
    upload_starlette_file = _upload
except Exception as e:
    logger.warning("blob_helper_import_failed", extra={"err": type(e).__name__})

try:
    from .queues.servicebus import enqueue_image_query as _enqueue_image_query  # type: ignore
    enqueue_image_query = _enqueue_image_query
except Exception as e:
    logger.warning("servicebus_helper_import_failed", extra={"err": type(e).__name__})

# Fallbacks for storage/queue to keep the API usable in dev
async def _fallback_upload_starlette_file(container_client: Any, file: UploadFile, prefix: str) -> Any:
    # Dev-only: save to /tmp and return a fake blob ref
    path = f"/tmp/{prefix}-{uuid4().hex}-{(getattr(file,'filename','') or 'upload')}"
    content = await file.read()
    with open(path, "wb") as f:
        f.write(content)
    class _Ref:
        def __init__(self, url, container, name, content_type, size):
            self.url = url; self.container = container; self.name = name
            self.content_type = content_type; self.size = size
    return _Ref(url=f"file://{path}", container="local", name=os.path.basename(path),
                content_type=getattr(file, "content_type", None), size=len(content))

async def _fallback_enqueue_image_query(payload: Dict[str, Any]) -> None:
    logger.info("DEV: would enqueue image query", extra={"payload": payload})

if upload_starlette_file is None:
    upload_starlette_file = _fallback_upload_starlette_file
if enqueue_image_query is None:
    enqueue_image_query = _fallback_enqueue_image_query

# Dummy container client placeholder for the upload helper signature
_container_client: Any = object()

# -----------------------------------------------------------------------------
# FastAPI app
# -----------------------------------------------------------------------------
app = FastAPI(title="IntelliOptics API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include additional feature routers if they exist (e.g., detectors, alerts)
with suppress(Exception):
    from .features.detectors import router as detectors_router  # type: ignore
    app.include_router(detectors_router, prefix=settings.api_base_path)
with suppress(Exception):
    from .features.alerts import router as alerts_router  # type: ignore
    app.include_router(alerts_router, prefix=settings.api_base_path)

# -----------------------------------------------------------------------------
# Health
# -----------------------------------------------------------------------------
@app.get(f"{settings.api_base_path}/health")
async def health() -> Dict[str, str]:
    return {"status": "ok"}

# -----------------------------------------------------------------------------
# Image Queries (SDK contract)
# -----------------------------------------------------------------------------
@app.post(
    f"{settings.api_base_path}/image-queries",
    dependencies=[Depends(require_auth)],
)
async def submit_image_query(
    request: Request,
    detector_id: str = Form(...),
    image: UploadFile = File(...),
    wait: bool = Form(False),
) -> Dict[str, Any]:
    """
    Accept an image for a detector, enqueue to the worker, and (optionally) wait
    for the result. Returns fields the SDK expects:

      { id, answer, confidence, latency_ms, result_type, count, extra }
    """
    t0 = perf_counter()
    image_query_id = uuid4().hex

    # --- Read upload (best-effort robust) ---
    try:
        content = await image.read()
    except Exception as e:
        logger.warning("uploadfile_read_failed", extra={
            "event": "uploadfile_read_failed",
            "image_query_id": image_query_id,
            "err": type(e).__name__,
        }, exc_info=True)
        content = b""
    finally:
        with suppress(Exception):
            await image.seek(0)
        with suppress(Exception):
            image.file.seek(0)

    safe_upload_name = (getattr(image, "filename", "") or "").split("/")[-1].split("\\")[-1]
    logger.info("image_query_received", extra={
        "event": "image_query_received",
        "image_query_id": image_query_id,
        "detector_id": detector_id,
        "upload_name": safe_upload_name,
        "content_type": getattr(image, "content_type", None),
        "size": len(content),
        "client_ip": getattr(getattr(request, "client", None), "host", None),
    })

    # --- Upload to blob (or local fallback) ---
    try:
        blobref = await upload_starlette_file(_container_client, image, prefix="image-queries")
        logger.info("blob_uploaded", extra={
            "event": "blob_uploaded",
            "image_query_id": image_query_id,
            "container": getattr(blobref, "container", None),
            "blob_name": getattr(blobref, "name", None),
            "content_type": getattr(blobref, "content_type", None),
            "size": getattr(blobref, "size", None),
        })
    except Exception as e:
        logger.exception("blob_upload_failed", extra={
            "event": "blob_upload_failed",
            "image_query_id": image_query_id,
            "err": type(e).__name__,
        })
        raise HTTPException(status_code=502, detail=f"blob upload failed: {type(e).__name__}")

    # --- Insert initial DB row (status=QUEUED) ---
    try:
        with SessionLocal() as db:
            row = ImageQueryRow(
                id=image_query_id,
                detector_id=detector_id,
                blob_url=getattr(blobref, "url", None),
                status="QUEUED",
                label=None,
                confidence=None,
                result_type=None,
                count=None,
                extra=None,
            )
            db.add(row)
            db.commit()
            logger.info("db_row_inserted", extra={"event": "db_row_inserted", "image_query_id": image_query_id})
    except Exception as e:
        logger.warning("db_insert_failed", extra={
            "event": "db_insert_failed",
            "image_query_id": image_query_id,
            "err": type(e).__name__,
        }, exc_info=True)

    # --- Enqueue for worker ---
    payload = {
        "image_query_id": image_query_id,
        "detector_id": detector_id,
        "blob_url": getattr(blobref, "url", None),
        "blob_container": getattr(blobref, "container", None),
        "blob_name": getattr(blobref, "name", None),
        "content_type": getattr(blobref, "content_type", None),
        "size": getattr(blobref, "size", None),
    }
    try:
        await enqueue_image_query(payload)
        logger.info("sb_sent", extra={
            "event": "sb_sent",
            "image_query_id": image_query_id,
            "queue": settings.sb_image_queue,
        })
    except Exception as e:
        logger.exception("sb_send_failed", extra={
            "event": "sb_send_failed",
            "image_query_id": image_query_id,
            "err": type(e).__name__,
        })
        raise HTTPException(status_code=502, detail="failed to enqueue image query")

    # --- If caller doesn't want to wait, return quickly ---
    if not wait:
        return {"image_query_id": image_query_id, "status": "QUEUED"}

    # --- Poll DB for DONE/ERROR up to timeout ---
    deadline = perf_counter() + settings.sync_wait_timeout_s
    row: Optional[ImageQueryRow] = None

    while perf_counter() < deadline:
        try:
            with SessionLocal() as db:
                row = db.get(ImageQueryRow, image_query_id)  # type: ignore
                if row and row.status in ("DONE", "ERROR"):
                    break
        except Exception:
            # transient DB issue — keep waiting
            pass
        await asyncio.sleep(0.5)

    latency_ms = int((perf_counter() - t0) * 1000)

    if not row or row.status != "DONE":
        # Timed out or still processing — return SDK shape with a hint
        return {
            "id": image_query_id,
            "answer": None,
            "confidence": None,
            "latency_ms": latency_ms,
            "result_type": None,
            "count": None,
            "extra": {"wait_timed_out": True},
        }

    # --- Normalize to SDK contract ---
    return {
        "id": row.id,
        "answer": row.label,
        "confidence": row.confidence,
        "latency_ms": latency_ms,
        "result_type": row.result_type,
        "count": row.count,
        "extra": row.extra,
        # "model_version": row.model_version  # add if your worker writes it
    }


# -----------------------------------------------------------------------------
# Root (optional)
# -----------------------------------------------------------------------------
@app.get("/")
async def root() -> Dict[str, str]:
    return {"hello": "intellioptics"}

app.include_router(labels.router)

