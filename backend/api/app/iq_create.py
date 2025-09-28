# backend/api/app/iq_create.py
from __future__ import annotations

import json
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from sqlalchemy import text

from .db import engine
from .iq_read import _fetch_one

router = APIRouter()


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _save_temp_image(iq_id: str, up: UploadFile) -> str:
    suffix = Path(up.filename).suffix or ".jpg"
    out_path = Path(tempfile.gettempdir()) / f"iq-{iq_id}{suffix}"
    with out_path.open("wb") as f:
        f.write(up.file.read())
    return out_path.resolve().as_uri()


def _build_extra_payload(
    *,
    metadata: Optional[str],
    confidence_threshold: Optional[float],
    patience_time: Optional[float],
    human_review: Optional[str],
) -> Dict[str, Any]:
    extra: Dict[str, Any] = {}
    if metadata:
        try:
            extra["metadata"] = json.loads(metadata)
        except json.JSONDecodeError as exc:  # pragma: no cover - defensive
            raise HTTPException(status_code=400, detail=f"metadata must be valid JSON: {exc}") from exc
    if confidence_threshold is not None:
        extra["confidence_threshold"] = confidence_threshold
    if patience_time is not None:
        extra["patience_time"] = patience_time
    if human_review is not None:
        extra["human_review"] = human_review
    return extra


@router.post("/v1/image-queries")
async def create_image_query(
    detector_id: str = Form(...),
    image: UploadFile = File(...),
    metadata: Optional[str] = Form(None),
    confidence_threshold: Optional[float] = Form(None),
    patience_time: Optional[float] = Form(None),
    human_review: Optional[str] = Form(None),
    want_async: Optional[bool] = Form(False),
    wait: Optional[float] = Form(None),
    image_query_id: Optional[str] = Form(None),
):
    iq_id = image_query_id or uuid.uuid4().hex
    try:
        blob_url = _save_temp_image(iq_id, image)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"failed to save image: {e}")

    extra = _build_extra_payload(
        metadata=metadata,
        confidence_threshold=confidence_threshold,
        patience_time=patience_time,
        human_review=human_review,
    )
    if want_async:
        extra["want_async"] = True
    if wait is not None:
        extra["wait"] = wait

    try:
        with engine.begin() as conn:
            conn.execute(
                text(
                    """
                    INSERT INTO image_queries (
                        id, detector_id, blob_url, status,
                        received_ts, result_type,
                        count, confidence, done_processing, extra
                    )
                    VALUES (
                        :id, :detector_id, :blob_url, 'QUEUED',
                        NOW(), 'BINARY',
                        0, 0.0, false, :extra
                    )
                """
                ),
                {
                    "id": iq_id,
                    "detector_id": detector_id,
                    "blob_url": blob_url,
                    "extra": extra or None,
                },
            )
    except Exception as e:  # pragma: no cover - defensive
        print({"lvl": "ERROR", "msg": "iq_insert_failed", "error": str(e)})
        raise HTTPException(status_code=500, detail="failed to write DB row") from e

    doc = _fetch_one(iq_id)
    if not doc:
        raise HTTPException(status_code=500, detail="failed to load created image query")
    return doc
