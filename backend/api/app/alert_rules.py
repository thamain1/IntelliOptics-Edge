"""REST API for configuring alert rules surfaced in the alarms UI."""

from __future__ import annotations

import json
import uuid
from pathlib import Path
from threading import Lock
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .db import get_db
from .models import ImageQueryRow


class TriggerCondition(BaseModel):
    """Defines how an alert is triggered for a detector."""

    comparator: str = Field(
        "equals",
        description="Comparison applied to the detector answer",
    )
    answer: str = Field(
        ..., description="Detector answer that should trip the alert", min_length=1
    )
    consecutive: int = Field(
        1,
        ge=1,
        le=10,
        description="Number of consecutive matches required before firing",
    )

    @validator("comparator")
    def _validate_comparator(cls, value: str) -> str:
        allowed = {"equals", "not_equals"}
        if value not in allowed:
            raise ValueError(f"comparator must be one of {sorted(allowed)}")
        return value


class Recipient(BaseModel):
    """Represents a downstream notification recipient."""

    channel: str = Field(
        ..., description="Notification channel", regex=r"^[a-zA-Z0-9_-]+$"
    )
    address: str = Field(
        ..., description="Channel specific destination", min_length=3
    )
    country_code: Optional[str] = Field(
        default=None,
        description="E.164 country code for SMS/voice destinations",
        regex=r"^\+?[0-9]{1,4}$",
    )


class SnoozeSettings(BaseModel):
    enabled: bool = Field(False, description="Whether alert snoozing is active")
    minutes: Optional[int] = Field(
        default=None,
        ge=1,
        le=1440,
        description="How many minutes to snooze after sending",
    )

    @validator("minutes", always=True)
    def _require_minutes(cls, value: Optional[int], values: Dict[str, object]) -> Optional[int]:
        if values.get("enabled") and value is None:
            raise ValueError("minutes must be provided when snooze is enabled")
        return value


class NotificationSettings(BaseModel):
    primary_channel: str = Field(
        "sms",
        description="Primary notification channel",
        regex=r"^[a-zA-Z0-9_-]+$",
    )
    primary_target: str = Field(..., description="Primary destination", min_length=3)
    include_image: bool = Field(
        False, description="Attach the annotated image in the notification"
    )
    message_template: str = Field(
        "",
        description="Template used for notification bodies",
    )
    template_format: str = Field(
        "plain",
        description="Template format hint",
        regex=r"^[a-zA-Z0-9_-]+$",
    )
    headers: Dict[str, str] = Field(
        default_factory=dict,
        description="Optional HTTP headers for webhook style notifications",
    )
    url: Optional[str] = Field(
        default=None,
        description="Webhook or landing URL associated with the alert",
    )
    recipients: List[Recipient] = Field(
        default_factory=list,
        description="Additional recipients to notify",
    )
    snooze: SnoozeSettings = Field(
        default_factory=SnoozeSettings,
        description="Post-send snooze configuration",
    )


class AlertRuleBase(BaseModel):
    name: str = Field(..., description="Human readable alert name", min_length=1)
    detector_id: str = Field(..., description="Detector identifier", min_length=3)
    detector_name: Optional[str] = Field(
        default=None, description="Friendly detector name"
    )
    enabled: bool = Field(True, description="Whether the alert is active")
    condition: TriggerCondition = Field(..., description="Trigger condition")
    confirm_with_cloud: bool = Field(
        False, description="Require cloud labelers before alerting"
    )
    notification: NotificationSettings = Field(
        ..., description="Notification delivery settings"
    )


class AlertRuleCreate(AlertRuleBase):
    pass


class AlertRule(AlertRuleBase):
    id: str = Field(..., description="Stable alert identifier")


class AlertRuleStore:
    """Lightweight JSON backed persistence for alert rules."""

    def __init__(self, path: Path):
        self.path = path
        self._lock = Lock()
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text("[]", encoding="utf-8")

    def _load(self) -> List[AlertRule]:
        raw: List[dict]
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            raw = []
        return [AlertRule(**item) for item in raw]

    def _write(self, items: List[AlertRule]) -> None:
        payload = [item.dict() for item in items]
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        tmp.replace(self.path)

    def list(self) -> List[AlertRule]:
        with self._lock:
            return self._load()

    def get(self, rule_id: str) -> Optional[AlertRule]:
        with self._lock:
            for rule in self._load():
                if rule.id == rule_id:
                    return rule
        return None

    def upsert(self, rule: AlertRule) -> AlertRule:
        with self._lock:
            items = self._load()
            updated: List[AlertRule] = []
            found = False
            for existing in items:
                if existing.id == rule.id:
                    updated.append(rule)
                    found = True
                else:
                    updated.append(existing)
            if not found:
                updated.append(rule)
            self._write(updated)
            return rule

    def delete(self, rule_id: str) -> None:
        with self._lock:
            items = [rule for rule in self._load() if rule.id != rule_id]
            self._write(items)


_store = AlertRuleStore(Path(__file__).resolve().parent / "data" / "alert_rules.json")

router = APIRouter(prefix="/v1/alert-rules", tags=["alert-rules"])


@router.get("", response_model=List[AlertRule])
def list_rules() -> List[AlertRule]:
    """Return all configured alert rules."""

    return _store.list()


@router.post("", response_model=AlertRule, status_code=status.HTTP_201_CREATED)
def create_rule(payload: AlertRuleCreate) -> AlertRule:
    """Create a brand new alert rule."""

    rule = AlertRule(id="arl_" + uuid.uuid4().hex, **payload.dict())
    return _store.upsert(rule)


@router.get("/{rule_id}", response_model=AlertRule)
def get_rule(rule_id: str) -> AlertRule:
    rule = _store.get(rule_id)
    if not rule:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert rule not found")
    return rule


@router.put("/{rule_id}", response_model=AlertRule)
def update_rule(rule_id: str, payload: AlertRuleCreate) -> AlertRule:
    existing = _store.get(rule_id)
    if not existing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert rule not found")
    updated = AlertRule(id=rule_id, **payload.dict())
    return _store.upsert(updated)


@router.delete("/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_rule(rule_id: str) -> None:
    existing = _store.get(rule_id)
    if not existing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert rule not found")
    _store.delete(rule_id)


@router.get("/detectors")
def detectors(db: Session = Depends(get_db)) -> List[Dict[str, object]]:
    """Return detector identifiers observed in the ingestion tables."""

    stmt = (
        select(
            ImageQueryRow.detector_id,
            func.count(ImageQueryRow.id).label("total"),
            func.max(ImageQueryRow.created_at).label("last_seen"),
        )
        .where(ImageQueryRow.detector_id.isnot(None))
        .group_by(ImageQueryRow.detector_id)
        .order_by(func.max(ImageQueryRow.created_at).desc())
    )
    rows = db.execute(stmt).all()
    results: List[Dict[str, object]] = []
    for detector_id, total, last_seen in rows:
        results.append(
            {
                "id": detector_id,
                "label": detector_id,
                "total_queries": int(total or 0),
                "last_seen": last_seen.isoformat() if last_seen else None,
            }
        )
    return results
