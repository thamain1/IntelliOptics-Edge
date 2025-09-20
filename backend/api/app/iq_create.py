# backend/api/app/iq_create.py
from __future__ import annotations

import uuid
import tempfile
from pathlib import Path
from datetime import datetime, timezone

from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from sqlalchemy import text

from .main import engine

router = APIRouter()

def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def _save_temp_image(iq_id: str, up: UploadFile) -> str:
    suffix = Path(up.filename).suffix or ".jpg"
    out_path = Path(tempfile.gettempdir()) / f"iq-{iq_id}{suffix}"
    with out_path.open("wb") as f:
        f.write(up.file.read())
    return out_path.resolve().as_uri()

@router.post("/v1/image-queries")
async def create_image_query(
    detector_id: str = Form(...),
    image: UploadFile = File(...)
):
    iq_id = uuid.uuid4().hex
    try:
        blob_url = _save_temp_image(iq_id, image)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"failed to save image: {e}")

    # Insert safe minimum + likely NOT NULLs; DO NOT touch 'answer' (column absent)
    try:
        with engine.begin() as conn:
            conn.execute(
                text("""
                    INSERT INTO image_queries (
                        id, detector_id, blob_url, status,
                        received_ts, result_type,
                        count, confidence, done_processing
                    )
                    VALUES (
                        :id, :detector_id, :blob_url, 'QUEUED',
                        NOW(), 'BINARY',
                        0, 0.0, false
                    )
                """),
                {"id": iq_id, "detector_id": detector_id, "blob_url": blob_url},
            )
    except Exception as e:
        # Log server-side for diagnosis, keep client message stable
        print({"lvl": "ERROR", "msg": "iq_insert_failed", "error": str(e)})
        raise HTTPException(status_code=500, detail="failed to write DB row")

    # Keep response shape compatible with your submit script
    return {
        "image_query_id": iq_id,
        "status": "QUEUED",
        "image_uri": blob_url,
    }
