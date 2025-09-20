# backend/api/app/alerts.py
from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import typing as T
import uuid
import logging

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

# ---------- Azure Blob (optional; mount even if missing) ----------
try:
    from azure.storage.blob import (
        BlobServiceClient,
        ContentSettings,
        generate_blob_sas,
        BlobSasPermissions,
    )
except Exception:  # pragma: no cover
    BlobServiceClient = None  # type: ignore
    ContentSettings = None  # type: ignore
    generate_blob_sas = None  # type: ignore
    BlobSasPermissions = None  # type: ignore

log = logging.getLogger("intellioptics.api")
router = APIRouter(prefix="/v1/alerts", tags=["alerts"])

# ---------- Env / Config ----------
CONN_STR = os.getenv("AZURE_STORAGE_CONNECTION_STRING", "").strip()
PRIVATE_CONTAINER = os.getenv("AZ_BLOB_CONTAINER", "images").strip()

PUBLIC_ENABLE = os.getenv("PUBLIC_SNAPSHOT_ENABLE", "true").lower() not in ("0", "false", "no")
PUBLIC_CONTAINER = os.getenv("PUBLIC_CONTAINER", "public").strip()
PUBLIC_PREFIX = os.getenv("PUBLIC_PREFIX", "web/alerts").strip()
PUBLIC_CACHE_CONTROL = os.getenv("PUBLIC_CACHE_CONTROL", "public, max-age=604800, immutable")

SAS_EXPIRE_MINUTES = int(os.getenv("SAS_EXPIRE_MINUTES", "1440"))
ARTIFACTS_DIR = pathlib.Path("backend/api/artifacts/ann")  # local annotated snapshots

# ---------- Optional: best-effort DB via psycopg (no import-time connect) ----------
try:
    import psycopg  # type: ignore
    from psycopg.rows import dict_row  # type: ignore

    DB_URL = os.getenv("DB_URL")
    _DB_OK = bool(DB_URL)
except Exception:
    DB_URL = None
    _DB_OK = False


def _db_exec(sql: str, params: tuple | None = None) -> None:
    if not _DB_OK:
        return
    try:
        with psycopg.connect(DB_URL, autocommit=True) as conn:  # type: ignore
            with conn.cursor() as cur:
                cur.execute(sql, params or ())
    except Exception:
        pass  # keep API healthy even if DB is down


def _db_query(sql: str, params: tuple | None = None) -> list[dict]:
    if not _DB_OK:
        return []
    try:
        with psycopg.connect(DB_URL) as conn:  # type: ignore
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(sql, params or ())
                return list(cur.fetchall())
    except Exception:
        return []

# ---------- Connection string helpers ----------
def _parse_conn_str(conn: str) -> dict[str, str]:
    """Parse 'key=value;key=value' into a dict (AccountName, AccountKey, EndpointSuffix, etc)."""
    parts = {}
    for seg in conn.split(";"):
        if not seg.strip() or "=" not in seg:
            continue
        k, v = seg.split("=", 1)
        parts[k.strip()] = v.strip()
    return parts

def _blob_service() -> BlobServiceClient:
    if not CONN_STR or not BlobServiceClient:
        raise HTTPException(status_code=500, detail="Blob service not configured (AZURE_STORAGE_CONNECTION_STRING).")
    return BlobServiceClient.from_connection_string(CONN_STR)

def _account_name_and_key() -> tuple[str, str]:
    parts = _parse_conn_str(CONN_STR)
    acct = parts.get("AccountName", "")
    key = parts.get("AccountKey", "")
    if not acct or not key:
        raise HTTPException(status_code=500, detail="Storage connection string missing AccountName/AccountKey.")
    return acct, key

def _today_parts(now: dt.datetime) -> tuple[int, int, int]:
    return now.year, now.month, now.day

# ---------- Blob operations ----------
def _upload_private_and_sas(
    bsc: BlobServiceClient, local_path: pathlib.Path, now: dt.datetime
) -> str:
    """Upload to private container images/alerts/YYYY/MM/DD/<file>.jpg and return a SAS URL."""
    y, m, d = _today_parts(now)
    blob_name = f"images/alerts/{y:04d}/{m:02d}/{d:02d}/{local_path.name}"
    cont = bsc.get_container_client(PRIVATE_CONTAINER)
    with local_path.open("rb") as f:
        cont.upload_blob(
            name=blob_name,
            data=f,
            overwrite=True,
            content_settings=ContentSettings(content_type="image/jpeg", cache_control="no-cache"),
        )

    account, key = _account_name_and_key()
    sas = generate_blob_sas(
        account_name=account,
        container_name=PRIVATE_CONTAINER,
        blob_name=blob_name,
        permission=BlobSasPermissions(read=True),
        expiry=dt.datetime.utcnow() + dt.timedelta(minutes=SAS_EXPIRE_MINUTES),
        account_key=key,  # REQUIRED for SAS
    )
    url = f"https://{account}.blob.core.windows.net/{PRIVATE_CONTAINER}/{blob_name}?{sas}"
    log.info(f"[alerts] private SAS generated: {url[:80]}...")
    return url

