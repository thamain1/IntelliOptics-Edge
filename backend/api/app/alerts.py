# backend/api/app/alerts.py
from __future__ import annotations

import os
import uuid
import json
import datetime as dt
from pathlib import Path
from typing import Optional, Tuple

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.exc import SQLAlchemyError

# --- Logging ---------------------------------------------------------------
import logging

logger = logging.getLogger("intellioptics.api")
logger.setLevel(logging.INFO)

# --- Optional Azure SDK ----------------------------------------------------
_AZURE_OK = True
try:
    from azure.storage.blob import (
        BlobServiceClient,
        BlobSasPermissions,
        ContentSettings,
        generate_blob_sas,
    )
except Exception as e:  # pragma: no cover
    _AZURE_OK = False
    logger.warning("[alerts] Azure SDK import failed: %s", e)


router = APIRouter(prefix="/v1/alerts", tags=["alerts"])

from . import db, migrations
from .db import SessionLocal
from .models import AlertEvent, ensure_alert_events_table

# =============================================================================
# Models
# =============================================================================

class SimulateIn(BaseModel):
    detector_id: str
    image_query_id: str = Field(alias="image_query_id")
    answer: str
    confidence: Optional[float] = None
    query_text: Optional[str] = None
    extra: Optional[dict] = None


class SimulateOut(BaseModel):
    ok: bool
    detector_id: str
    image_query_id: str
    answer: str
    snapshot_url: Optional[str] = None
    public_url: Optional[str] = None
    query_text: Optional[str] = None
    stored_event_id: Optional[str] = None


# =============================================================================
# Helpers
# =============================================================================

def _env(name: str, default: Optional[str] = None) -> Optional[str]:
    v = os.getenv(name)
    return v if (v is not None and str(v).strip() != "") else default


def _parse_account(conn_str: str) -> Tuple[str, str]:
    # Expect "...;AccountName=...;AccountKey=...;..."
    parts = dict(x.split("=", 1) for x in conn_str.split(";") if "=" in x)
    acct = parts.get("AccountName")
    key = parts.get("AccountKey")
    if not acct or not key:
        raise RuntimeError("AZURE_STORAGE_CONNECTION_STRING missing AccountName or AccountKey")
    return acct, key


def _find_annotated_file(iq: str) -> Optional[Path]:
    """
    Try all known locations for annotated snapshots.
    Returns the first existing path.
    """
    candidates = [
        # Working-dir relative (backend/api) — what capture.ps1 writes
        Path("artifacts") / "ann" / f"{iq}.jpg",
        # Module-dir relative (backend/api/app) — some routers used this historically
        Path(__file__).parent / "artifacts" / "ann" / f"{iq}.jpg",
        # Add more candidates as needed:
        # Path("..") / "artifacts" / "ann" / f"{iq}.jpg",
    ]
    for p in candidates:
        if p.exists():
            return p
    return None


def _maybe_upload_to_blob(local_path: Path) -> Tuple[Optional[str], Optional[str]]:
    """
    Uploads local_path to private container; returns (snapshot_url, public_url).
    If blob config not present or SDK unavailable, returns (None, None).
    """
    if not _AZURE_OK:
        logger.warning("[alerts] Azure SDK not available")
        return (None, None)

    conn = _env("AZURE_STORAGE_CONNECTION_STRING")
    if not conn:
        logger.warning("[alerts] AZURE_STORAGE_CONNECTION_STRING missing; skipping upload")
        return (None, None)

    priv_container = _env("AZ_BLOB_CONTAINER", "images")
    pub_enabled = str(_env("PUBLIC_SNAPSHOT_ENABLE", "false")).lower() == "true"
    pub_container = _env("PUBLIC_CONTAINER", "public")
    pub_prefix = _env("PUBLIC_PREFIX", "web/alerts")
    sas_minutes = int(_env("SAS_EXPIRE_MINUTES", "1440") or "1440")

    # Allow pinning a storage API version to avoid future breaking headers
    api_ver = _env("AZURE_STORAGE_BLOB_API_VERSION")
    if api_ver:
        os.environ["AZURE_STORAGE_BLOB_API_VERSION"] = api_ver

    acct_name, acct_key = _parse_account(conn)
    svc = BlobServiceClient.from_connection_string(conn)

    now = dt.datetime.utcnow()
    dated_prefix = f"alerts/{now:%Y/%m/%d}"
    private_blob = f"{dated_prefix}/{local_path.name}"

    # Upload private
    bpriv = svc.get_blob_client(container=priv_container, blob=private_blob)
    with local_path.open("rb") as f:
        bpriv.upload_blob(
            f,
            overwrite=True,
            content_settings=ContentSettings(content_type="image/jpeg"),
        )
    # SAS
    sas = generate_blob_sas(
        account_name=acct_name,
        account_key=acct_key,
        container_name=priv_container,
        blob_name=private_blob,
        permission=BlobSasPermissions(read=True),
        expiry=now + dt.timedelta(minutes=sas_minutes),
    )
    snapshot_url = f"https://{acct_name}.blob.core.windows.net/{priv_container}/{private_blob}?{sas}"

    public_url = None
    if pub_enabled:
        uid = uuid.uuid4().hex[:8]
        public_blob = f"{pub_prefix}/{now:%Y/%m/%d}/{local_path.stem}-{uid}.jpg"
        bpub = svc.get_blob_client(container=pub_container, blob=public_blob)
        # Copy from private (server-side copy)
        src = f"https://{acct_name}.blob.core.windows.net/{priv_container}/{private_blob}"
        bpub.start_copy_from_url(src)
        public_url = f"https://{acct_name}.blob.core.windows.net/{pub_container}/{public_blob}"

    return (snapshot_url, public_url)


