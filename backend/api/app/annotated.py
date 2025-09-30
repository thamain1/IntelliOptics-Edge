# backend/api/app/annotated.py
from __future__ import annotations

import os
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

router = APIRouter()


def _ann_dir() -> Path:
    """
    Resolve the annotations directory.
    Priority:
      1) IO_ANN_DIR env var (what the worker uses)
      2) <repo_root>/artifacts/ann  (repo_root = .../IntelliOptics-Edge)
    """
    env_dir = os.environ.get("IO_ANN_DIR")
    if env_dir:
        return Path(env_dir)

    # This file lives at: backend/api/app/annotated.py
    # repo_root = .../backend/api/app/../../.. (3 parents up)
    here = Path(__file__).resolve()
    repo_root = here.parents[3]
    return repo_root / "artifacts" / "ann"


@router.get("/v1/image-queries/{iq_id}/annotated", response_class=FileResponse)
def get_annotated_snapshot(
    iq_id: str,
    fmt: str = Query("jpg", pattern="^(jpg|jpeg|png)$", description="Image format to serve"),
):
    """
    Serve the annotated snapshot produced by the worker for a given image_query_id.
    Returns 404 if the file doesn't exist yet.
    """
    ext = "jpg" if fmt.lower() in ("jpg", "jpeg") else "png"
    ann_dir = _ann_dir()

    # Primary candidate
    candidate = ann_dir / f"{iq_id}.{ext}"

    # Fallback to .jpg if requested format missing (worker defaults to jpg)
    if not candidate.exists():
        jpg_fallback = ann_dir / f"{iq_id}.jpg"
        if candidate.suffix.lower() != ".jpg" and jpg_fallback.exists():
            candidate = jpg_fallback
        else:
            raise HTTPException(status_code=404, detail="Annotated snapshot not found")

    media = "image/jpeg" if candidate.suffix.lower() in (".jpg", ".jpeg") else "image/png"
    # FileResponse streams efficiently and sets Content-Length/Type; add filename for nicer downloads
    return FileResponse(path=str(candidate), media_type=media, filename=candidate.name)
