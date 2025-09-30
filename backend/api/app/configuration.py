"""REST endpoints for managing edge configuration data."""

from __future__ import annotations

import logging
from contextlib import contextmanager
from typing import Iterator

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.configs import StreamConfig

from .config_store import (create_stream, delete_stream, export_yaml_payload,
                           get_stream, list_detectors, list_streams,
                           update_stream)
from .db import SessionLocal

try:  # Optional dependency during tests/local dev
    from .security import require_api_key  # type: ignore
except Exception:  # pragma: no cover - security dependency optional
    require_api_key = None  # type: ignore

log = logging.getLogger("intellioptics.config_api")

_dependencies = []
if require_api_key:
    _dependencies.append(Depends(require_api_key))

router = APIRouter(prefix="/v1/config", tags=["config"], dependencies=_dependencies)


@contextmanager
def _session_scope() -> Iterator[Session]:
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def _json_stream(stream: StreamConfig) -> dict:
    return stream.model_dump(mode="json")


@router.get("/detectors")
def get_detectors() -> dict:
    with _session_scope() as session:
        detectors = list_detectors(session)
        return {
            "items": [det.model_dump(mode="json") for det in detectors],
            "count": len(detectors),
        }


@router.get("/streams")
def get_streams() -> dict:
    with _session_scope() as session:
        streams = list_streams(session)
        return {
            "items": [_json_stream(stream) for stream in streams],
            "count": len(streams),
        }


@router.get("/streams/{name}")
def get_stream_detail(name: str) -> dict:
    with _session_scope() as session:
        try:
            stream = get_stream(session, name)
        except KeyError as exc:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Stream '{name}' not found") from exc
        return {"item": _json_stream(stream)}


@router.post("/streams", status_code=status.HTTP_201_CREATED)
def create_stream_endpoint(stream: StreamConfig) -> dict:
    try:
        with _session_scope() as session:
            created = create_stream(session, stream)
            return {"item": _json_stream(created)}
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except SQLAlchemyError as exc:  # pragma: no cover - DB failure path
        log.exception("Failed to create stream")
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="storage unavailable") from exc


@router.put("/streams/{name}")
def update_stream_endpoint(name: str, stream: StreamConfig) -> dict:
    if stream.name != name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Payload name must match path parameter",
        )
    try:
        with _session_scope() as session:
            updated = update_stream(session, stream)
            return {"item": _json_stream(updated)}
    except KeyError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Stream '{name}' not found") from exc
    except SQLAlchemyError as exc:  # pragma: no cover - DB failure path
        log.exception("Failed to update stream %s", name)
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="storage unavailable") from exc


@router.delete("/streams/{name}", status_code=status.HTTP_204_NO_CONTENT)
def delete_stream_endpoint(name: str) -> Response:
    try:
        with _session_scope() as session:
            delete_stream(session, name)
    except KeyError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Stream '{name}' not found") from exc
    except SQLAlchemyError as exc:  # pragma: no cover - DB failure path
        log.exception("Failed to delete stream %s", name)
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="storage unavailable") from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/export")
def export_config() -> dict:
    with _session_scope() as session:
        yaml_text, doc = export_yaml_payload(session)
        stream_count = len(doc.streams or {})
        detector_count = len(doc.detectors or {})
        updated_at = doc.updated_at.isoformat() if doc.updated_at else None
        return {
            "yaml": yaml_text,
            "stream_count": stream_count,
            "detector_count": detector_count,
            "updated_at": updated_at,
        }
