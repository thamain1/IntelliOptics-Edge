from sqlalchemy import text
from .db import engine

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
]

def migrate():
    with engine.begin() as conn:
        for stmt in DDL:
            conn.execute(text(stmt))
