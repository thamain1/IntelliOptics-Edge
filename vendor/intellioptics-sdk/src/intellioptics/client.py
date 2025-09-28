"""HTTP client implementation for the IntelliOptics SDK."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Dict

import httpx

from .exceptions import ApiException, ApiTokenError, IntelliOpticsClientError
from .models import (
    BinaryClassificationResult,
    Detector,
    ImageQuery,
    ImageQueryTypeEnum,
    Label,
    ModeEnum,
    ResultTypeEnum,
    Source,
)

DEFAULT_BASE_URL = "https://intellioptics-api-37558.azurewebsites.net"


class _ApiClientConfig:
    def __init__(self, api_token: str | None):
        self.api_key: Dict[str, str] = {"ApiToken": api_token or ""}


class _ApiClient:
    def __init__(self, config: _ApiClientConfig):
        self.configuration = config


class IntelliOptics:
    """Minimal SDK for interacting with the IntelliOptics HTTP API."""

    def __init__(
        self,
        *,
        api_token: str | None = None,
        base_url: str | None = None,
        endpoint: str | None = None,
        timeout: float = 30.0,
        http_client: httpx.Client | None = None,
    ) -> None:
        if not api_token:
            raise ApiTokenError("An API token is required to communicate with IntelliOptics")

        self._token = api_token
        self.base_url = (endpoint or base_url or DEFAULT_BASE_URL).rstrip("/")
        self._timeout = timeout
        self._client = http_client or httpx.Client(base_url=self.base_url, timeout=self._timeout)
        self._owns_client = http_client is None
        self.api_client = _ApiClient(_ApiClientConfig(api_token))

    # ------------------------------------------------------------------
    # Lifecycle helpers
    # ------------------------------------------------------------------
    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def __enter__(self) -> "IntelliOptics":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------
    def _headers(self) -> Dict[str, str]:
        return {"Authorization": f"Bearer {self._token}"}

    def _request(self, method: str, path: str, *, expect_json: bool = True, **kwargs) -> Any:
        url = path if path.startswith("http") else f"{self.base_url}{path}"
        if "headers" in kwargs:
            headers = {**self._headers(), **kwargs.pop("headers")}
        else:
            headers = self._headers()
        try:
            response = self._client.request(method, url, headers=headers, **kwargs)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:  # pragma: no cover - network failure handling
            raise ApiException(status=exc.response.status_code, reason=exc.response.text) from exc
        except httpx.HTTPError as exc:  # pragma: no cover - network failure handling
            raise IntelliOpticsClientError(str(exc)) from exc

        if expect_json:
            return response.json()
        return response

    def _build_image_query(self, payload: Dict[str, Any]) -> ImageQuery:
        iq_id = payload.get("id") or payload.get("image_query_id")
        if not iq_id:
            raise IntelliOpticsClientError("API response did not contain an image query id")

        created_raw = payload.get("received_ts") or payload.get("created_at")
        if created_raw:
            try:
                created_at = datetime.fromisoformat(created_raw.replace("Z", "+00:00"))
            except ValueError:
                created_at = datetime.now(timezone.utc)
        else:
            created_at = datetime.now(timezone.utc)

        result_type = payload.get("result_type")
        result_type_enum = None
        if result_type:
            try:
                result_type_enum = ResultTypeEnum(result_type)
            except ValueError:
                # Accept lowercase/legacy values by normalising
                result_type_enum = ResultTypeEnum(result_type.upper()) if isinstance(result_type, str) else None

        result_obj = None
        answer = payload.get("answer")
        if answer:
            try:
                label = Label(answer)
            except ValueError:
                label = Label.UNKNOWN
            if result_type_enum is None:
                result_type_enum = ResultTypeEnum.BINARY_CLASSIFICATION
            if result_type_enum == ResultTypeEnum.BINARY_CLASSIFICATION:
                result_obj = BinaryClassificationResult(
                    confidence=float(payload.get("confidence") or 0.0),
                    label=label,
                    source=Source.CLOUD,
                    from_edge=False,
                )

        metadata = payload.get("extra") or payload.get("metadata")
        rois = metadata.get("edge_result", {}).get("rois") if isinstance(metadata, dict) else None

        return ImageQuery(
            id=iq_id,
            detector_id=payload.get("detector_id", ""),
            created_at=created_at,
            type=ImageQueryTypeEnum.image_query,
            result_type=result_type_enum,
            result=result_obj,
            confidence_threshold=payload.get("confidence_threshold"),
            metadata=metadata if isinstance(metadata, dict) else None,
            rois=rois,
            done_processing=bool(payload.get("done_processing")),
        )

    # ------------------------------------------------------------------
    # Public API methods
    # ------------------------------------------------------------------
    def get_detector(self, id: str) -> Detector:
        payload = self._request("GET", f"/v1/detectors/{id}")
        mode_value = payload.get("mode", ModeEnum.BINARY.value)
        try:
            payload["mode"] = ModeEnum(mode_value.upper())
        except ValueError:
            payload["mode"] = ModeEnum.BINARY
        return Detector.model_validate(payload)

    def submit_image_query(
        self,
        *,
        detector: str,
        image: bytes,
        content_type: str = "image/jpeg",
        wait: float = 0,
        patience_time: float | None = None,
        confidence_threshold: float | None = None,
        human_review: str | None = None,
        want_async: bool = False,
        metadata: Dict[str, Any] | None = None,
        image_query_id: str | None = None,
    ) -> ImageQuery:
        form: Dict[str, Any] = {"detector_id": detector}
        if patience_time is not None:
            form["patience_time"] = str(patience_time)
        if confidence_threshold is not None:
            form["confidence_threshold"] = str(confidence_threshold)
        if human_review is not None:
            form["human_review"] = human_review
        if metadata is not None:
            form["metadata"] = json.dumps(metadata)
        if image_query_id is not None:
            form["image_query_id"] = image_query_id
        if want_async:
            form["want_async"] = "true"
        if wait:
            form["wait"] = str(wait)

        files = {"image": ("upload", image, content_type)}
        payload = self._request("POST", "/v1/image-queries", data=form, files=files)

        iq = self._build_image_query(payload)

        if wait and not want_async:
            iq = self.wait_for_image_query(iq.id, timeout=wait)
        return iq

    def wait_for_image_query(self, image_query_id: str, timeout: float = 8.0) -> ImageQuery:
        payload = self._request(
            "GET",
            f"/v1/image-queries/{image_query_id}/wait",
            params={"timeout_ms": int(timeout * 1000)},
        )
        return self._build_image_query(payload)

    def ask_async(self, **kwargs) -> ImageQuery:
        kwargs.setdefault("wait", 0)
        kwargs.setdefault("want_async", True)
        return self.submit_image_query(**kwargs)
