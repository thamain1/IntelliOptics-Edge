from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy.pool import StaticPool

from .config import settings


logger = logging.getLogger("intellioptics.db")
Base = declarative_base()
SessionLocal = sessionmaker(autoflush=False, autocommit=False, future=True)

_engine: Engine | None = None


def _default_sqlite_path() -> Path:
    data_dir = Path(__file__).resolve().parent.parent / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir / "events.db"


def _resolve_db_url(override: Optional[str] = None) -> str:
    if override:
        url = override
    else:
        url = (
            os.getenv("DATABASE_URL")
            or os.getenv("POSTGRES_DSN")
            or settings.pg_dsn
        )

    if not url:
        url = f"sqlite:///{_default_sqlite_path()}"

    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)

    return url


def _engine_kwargs(url: str) -> dict:
    kwargs: dict = {"future": True}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
        if url in {"sqlite://", "sqlite:///:memory:"}:
            kwargs["poolclass"] = StaticPool
    else:
        kwargs["pool_pre_ping"] = True
    return kwargs


def configure_engine(url: Optional[str] = None) -> Engine:
    global _engine

    resolved = _resolve_db_url(url)
    if _engine is not None:
        _engine.dispose()

    try:
        _engine = create_engine(resolved, **_engine_kwargs(resolved))
    except ModuleNotFoundError as exc:
        if exc.name in {"psycopg", "psycopg2"}:
            fallback = f"sqlite:///{_default_sqlite_path()}"
            logger.warning(
                "[db] psycopg driver missing; falling back to SQLite at %s", fallback
            )
            _engine = create_engine(fallback, **_engine_kwargs(fallback))
        else:  # pragma: no cover
            raise
    SessionLocal.configure(bind=_engine)
    return _engine


def get_engine() -> Engine:
    global _engine
    if _engine is None:
        configure_engine()
    assert _engine is not None
    return _engine


# Initialize engine on import so application code has a ready-to-use handle.
configure_engine()
