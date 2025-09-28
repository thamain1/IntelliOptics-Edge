"""Review-focused API endpoints for human-in-the-loop labeling."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Iterable, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from .config import settings
from .db import SessionLocal
from .models import ImageQueryRow

try:  # pragma: no cover - optional dependency during local development
    from .queues.servicebus import enqueue_feedback
except Exception:  # pragma: no cover - Service Bus is optional for HITL flows
    enqueue_feedback = None  # type: ignore[assignment]


log = logging.getLogger("intellioptics.api.review")


def _db_session() -> Iterable[Session]:
    """FastAPI dependency that yields a SQLAlchemy session."""

    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _row_to_dict(row: ImageQueryRow) -> dict:
    """Serialize a DB row into the shape expected by the review UI."""

    def _ts(value: Optional[datetime]) -> Optional[str]:
        if not value:
            return None
        try:
            return value.astimezone(timezone.utc).isoformat()
        except Exception:  # pragma: no cover - defensive fallback for naive datetimes
            return value.isoformat() if hasattr(value, "isoformat") else str(value)

    return {
        "id": row.id,
        "detector_id": row.detector_id,
        "image_uri": row.blob_url,
        "status": row.status,
        "model_label": row.label,
        "model_confidence": row.confidence,
        "result_type": row.result_type,
        "count": row.count,
        "extra": row.extra,
        "received_ts": _ts(row.created_at),
        "updated_ts": _ts(row.updated_at),
        "human_label": row.human_label,
        "human_confidence": row.human_confidence,
        "human_notes": row.human_notes,
        "human_user": row.human_user,
        "human_labeled_at": _ts(row.human_labeled_at),
    }


class ReviewQueueResponse(BaseModel):
    items: List[dict]
    total: int
    limit: int
    offset: int


class HumanLabelRequest(BaseModel):
    label: str = Field(..., pattern=r"^(YES|NO|UNCLEAR)$")
    confidence: Optional[float] = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="Optional reviewer confidence in the provided label.",
    )
    notes: Optional[str] = Field(default=None, max_length=2000)
    user: Optional[str] = Field(
        default=None,
        description="Identifier for the reviewer submitting feedback.",
    )
    count: Optional[int] = Field(
        default=None,
        ge=0,
        description="Optional object count supplied by the reviewer.",
    )


router = APIRouter(prefix=settings.api_base_path, tags=["review"])


@router.get("/review/image-queries", response_model=ReviewQueueResponse)
def list_review_queue(
    *,
    db: Session = Depends(_db_session),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    detector_id: Optional[str] = Query(None, description="Filter by detector identifier"),
    pending_only: bool = Query(
        True,
        description="Return only image queries that still require human labels.",
    ),
) -> ReviewQueueResponse:
    """Return a paginated list of image queries for human review."""

    stmt = select(ImageQueryRow).order_by(ImageQueryRow.created_at.desc())
    count_stmt = select(func.count()).select_from(ImageQueryRow)

    if detector_id:
        stmt = stmt.where(ImageQueryRow.detector_id == detector_id)
        count_stmt = count_stmt.where(ImageQueryRow.detector_id == detector_id)

    if pending_only:
        stmt = stmt.where(ImageQueryRow.human_label.is_(None))
        count_stmt = count_stmt.where(ImageQueryRow.human_label.is_(None))

    total = db.execute(count_stmt).scalar_one()
    rows = db.execute(stmt.offset(offset).limit(limit)).scalars().all()

    return ReviewQueueResponse(
        items=[_row_to_dict(row) for row in rows],
        total=int(total),
        limit=limit,
        offset=offset,
    )


@router.get("/review/image-queries/{image_query_id}")
def get_review_item(
    image_query_id: str,
    db: Session = Depends(_db_session),
):
    """Fetch a single image query with all human-review metadata."""

    row = db.get(ImageQueryRow, image_query_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="not found")
    return _row_to_dict(row)


@router.post("/review/image-queries/{image_query_id}/label")
async def submit_human_label(
    image_query_id: str,
    payload: HumanLabelRequest,
    db: Session = Depends(_db_session),
):
    """Persist a human label and forward it to downstream feedback pipelines."""

    row = db.get(ImageQueryRow, image_query_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="not found")

    row.human_label = payload.label
    row.human_confidence = payload.confidence
    row.human_notes = payload.notes
    row.human_user = payload.user
    row.human_labeled_at = datetime.now(timezone.utc)

    if payload.count is not None:
        row.count = payload.count

    try:
        db.add(row)
        db.commit()
    except SQLAlchemyError as exc:  # pragma: no cover - FastAPI surface handles runtime
        db.rollback()
        log.exception("failed to persist human label", extra={"image_query_id": image_query_id})
        raise HTTPException(status_code=500, detail="failed to store human label") from exc

    if enqueue_feedback is not None:
        try:
            await enqueue_feedback(
                {
                    "image_query_id": image_query_id,
                    "label": payload.label,
                    "confidence": payload.confidence,
                    "count": payload.count,
                    "notes": payload.notes,
                    "user": payload.user,
                }
            )
        except Exception:  # pragma: no cover - feedback queuing is best-effort
            log.exception(
                "failed to enqueue human feedback", extra={"image_query_id": image_query_id}
            )

    return _row_to_dict(row)
