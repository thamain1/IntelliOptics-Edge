"""Helpers used by the IntelliOptics experimental integrations."""
from __future__ import annotations

from typing import Any, Dict, Optional

from .client import IntelliOptics


class ExperimentalApi:
    """Small helper that exposes convenience methods used by the edge stack."""

    def __init__(self, client: IntelliOptics):
        self._client = client

    # ------------------------------------------------------------------
    # Convenience builders
    # ------------------------------------------------------------------
    def make_webhook_action(
        self,
        *,
        url: str,
        method: str = "POST",
        headers: Optional[Dict[str, str]] = None,
        include_image: bool = True,
    ) -> Dict[str, Any]:
        """Return a notification payload compatible with the alert-rules API."""

        final_headers = {"X-HTTP-Method": method.upper()}
        if headers:
            final_headers.update(headers)
        return {
            "primary_channel": "webhook",
            "primary_target": url,
            "include_image": include_image,
            "message_template": "",  # default empty template
            "template_format": "json",
            "headers": final_headers,
            "url": url,
            "recipients": [],
            "snooze": {"enabled": False, "minutes": None},
        }

    def make_condition(
        self,
        *,
        kind: str,
        parameters: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Convert legacy rule condition helpers into the new API schema."""

        params = parameters or {}
        label = params.get("label", "YES")
        consecutive = int(params.get("consecutive", 1))

        comparator_map = {
            "CHANGED_TO": "equals",
            "CHANGED_FROM": "not_equals",
        }
        comparator = comparator_map.get(kind.upper(), "equals")

        return {
            "comparator": comparator,
            "answer": label,
            "consecutive": max(1, consecutive),
        }

    # ------------------------------------------------------------------
    # API calls
    # ------------------------------------------------------------------
    def create_rule(
        self,
        *,
        detector: str,
        rule_name: str,
        action: Dict[str, Any],
        condition: Dict[str, Any],
        enabled: bool = True,
        detector_name: str | None = None,
        confirm_with_cloud: bool = False,
    ) -> Dict[str, Any]:
        payload = {
            "name": rule_name,
            "detector_id": detector,
            "detector_name": detector_name,
            "enabled": enabled,
            "condition": condition,
            "confirm_with_cloud": confirm_with_cloud,
            "notification": action,
        }
        return self._client._request("POST", "/v1/alert-rules", json=payload)
