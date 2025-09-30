# app/features/detectors.py
from __future__ import annotations

import uuid
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.auth import require_auth
from app.db import get_db
from app.models import \
    Detector  # SQLAlchemy model: id (UUID), public_id, name, mode, query, confidence_threshold, status, created_at

router = APIRouter(prefix="/v1/detectors", tags=["detectors"])


# ========= Pydantic Schemas =========


class DetectorCreate(BaseModel):
    name: str
    # optional; default 'binary' if omitted
    mode: Optional[str] = Field(default=None, description="binary|count|custom (optional)")
    query: str
    confidence_threshold: float = Field(0.75, ge=0.0, le=1.0)


class DetectorOut(BaseModel):
    id: str  # public det_* id
    name: str
    mode: Optional[str] = None
    query: str
    confidence_threshold: float
    status: Optional[str] = "active"


# ========= Helpers =========


def _normalize_create_payload(raw: Dict[str, Any]) -> DetectorCreate:
    """
    Accept legacy keys and normalize to SDK fields:
      - query_text -> query
      - threshold  -> confidence_threshold
    """
    payload = dict(raw)
    if "query" not in payload and "query_text" in payload:
        payload["query"] = payload.pop("query_text")
    if "confidence_threshold" not in payload and "threshold" in payload:
        payload["confidence_threshold"] = payload.pop("threshold")
    # Defaults/validation via Pydantic
    return DetectorCreate(**payload)


def _row_to_out(det: Detector) -> Dict[str, Any]:
    return {
        "id": det.public_id,  # SDK-facing id
        "name": det.name,
        "mode": getattr(det, "mode", None),
        "query": det.query,
        "confidence_threshold": float(det.confidence_threshold),
        "status": getattr(det, "status", "active"),
    }


def _get_by_any_id(db: Session, detector_id: str) -> Optional[Detector]:
    q = db.query(Detector)
    if detector_id.startswith("det_"):
        return q.filter(Detector.public_id == detector_id).first()
    # fallback to UUID for back-compat
    try:
        return q.filter(Detector.id == uuid.UUID(detector_id)).first()
    except Exception:
        return None


# ========= Routes =========


@router.get("", response_model=List[DetectorOut], dependencies=[Depends(require_auth)])
def list_detectors(db: Session = Depends(get_db)):
    """
    List detectors (SDK-aligned fields). Ordered by created_at desc when available.
    """
    q = db.query(Detector)
    # If your model has created_at, prefer ordering by it
    try:
        rows = q.order_by(getattr(Detector, "created_at").desc()).all()
    except Exception:
        rows = q.all()
    return [_row_to_out(r) for r in rows]


@router.get("/{detector_id}", response_model=DetectorOut, dependencies=[Depends(require_auth)])
def get_detector(detector_id: str, db: Session = Depends(get_db)):
    """
    Get a detector by public det_* id (preferred) or legacy UUID (back-compat).
    """
    det = _get_by_any_id(db, detector_id)
    if not det:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Detector not found")
    return _row_to_out(det)


@router.post("", response_model=DetectorOut, dependencies=[Depends(require_auth)])
def create_detector(raw: Dict[str, Any] = Body(...), db: Session = Depends(get_db)):
    """
    Create a detector using SDK-aligned fields. No internal SDK dependency.
    Ensures the response exposes a public det_* id.
    """
    body = _normalize_create_payload(raw)
    public_id = "det_" + uuid.uuid4().hex  # 32 hex chars, matches det_<hex> format

    det = Detector(
        public_id=public_id,
        name=body.name,
        mode=body.mode or "binary",
        query=body.query,
        confidence_threshold=body.confidence_threshold,
        status="active",
    )

    try:
        db.add(det)
        db.commit()
        db.refresh(det)
    except Exception as e:
        db.rollback()
        # If unique index exists on public_id, collisions are astronomically unlikely,
        # but we still present a clean 502 on any DB error.
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=f"create_detector failed: {type(e).__name__}"
        )

    return _row_to_out(det)