def _store_event_best_effort(payload: dict) -> Optional[str]:
    """
    Attempt to persist an alert event. Returns the event ID or None on failure.
    """

    try:
        ensure_alert_events_table(db.get_engine())
    except Exception as exc:  # pragma: no cover
        logger.warning("[alerts] unable to ensure alert_events table: %s", exc)

    try:
        session = SessionLocal()
    except Exception as exc:  # pragma: no cover
        logger.warning("[alerts] failed to obtain DB session: %s", exc)
        return None

    try:
        event = AlertEvent(
            detector_id=payload.get("detector_id"),
            image_query_id=payload.get("image_query_id"),
            answer=payload.get("answer"),
            payload=payload,
        )
        session.add(event)
        session.commit()
        session.refresh(event)
        return event.id
    except SQLAlchemyError as exc:
        session.rollback()
        logger.warning("[alerts] event store failed: %s", exc, exc_info=True)
    except Exception as exc:  # pragma: no cover
        session.rollback()
        logger.warning("[alerts] unexpected event store failure: %s", exc, exc_info=True)
    finally:
        session.close()

    return None


# =============================================================================
# Routes
# =============================================================================

@router.post("/simulate", response_model=SimulateOut)
def simulate_alert(body: SimulateIn) -> SimulateOut:
    """
    - Finds annotated snapshot for image_query_id.
    - Uploads to Azure Blob (private) + optional public publish.
    - Returns URLs and stores a lightweight event.
    """
    iq = body.image_query_id
    answer = body.answer.upper().strip()

    local = _find_annotated_file(iq)
    if not local:
        # Emit a clear log showing where we looked
        logger.warning(
            "[alerts] annotated file not found for IQ=%s; looked in: %s",
            iq,
            [
                str(Path("artifacts") / "ann" / f"{iq}.jpg"),
                str(Path(__file__).parent / "artifacts" / "ann" / f"{iq}.jpg"),
            ],
        )
        # Still return 200 with ok:true to preserve current behavior, but with null URLs
        stored_id = _store_event_best_effort(
            {
                "detector_id": body.detector_id,
                "image_query_id": iq,
                "answer": answer,
                "query_text": body.query_text,
                "note": "annotated-file-missing",
            }
        )
        return SimulateOut(
            ok=True,
            detector_id=body.detector_id,
            image_query_id=iq,
            answer=answer,
            snapshot_url=None,
            public_url=None,
            query_text=body.query_text,
            stored_event_id=stored_id,
        )

    # We have a file; attempt Azure upload if configured, else return null URLs
    snapshot_url: Optional[str] = None
    public_url: Optional[str] = None
    try:
        snapshot_url, public_url = _maybe_upload_to_blob(local)
        if snapshot_url:
            logger.info("[alerts] uploaded -> SAS OK for IQ=%s", iq)
        if public_url:
            logger.info("[alerts] published -> public OK for IQ=%s", iq)
        if not snapshot_url and not public_url:
            logger.warning("[alerts] blob not configured or SDK missing; URLs null for IQ=%s", iq)
    except Exception as e:  # pragma: no cover
        logger.warning("[alerts] upload/publish failed for IQ=%s: %s", iq, e, exc_info=True)
        snapshot_url = None
        public_url = None

    stored_id = _store_event_best_effort(
        {
            "detector_id": body.detector_id,
            "image_query_id": iq,
            "answer": answer,
            "confidence": body.confidence,
            "query_text": body.query_text,
            "extra": body.extra or {},
            "snapshot_url": snapshot_url,
            "public_url": public_url,
        }
    )

    return SimulateOut(
        ok=True,
        detector_id=body.detector_id,
        image_query_id=iq,
        answer=answer,
        snapshot_url=snapshot_url,
        public_url=public_url,
        query_text=body.query_text,
        stored_event_id=stored_id,
    )


@router.get("/events/recent")
def recent_events(limit: int = 10) -> dict:
    """Return the most recent stored alert events."""

    limit = max(1, min(limit, 100))

    try:
        ensure_alert_events_table(db.get_engine())
    except Exception as exc:  # pragma: no cover
        logger.warning("[alerts] unable to ensure alert_events table before query: %s", exc)

    try:
        with SessionLocal() as session:
            records = (
                session.query(AlertEvent)
                .order_by(AlertEvent.created_at.desc(), AlertEvent.id.desc())
                .limit(limit)
                .all()
            )
    except SQLAlchemyError as exc:
        logger.warning("[alerts] failed to load recent events: %s", exc, exc_info=True)
        raise HTTPException(status_code=503, detail="event storage unavailable")
    except Exception as exc:  # pragma: no cover
        logger.warning("[alerts] unexpected error loading events: %s", exc, exc_info=True)
        raise HTTPException(status_code=503, detail="event storage unavailable")

    return {
        "ok": True,
        "items": [record.to_dict() for record in records],
        "limit": limit,
    }


@router.post("/admin/migrate")
def admin_migrate() -> dict:
    """Run database migrations required for alert storage."""

    try:
        applied = migrations.migrate()
    except SQLAlchemyError as exc:
        logger.warning("[alerts] migration failure: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail="migration failed")
    except Exception as exc:  # pragma: no cover
        logger.warning("[alerts] unexpected migration failure: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail="migration failed")

    return {"ok": True, "migrations": applied}