def _publish_public_copy(
    bsc: BlobServiceClient, local_path: pathlib.Path, now: dt.datetime
) -> str:
    """Publish a non-expiring public copy for web/email viewing. Returns public HTTPS URL."""
    y, m, d = _today_parts(now)
    stem = local_path.stem
    suffix = local_path.suffix.lower() or ".jpg"
    unique = uuid.uuid4().hex[:6]
    blob_name = f"{PUBLIC_PREFIX}/{y:04d}/{m:02d}/{d:02d}/{stem}-{unique}{suffix}"

    cont = bsc.get_container_client(PUBLIC_CONTAINER)
    with local_path.open("rb") as f:
        cont.upload_blob(
            name=blob_name,
            data=f,
            overwrite=True,
            content_settings=ContentSettings(
                content_type="image/jpeg",
                cache_control=PUBLIC_CACHE_CONTROL,
            ),
        )
    account, _ = _account_name_and_key()
    url = f"https://{account}.blob.core.windows.net/{PUBLIC_CONTAINER}/{blob_name}"
    log.info(f"[alerts] public URL published: {url}")
    return url

# ---------- Models ----------
class SimulateRequest(BaseModel):
    detector_id: str
    image_query_id: str
    answer: str = Field(..., description="YES/NO/COUNT/UNCLEAR")
    confidence: float | None = None
    count: float | None = None
    extra: dict | None = None
    query_text: str | None = Field(None, description='e.g., "Is there a person in the image?"')

class SimulateResponse(BaseModel):
    ok: bool
    detector_id: str
    image_query_id: str
    answer: str
    snapshot_url: str | None = None  # private SAS URL
    public_url: str | None = None    # public HTTPS URL
    query_text: str | None = None
    stored_event_id: str | None = None

class RecentEvent(BaseModel):
    id: str
    detector_id: str
    answer: str
    confidence: float | None = None
    count: float | None = None
    snapshot_url: str | None = None
    extra: dict | None = None
    created_at: str

# ---------- Routes ----------
@router.post("/simulate", response_model=SimulateResponse)
def simulate_alert(req: SimulateRequest):
    """
    Dev-only simulate: if a local annotated file exists (backend/api/artifacts/ann/<IQ>.jpg),
    upload to private container (+SAS). If enabled, also publish a copy to the public container.
    Record an alert_event if DB is available (best-effort).
    """
    now = dt.datetime.utcnow()
    ann_path = ARTIFACTS_DIR / f"{req.image_query_id}.jpg"

    snapshot_sas = None
    public_url = None

    if ann_path.exists() and BlobServiceClient and ContentSettings and generate_blob_sas:
        try:
            bsc = _blob_service()
            snapshot_sas = _upload_private_and_sas(bsc, ann_path, now)
            if PUBLIC_ENABLE:
                try:
                    public_url = _publish_public_copy(bsc, ann_path, now)
                except Exception as e:
                    log.warning(f"[alerts] public publish failed: {e}")
                    public_url = None
        except Exception as e:
            log.warning(f"[alerts] upload/SAS failed: {e}")
            snapshot_sas = None
            public_url = None
    else:
        log.warning("[alerts] annotated file missing or blob SDK not available; skipping uploads")

    # Store event (best-effort)
    event_id = str(uuid.uuid4())
    _db_exec(
        """
        INSERT INTO alert_events (id, detector_id, answer, confidence, count, snapshot_url, extra, created_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb, NOW())
        """,
        (
            event_id,
            req.detector_id,
            req.answer,
            req.confidence,
            req.count,
            snapshot_sas,
            json.dumps(req.extra or {}),
        ),
    )

    return SimulateResponse(
        ok=True,
        detector_id=req.detector_id,
        image_query_id=req.image_query_id,
        answer=req.answer,
        snapshot_url=snapshot_sas,
        public_url=public_url,
        query_text=req.query_text,
        stored_event_id=event_id if _DB_OK else None,
    )

@router.get("/events/recent", response_model=list[RecentEvent])
def recent_events(limit: int = Query(20, ge=1, le=200)):
    """Return most recent events if DB available; otherwise an empty list."""
    rows = _db_query(
        """
        SELECT id, detector_id, answer, confidence, count, snapshot_url, extra,
               to_char(created_at,'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
        FROM alert_events
        ORDER BY created_at DESC
        LIMIT %s
        """,
        (limit,),
    )
    return [RecentEvent(**r) for r in rows]

@router.post("/admin/migrate")
def admin_migrate():
    """Ensure alert_events has required columns; no-op if DB is unavailable."""
    ran: list[str] = []
    if not _DB_OK:
        return {"ok": False, "ran": ran}

    stmts = [
        "ALTER TABLE IF NOT EXISTS alert_events ADD COLUMN IF NOT EXISTS confidence DOUBLE PRECISION NULL",
        "ALTER TABLE IF NOT EXISTS alert_events ADD COLUMN IF NOT EXISTS count DOUBLE PRECISION NULL",
        "ALTER TABLE IF NOT EXISTS alert_events ADD COLUMN IF NOT EXISTS snapshot_url VARCHAR(2048) NULL",
        "ALTER TABLE IF NOT EXISTS alert_events ADD COLUMN IF NOT EXISTS extra JSONB NULL",
    ]
    for s in stmts:
        try:
            _db_exec(s)
            ran.append(s)
        except Exception:
            pass
    return {"ok": True, "ran": ran}
