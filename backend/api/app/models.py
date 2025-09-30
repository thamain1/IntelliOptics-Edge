from __future__ import annotations

import datetime as dt
import uuid
from typing import Any, Dict

from sqlalchemy import (JSON, TIMESTAMP, Boolean, Float, Integer, String, func,
                        inspect)
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Mapped, declarative_base, mapped_column

Base = declarative_base()


class ImageQueryRow(Base):
    __tablename__ = "image_queries"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    detector_id: Mapped[str] = mapped_column(String)
    blob_url: Mapped[str] = mapped_column(String)

    status: Mapped[str] = mapped_column(String, default="SUBMITTED")
    label: Mapped[str | None] = mapped_column(String, nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    result_type: Mapped[str | None] = mapped_column(String, nullable=True)
    count: Mapped[float | None] = mapped_column(Float, nullable=True)

    # portable JSON (works on SQLite and Postgres)
    extra = mapped_column(JSON, nullable=True)

    done_processing: Mapped[bool] = mapped_column(Boolean, default=False)

    # human review fields
    human_label: Mapped[str | None] = mapped_column(String, nullable=True)
    human_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    human_notes: Mapped[str | None] = mapped_column(String, nullable=True)
    human_user: Mapped[str | None] = mapped_column(String, nullable=True)
    human_labeled_at = mapped_column(TIMESTAMP(timezone=True), nullable=True)

    created_at = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )


class AlertRuleRow(Base):
    __tablename__ = "alert_rules"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String)
    detector_id: Mapped[str] = mapped_column(String)
    detector_name: Mapped[str | None] = mapped_column(String, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    condition: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    confirm_with_cloud: Mapped[bool] = mapped_column(Boolean, default=False)
    notification: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    created_at = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )


class AlertEvent(Base):
    __tablename__ = "alert_events"

    id: Mapped[str] = mapped_column(
        String,
        primary_key=True,
        default=lambda: str(uuid.uuid4()),
    )
    detector_id: Mapped[str | None] = mapped_column(String, nullable=True)
    image_query_id: Mapped[str | None] = mapped_column(String, nullable=True)
    answer: Mapped[str | None] = mapped_column(String, nullable=True)
    payload: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    created_at = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        default=lambda: dt.datetime.now(dt.timezone.utc),
        nullable=False,
        index=True,
    )

    def to_dict(self) -> Dict[str, Any]:
        created = self.created_at.isoformat() if self.created_at else None
        return {
            "id": self.id,
            "detector_id": self.detector_id,
            "image_query_id": self.image_query_id,
            "answer": self.answer,
            "created_at": created,
            "payload": self.payload,
        }


def ensure_alert_events_table(engine: Engine) -> bool:
    """Create the alert_events table if it does not exist."""
    inspector = inspect(engine)
    existing = inspector.has_table(AlertEvent.__tablename__)
    AlertEvent.__table__.create(bind=engine, checkfirst=True)
    return not existing


class EdgeConfigDocument(Base):
    __tablename__ = "edge_config_documents"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    global_config: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    edge_inference_configs: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    detectors: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    streams: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)
    created_at = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


def ensure_edge_config_document_table(engine: Engine) -> bool:
    """Ensure the edge_config_documents table exists."""

    inspector = inspect(engine)
    existing = inspector.has_table(EdgeConfigDocument.__tablename__)
    EdgeConfigDocument.__table__.create(bind=engine, checkfirst=True)
    return not existing
