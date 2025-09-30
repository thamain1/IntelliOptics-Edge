# backend/api/app/iq_read.py
from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import text

from .db import engine

router = APIRouter()


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _row_to_dict(row: Any) -> Dict[str, Any]:
    image_uri = row.blob_url

    cnt = row.count or 0
    answer = "YES" if cnt > 0 else "NO"

    status = row.status or "QUEUED"
    db_done = bool(row.done_processing) if row.done_processing is not None else False
    # <- key change: derive done if status is DONE
    done = db_done or (status == "DONE")

    def _ts(x):
        if not x:
            return None
        # keep ISO 8601; DB may already be tz-aware UTC
        try:
            return x.isoformat().replace("+00:00", "+00:00")
        except Exception:
            return str(x)

    return {
        "id": row.id,
        "detector_id": row.detector_id,
        "image_uri": image_uri,
        "status": status,
        "confidence": float(row.confidence or 0.0),
        "result_type": row.result_type,
        "count": int(cnt),
        "extra": row.extra,
        "received_ts": _ts(row.received_ts),
        "processing_started_ts": _ts(row.processing_started_ts),
        "updated_ts": _ts(row.updated_ts),
        "done_processing": done,
        "answer": answer,
    }


def _fetch_one(iq_id: str) -> Optional[Dict[str, Any]]:
    sql = text(
        """
        SELECT
            id, detector_id,
            blob_url,
            status, confidence, result_type, count, extra,
            received_ts, processing_started_ts, updated_ts,
            COALESCE(done_processing, false) AS done_processing
        FROM image_queries
        WHERE id = :id
        LIMIT 1
    """
    )
    with engine.connect() as conn:
        res = conn.execute(sql, {"id": iq_id})
        row = res.mappings().first()
        if not row:
            return None
        return _row_to_dict(row)


@router.get("/v1/image-queries/{iq_id}")
def get_image_query(iq_id: str):
    doc = _fetch_one(iq_id)
    if not doc:
        raise HTTPException(status_code=404, detail="not found")
    return doc


@router.get("/v1/image-queries/{iq_id}/wait")
async def wait_image_query(
    iq_id: str,
    timeout_ms: int = Query(8000, ge=0, le=60000),
    poll_ms: int = Query(250, ge=10, le=2000),
):
    deadline = datetime.now(timezone.utc).timestamp() + (timeout_ms / 1000.0)
    while True:
        doc = _fetch_one(iq_id)
        if not doc:
            raise HTTPException(status_code=404, detail="not found")
        if doc["status"] in ("DONE", "FAILED") or doc.get("done_processing"):
            return doc
        if datetime.now(timezone.utc).timestamp() >= deadline:
            return {"status": "PROCESSING", "image_query_id": iq_id}
        await asyncio.sleep(poll_ms / 1000.0)
