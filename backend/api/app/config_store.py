"""Persistence helpers for managing edge configuration state in the cloud API."""

from __future__ import annotations

import logging
from copy import deepcopy
from pathlib import Path
from typing import Dict, Iterable, List

import yaml
from sqlalchemy.orm import Session

from app.core.configs import DetectorConfig, RootEdgeConfig, StreamConfig

from .models import EdgeConfigDocument

log = logging.getLogger("intellioptics.config_store")

DEFAULT_EDGE_CONFIG_PATH = Path(__file__).resolve().parents[3] / "configs" / "edge-config.yaml"
_DEFAULT_DOCUMENT_NAME = "active"


def _canonical_detectors(raw: Iterable[dict] | Dict[str, dict] | None) -> Dict[str, dict]:
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return {str(k): dict(v) if isinstance(v, dict) else {"edge_inference_config": v} for k, v in raw.items()}

    result: Dict[str, dict] = {}
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        detector_id = str(entry.get("detector_id", ""))
        payload = {k: v for k, v in entry.items() if k != "detector_id"}
        if "edge_inference_config" not in payload:
            payload["edge_inference_config"] = "default"
        result[detector_id] = payload
    return result


def _canonical_streams(raw: Iterable[dict] | Dict[str, dict] | None) -> Dict[str, dict]:
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return {str(k): dict(v) if isinstance(v, dict) else {} for k, v in raw.items()}

    result: Dict[str, dict] = {}
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name", ""))
        payload = {k: v for k, v in entry.items() if k != "name"}
        if not name:
            continue
        result[name] = payload
    return result


def _load_default_config() -> dict:
    if DEFAULT_EDGE_CONFIG_PATH.exists():
        log.info("Initializing edge_config_documents from %s", DEFAULT_EDGE_CONFIG_PATH)
        with DEFAULT_EDGE_CONFIG_PATH.open("r", encoding="utf-8") as fh:
            raw = yaml.safe_load(fh) or {}
    else:
        log.warning("Default edge config file missing at %s; using minimal scaffold", DEFAULT_EDGE_CONFIG_PATH)
        raw = {}

    return {
        "global_config": deepcopy(raw.get("global_config", {})),
        "edge_inference_configs": deepcopy(raw.get("edge_inference_configs", {})),
        "detectors": _canonical_detectors(raw.get("detectors")),
        "streams": _canonical_streams(raw.get("streams")),
    }


def ensure_document(session: Session) -> EdgeConfigDocument:
    doc = (
        session.query(EdgeConfigDocument)
        .filter(EdgeConfigDocument.name == _DEFAULT_DOCUMENT_NAME)
        .one_or_none()
    )
    if doc is None:
        payload = _load_default_config()
        doc = EdgeConfigDocument(
            name=_DEFAULT_DOCUMENT_NAME,
            global_config=payload["global_config"],
            edge_inference_configs=payload["edge_inference_configs"],
            detectors=payload["detectors"],
            streams=payload["streams"],
        )
        session.add(doc)
        session.commit()
        session.refresh(doc)
    return doc


def _stream_dict(stream: StreamConfig) -> dict:
    return stream.model_dump(mode="json", exclude={"name"})


def list_detectors(session: Session) -> List[DetectorConfig]:
    doc = ensure_document(session)
    detectors: Dict[str, dict] = doc.detectors or {}
    items: List[DetectorConfig] = []
    for detector_id, payload in sorted(detectors.items(), key=lambda item: item[0]):
        data = {"detector_id": detector_id, **(payload or {})}
        try:
            items.append(DetectorConfig(**data))
        except Exception as exc:
            log.warning("Invalid detector config for %s ignored: %s", detector_id, exc)
    return items


def list_streams(session: Session) -> List[StreamConfig]:
    doc = ensure_document(session)
    streams: Dict[str, dict] = doc.streams or {}
    items: List[StreamConfig] = []
    for name, payload in sorted(streams.items(), key=lambda item: item[0]):
        try:
            items.append(StreamConfig(**{"name": name, **(payload or {})}))
        except Exception as exc:
            log.warning("Invalid stream config for %s ignored: %s", name, exc)
    return items


def get_stream(session: Session, name: str) -> StreamConfig:
    """Return a single stream definition from the configuration store."""

    doc = ensure_document(session)
    streams: Dict[str, dict] = doc.streams or {}
    payload = streams.get(name)
    if payload is None:
        raise KeyError(name)
    try:
        return StreamConfig(**{"name": name, **(payload or {})})
    except Exception as exc:  # pragma: no cover - invalid data guarded via create/update
        log.error("Stream '%s' in storage is invalid: %s", name, exc)
        raise


def create_stream(session: Session, stream: StreamConfig) -> StreamConfig:
    doc = ensure_document(session)
    streams = dict(doc.streams or {})
    if stream.name in streams:
        raise ValueError(f"Stream '{stream.name}' already exists")
    streams[stream.name] = _stream_dict(stream)
    doc.streams = streams
    session.add(doc)
    session.commit()
    session.refresh(doc)
    return stream


def update_stream(session: Session, stream: StreamConfig) -> StreamConfig:
    doc = ensure_document(session)
    streams = dict(doc.streams or {})
    if stream.name not in streams:
        raise KeyError(stream.name)
    streams[stream.name] = _stream_dict(stream)
    doc.streams = streams
    session.add(doc)
    session.commit()
    session.refresh(doc)
    return stream


def delete_stream(session: Session, name: str) -> None:
    doc = ensure_document(session)
    streams = dict(doc.streams or {})
    if name not in streams:
        raise KeyError(name)
    streams.pop(name)
    doc.streams = streams
    session.add(doc)
    session.commit()
    session.refresh(doc)


def export_root_config(session: Session) -> tuple[RootEdgeConfig, EdgeConfigDocument]:
    doc = ensure_document(session)
    payload = {
        "global_config": doc.global_config or {},
        "edge_inference_configs": doc.edge_inference_configs or {},
        "detectors": {det.detector_id: det.model_dump(mode="json") for det in list_detectors(session)},
        "streams": {stream.name: stream.model_dump(mode="json") for stream in list_streams(session)},
    }
    config = RootEdgeConfig(**payload)
    return config, doc


def export_yaml_payload(session: Session) -> tuple[str, EdgeConfigDocument]:
    config, doc = export_root_config(session)
    detectors_list = [
        {"detector_id": det_id, **det.model_dump(mode="json", exclude={"detector_id"})}
        for det_id, det in config.detectors.items()
    ]
    streams_list = [
        {"name": name, **stream.model_dump(mode="json", exclude={"name"})}
        for name, stream in config.streams.items()
    ]
    payload = {
        "global_config": config.global_config.model_dump(mode="json"),
        "edge_inference_configs": {
            key: value.model_dump(mode="json") for key, value in config.edge_inference_configs.items()
        },
        "detectors": detectors_list,
        "streams": streams_list,
    }
    yaml_text = yaml.safe_dump(payload, sort_keys=False)
    return yaml_text, doc
