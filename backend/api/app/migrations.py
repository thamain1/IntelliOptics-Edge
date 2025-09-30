from __future__ import annotations

import logging
from typing import List

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from . import db
from .models import (ensure_alert_events_table,
                     ensure_edge_config_document_table)

logger = logging.getLogger("intellioptics.api")

DDL = [
    """
    CREATE TABLE IF NOT EXISTS image_queries (
        id TEXT PRIMARY KEY,
        detector_id TEXT,
        blob_url TEXT,
        status TEXT,
        label TEXT,
        confidence DOUBLE PRECISION,
        result_type TEXT,
        count DOUBLE PRECISION,
        extra JSONB,
        done_processing BOOLEAN DEFAULT FALSE,
        human_label TEXT,
        human_confidence DOUBLE PRECISION,
        human_notes TEXT,
        human_user TEXT,
        human_labeled_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,
    """ALTER TABLE image_queries ADD COLUMN IF NOT EXISTS count DOUBLE PRECISION;""",
    """ALTER TABLE image_queries ADD COLUMN IF NOT EXISTS extra JSONB;""",
    """ALTER TABLE image_queries ADD COLUMN IF NOT EXISTS human_label TEXT;""",
    """ALTER TABLE image_queries ADD COLUMN IF NOT EXISTS human_confidence DOUBLE PRECISION;""",
    """ALTER TABLE image_queries ADD COLUMN IF NOT EXISTS human_notes TEXT;""",
    """ALTER TABLE image_queries ADD COLUMN IF NOT EXISTS human_user TEXT;""",
    """ALTER TABLE image_queries ADD COLUMN IF NOT EXISTS human_labeled_at TIMESTAMPTZ;""",
    """CREATE INDEX IF NOT EXISTS ix_image_queries_detector_id ON image_queries(detector_id);""",
    """CREATE INDEX IF NOT EXISTS ix_image_queries_created_at ON image_queries(created_at);""",
    """
    CREATE TABLE IF NOT EXISTS alert_rules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        detector_id TEXT NOT NULL,
        detector_name TEXT,
        enabled BOOLEAN DEFAULT TRUE,
        condition JSONB NOT NULL,
        confirm_with_cloud BOOLEAN DEFAULT FALSE,
        notification JSONB NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,
    """ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS detector_name TEXT;""",
    """ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS enabled BOOLEAN DEFAULT TRUE;""",
    """ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS condition JSONB;""",
    """ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS confirm_with_cloud BOOLEAN DEFAULT FALSE;""",
    """ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS notification JSONB;""",
    """ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();""",
    """ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();""",
    """CREATE INDEX IF NOT EXISTS ix_alert_rules_detector_id ON alert_rules(detector_id);""",
    """CREATE INDEX IF NOT EXISTS ix_alert_rules_enabled ON alert_rules(enabled);""",
    """
    CREATE TABLE IF NOT EXISTS edge_config_documents (
        id SERIAL PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        global_config JSONB NOT NULL DEFAULT '{}'::jsonb,
        edge_inference_configs JSONB NOT NULL DEFAULT '{}'::jsonb,
        detectors JSONB NOT NULL DEFAULT '{}'::jsonb,
        streams JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,
    """ALTER TABLE edge_config_documents ADD COLUMN IF NOT EXISTS global_config JSONB DEFAULT '{}'::jsonb;""",
    """ALTER TABLE edge_config_documents ADD COLUMN IF NOT EXISTS edge_inference_configs JSONB DEFAULT '{}'::jsonb;""",
    """ALTER TABLE edge_config_documents ADD COLUMN IF NOT EXISTS detectors JSONB DEFAULT '{}'::jsonb;""",
    """ALTER TABLE edge_config_documents ADD COLUMN IF NOT EXISTS streams JSONB DEFAULT '{}'::jsonb;""",
    """ALTER TABLE edge_config_documents ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();""",
    """ALTER TABLE edge_config_documents ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();""",
]


def migrate() -> List[str]:
    engine = db.get_engine()
    applied: List[str] = []

    if engine.dialect.name.startswith("postgres"):
        try:
            with engine.begin() as conn:
                for stmt in DDL:
                    conn.execute(text(stmt))
                    applied.append(stmt.strip().splitlines()[0])
        except SQLAlchemyError:  # pragma: no cover - exercised via API tests
            logger.exception("[migrations] failed to apply legacy DDL")
            raise
    else:
        logger.info("[migrations] skipping legacy DDL for dialect %s", engine.dialect.name)

    created_alerts = ensure_alert_events_table(engine)
    applied.append("alert_events.create" if created_alerts else "alert_events.exists")

    created_configs = ensure_edge_config_document_table(engine)
    applied.append("edge_config_documents.create" if created_configs else "edge_config_documents.exists")
    return applied
