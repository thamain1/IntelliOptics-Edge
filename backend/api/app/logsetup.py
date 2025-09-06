# app/logsetup.py
from __future__ import annotations

import json
import logging
import os
import sys
from datetime import datetime, timezone

# Fields Python logging sticks on every record (we won't duplicate these)
_STD_FIELDS = {
    "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
    "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
    "created", "msecs", "relativeCreated", "thread", "threadName", "processName",
    "process", "message"
}

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        # Base envelope
        out = {
            "ts": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "lvl": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }

        # Add exception info if present
        if record.exc_info:
            out["exc"] = self.formatException(record.exc_info)

        # Add any custom extras passed via logger.*(..., extra={...})
        for k, v in record.__dict__.items():
            if k not in _STD_FIELDS and not k.startswith("_"):
                try:
                    json.dumps(v)  # ensure JSON-serializable
                    out[k] = v
                except Exception:
                    out[k] = str(v)

        return json.dumps(out, separators=(",", ":"))

def setup_logging(level: str | None = None) -> None:
    level = (level or os.getenv("LOG_LEVEL") or "INFO").upper()

    root = logging.getLogger()
    root.handlers.clear()
    root.setLevel(level)

    h = logging.StreamHandler(sys.stdout)
    h.setFormatter(JsonFormatter())
    root.addHandler(h)

    # Quiet noisy libs unless debugging
    for name in (
        "azure", "azure.core.pipeline.policies.http_logging_policy",
        "azure.identity", "urllib3"
    ):
        logging.getLogger(name).setLevel(logging.WARNING)

    # Let uvicorn loggers bubble up to root so we get JSON too
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        lg = logging.getLogger(name)
        lg.handlers.clear()
        lg.propagate = True
