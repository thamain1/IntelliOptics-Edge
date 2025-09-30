import sys
from pathlib import Path

import pytest
import yaml
from fastapi import FastAPI
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from backend.api.app import (config_store, configuration, db,  # noqa: E402
                             migrations)


@pytest.fixture
def sqlite_config_db(tmp_path):
    url = f"sqlite:///{tmp_path/'config.db'}"
    db.configure_engine(url)
    migrations.migrate()
    with db.SessionLocal() as session:
        doc = config_store.ensure_document(session)
        doc.detectors = {"det_test": {"edge_inference_config": "default"}}
        session.add(doc)
        session.commit()
    yield
    db.get_engine().dispose()


def create_client():
    app = FastAPI()
    app.include_router(configuration.router)
    return TestClient(app)


def test_stream_crud_flow(sqlite_config_db):
    client = create_client()

    payload = {
        "name": "line-1",
        "detector_id": "det_test",
        "url": "rtsp://example.com/stream",
        "sampling_interval_seconds": 1.5,
        "reconnect_delay_seconds": 5.0,
        "backend": "auto",
        "encoding": "jpeg",
        "submission_method": "edge",
        "api_base_url": "http://127.0.0.1:30101",
        "api_timeout_seconds": 10,
    }

    resp = client.post("/v1/config/streams", json=payload)
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["item"]["name"] == "line-1"

    resp = client.get("/v1/config/streams")
    assert resp.status_code == 200
    listing = resp.json()
    assert listing["count"] == 1
    assert listing["items"][0]["detector_id"] == "det_test"

    detail = client.get("/v1/config/streams/line-1")
    assert detail.status_code == 200
    assert detail.json()["item"]["name"] == "line-1"

    payload_update = dict(payload)
    payload_update["sampling_interval_seconds"] = 2.0
    resp = client.put("/v1/config/streams/line-1", json=payload_update)
    assert resp.status_code == 200
    assert resp.json()["item"]["sampling_interval_seconds"] == 2.0

    resp = client.delete("/v1/config/streams/line-1")
    assert resp.status_code == 204

    resp = client.get("/v1/config/streams")
    assert resp.status_code == 200
    assert resp.json()["count"] == 0

    missing = client.get("/v1/config/streams/line-1")
    assert missing.status_code == 404


def test_duplicate_stream_rejected(sqlite_config_db):
    client = create_client()

    payload = {
        "name": "line-dup",
        "detector_id": "det_test",
        "url": "rtsp://example.com/a",
        "sampling_interval_seconds": 1.0,
        "reconnect_delay_seconds": 5.0,
        "backend": "auto",
        "encoding": "jpeg",
        "submission_method": "edge",
        "api_base_url": "http://127.0.0.1:30101",
        "api_timeout_seconds": 10,
    }

    assert client.post("/v1/config/streams", json=payload).status_code == 201
    resp = client.post("/v1/config/streams", json=payload)
    assert resp.status_code == 409


def test_export_returns_yaml(sqlite_config_db):
    client = create_client()

    payload = {
        "name": "line-export",
        "detector_id": "det_test",
        "url": "rtsp://example.com/export",
        "sampling_interval_seconds": 1.0,
        "reconnect_delay_seconds": 5.0,
        "backend": "auto",
        "encoding": "jpeg",
        "submission_method": "edge",
        "api_base_url": "http://127.0.0.1:30101",
        "api_timeout_seconds": 10,
    }

    client.post("/v1/config/streams", json=payload)

    resp = client.get("/v1/config/export")
    assert resp.status_code == 200
    data = resp.json()
    assert data["stream_count"] == 1
    assert data["detector_count"] >= 1
    loaded = yaml.safe_load(data["yaml"])
    assert any(stream["name"] == "line-export" for stream in loaded.get("streams", []))


def test_detectors_endpoint(sqlite_config_db):
    client = create_client()
    resp = client.get("/v1/config/detectors")
    assert resp.status_code == 200
    data = resp.json()
    assert data["count"] >= 1
    assert any(det["detector_id"] == "det_test" for det in data["items"])
