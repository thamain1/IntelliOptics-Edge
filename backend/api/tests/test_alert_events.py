import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from backend.api.app import alerts, db, migrations, models


@pytest.fixture
def sqlite_alerts_db(tmp_path):
    url = f"sqlite:///{tmp_path/'alerts.db'}"
    db.configure_engine(url)
    migrations.migrate()
    yield
    db.get_engine().dispose()


def test_store_event_persists_payload(sqlite_alerts_db):
    payload = {
        "detector_id": "det-1",
        "image_query_id": "iq-1",
        "answer": "YES",
        "extra": {"foo": "bar"},
    }

    event_id = alerts._store_event_best_effort(payload)

    assert event_id

    with db.SessionLocal() as session:
        stored = session.get(models.AlertEvent, event_id)
        assert stored is not None
        assert stored.payload["extra"] == {"foo": "bar"}
        assert stored.detector_id == "det-1"


def test_recent_events_returns_latest(sqlite_alerts_db):
    alerts._store_event_best_effort(
        {
            "detector_id": "det-1",
            "image_query_id": "iq-1",
            "answer": "NO",
        }
    )
    alerts._store_event_best_effort(
        {
            "detector_id": "det-2",
            "image_query_id": "iq-2",
            "answer": "YES",
        }
    )

    app = FastAPI()
    app.include_router(alerts.router)
    client = TestClient(app)

    response = client.get("/v1/alerts/events/recent", params={"limit": 1})
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["limit"] == 1
    assert len(data["items"]) == 1
    assert data["items"][0]["image_query_id"] == "iq-2"


def test_store_event_handles_failures_gracefully(monkeypatch, sqlite_alerts_db):
    class BrokenSession:
        def __init__(self):
            self.rolled_back = False
            self.closed = False

        def add(self, _):
            pass

        def commit(self):
            raise RuntimeError("boom")

        def refresh(self, _):
            pass

        def rollback(self):
            self.rolled_back = True

        def close(self):
            self.closed = True

    broken = BrokenSession()
    monkeypatch.setattr(alerts, "SessionLocal", lambda: broken)

    event_id = alerts._store_event_best_effort({"detector_id": "det"})
    assert event_id is None
    assert broken.rolled_back is True
    assert broken.closed is True


def test_recent_events_returns_error_on_failure(monkeypatch, sqlite_alerts_db):
    def raise_session(*args, **kwargs):
        raise RuntimeError("db down")

    monkeypatch.setattr(alerts, "SessionLocal", raise_session)

    app = FastAPI()
    app.include_router(alerts.router)
    client = TestClient(app)

    response = client.get("/v1/alerts/events/recent")
    assert response.status_code == 503
    assert response.json()["detail"] == "event storage unavailable"
