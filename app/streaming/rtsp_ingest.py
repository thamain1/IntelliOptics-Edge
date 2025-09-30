"""RTSP streaming ingest that feeds frames into the edge inference pipeline."""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass
from typing import Dict, Optional
from urllib.parse import urlparse, urlunparse

import httpx

try:  # pragma: no cover - optional dependency is validated at runtime
    import cv2  # type: ignore
except Exception:  # pragma: no cover - handled gracefully when missing
    cv2 = None  # type: ignore[misc, assignment]

from app.api.naming import API_BASE_PATH
from app.core.app_state import AppState
from app.core.configs import StreamBackend, StreamConfig, StreamSubmissionMethod

LOGGER = logging.getLogger(__name__)


@dataclass(slots=True)
class _FramePayload:
    data: bytes
    content_type: str


class RTSPStreamWorker:
    """Worker that ingests a single RTSP stream and submits frames for inference."""

    def __init__(self, name: str, config: StreamConfig, app_state: AppState) -> None:
        self.name = name
        self.config = config
        self.app_state = app_state
        self._stop_event = asyncio.Event()
        self._capture: Optional["cv2.VideoCapture"] = None

    def stop(self) -> None:
        self._stop_event.set()

    async def run(self) -> None:
        if cv2 is None:
            LOGGER.error(
                "OpenCV is not available. Stream '%s' will not be started. "
                "Ensure opencv-python (non-headless) is installed in the runtime image.",
                self.name,
            )
            return

        detector_id = self.config.detector_id
        if not self.app_state.edge_inference_manager.detector_configured_for_edge_inference(detector_id):
            LOGGER.warning(
                "Skipping stream '%s' because detector '%s' is not configured for edge inference.",
                self.name,
                detector_id,
            )
            return

        LOGGER.info(
            "Starting RTSP ingest for stream '%s' targeting detector '%s' using %s submission.",
            self.name,
            detector_id,
            self.config.submission_method.value,
        )

        while not self._stop_event.is_set():
            try:
                if not await self._ensure_capture():
                    await asyncio.sleep(self.config.reconnect_delay_seconds)
                    continue

                payload = await self._read_frame()
                if payload is None:
                    await asyncio.sleep(self.config.reconnect_delay_seconds)
                    continue

                await self._submit_frame(payload)
                await asyncio.sleep(self.config.sampling_interval_seconds)
            except asyncio.CancelledError:  # pragma: no cover - cooperative cancellation
                raise
            except Exception as exc:  # pragma: no cover - defensive logging
                LOGGER.exception("Error while ingesting stream '%s': %s", self.name, exc)
                await asyncio.sleep(self.config.reconnect_delay_seconds)
        self._release_capture()
        LOGGER.info("Stopped RTSP ingest for stream '%s'.", self.name)

    async def _ensure_capture(self) -> bool:
        if self._capture is not None and self._capture.isOpened():
            return True

        self._release_capture()
        url = self._build_url()
        backend_flag = {
            StreamBackend.AUTO: 0,
            StreamBackend.FFMPEG: getattr(cv2, "CAP_FFMPEG", 0),
            StreamBackend.GSTREAMER: getattr(cv2, "CAP_GSTREAMER", 0),
        }[self.config.backend]

        LOGGER.debug("Opening stream '%s' with backend '%s'", self.name, self.config.backend.value)
        capture = cv2.VideoCapture(url, backend_flag) if backend_flag else cv2.VideoCapture(url)
        if not capture.isOpened():
            LOGGER.warning(
                "Failed to open RTSP stream '%s' using url '%s'. Will retry in %.1fs.",
                self.name,
                url,
                self.config.reconnect_delay_seconds,
            )
            return False

        self._capture = capture
        return True

    async def _read_frame(self) -> Optional[_FramePayload]:
        assert cv2 is not None  # already guarded in run
        if self._capture is None:
            return None

        ret, frame = await asyncio.to_thread(self._capture.read)
        if not ret or frame is None:
            LOGGER.warning("Stream '%s' returned an empty frame. Reinitializing capture.", self.name)
            self._release_capture()
            return None

        payload = await asyncio.to_thread(self._encode_frame, frame)
        return payload

    def _encode_frame(self, frame) -> _FramePayload:  # type: ignore[no-untyped-def]
        assert cv2 is not None  # for type checkers
        extension = ".jpg" if self.config.encoding == "jpeg" else ".png"
        content_type = "image/jpeg" if extension == ".jpg" else "image/png"
        success, buffer = cv2.imencode(extension, frame)
        if not success:
            raise RuntimeError(f"Failed to encode frame from stream '{self.name}' using {self.config.encoding}.")
        return _FramePayload(buffer.tobytes(), content_type)

    async def _submit_frame(self, payload: _FramePayload) -> None:
        if self.config.submission_method is StreamSubmissionMethod.EDGE:
            if not self.app_state.edge_inference_manager.inference_is_available(self.config.detector_id):
                LOGGER.debug(
                    "Inference service for detector '%s' is not ready. Skipping frame from stream '%s'.",
                    self.config.detector_id,
                    self.name,
                )
                return
            await asyncio.to_thread(
                self.app_state.edge_inference_manager.run_inference,
                self.config.detector_id,
                payload.data,
                payload.content_type,
            )
        else:
            await self._post_via_api(payload)

    async def _post_via_api(self, payload: _FramePayload) -> None:
        headers = {"Content-Type": payload.content_type}
        if self.config.api_token_env:
            token_value = os.environ.get(self.config.api_token_env)
            if token_value:
                headers["x-api-token"] = token_value
            else:
                LOGGER.warning(
                    "Environment variable '%s' is not set. API submission for stream '%s' may fail.",
                    self.config.api_token_env,
                    self.name,
                )
        url = f"{self.config.api_base_url}{API_BASE_PATH}/image-queries"
        try:
            async with httpx.AsyncClient(timeout=self.config.api_timeout_seconds) as client:
                response = await client.post(
                    url,
                    params={"detector_id": self.config.detector_id},
                    content=payload.data,
                    headers=headers,
                )
                response.raise_for_status()
        except httpx.HTTPError as exc:
            LOGGER.warning(
                "Failed to submit frame for stream '%s' to %s: %s",
                self.name,
                url,
                exc,
            )

    def _release_capture(self) -> None:
        if self._capture is not None:
            try:
                self._capture.release()
            except Exception:  # pragma: no cover - best effort cleanup
                LOGGER.debug("Error releasing capture for stream '%s'", self.name, exc_info=True)
        self._capture = None

    def _build_url(self) -> str:
        username, password = self.config.resolved_credentials
        if not username and not password:
            return self.config.url

        parsed = urlparse(self.config.url)
        if parsed.username or parsed.password:
            return self.config.url

        netloc = parsed.netloc
        if username:
            auth = username
            if password:
                auth = f"{auth}:{password}"
            netloc = f"{auth}@{netloc}"
        elif password:
            LOGGER.warning(
                "Password provided for stream '%s' without a username. Ignoring credentials.",
                self.name,
            )
        parsed = parsed._replace(netloc=netloc)
        return urlunparse(parsed)


class StreamIngestManager:
    """Coordinates RTSP stream ingest workers."""

    def __init__(self, app_state: AppState) -> None:
        self._app_state = app_state
        self._tasks: Dict[str, asyncio.Task[None]] = {}
        self._workers: Dict[str, RTSPStreamWorker] = {}

    async def start(self) -> None:
        if not self._app_state.stream_configs:
            LOGGER.info("No RTSP streams configured. Stream ingest manager is idle.")
            return

        for name, config in self._app_state.stream_configs.items():
            worker = RTSPStreamWorker(name=name, config=config, app_state=self._app_state)
            task = asyncio.create_task(worker.run(), name=f"rtsp-stream:{name}")
            self._workers[name] = worker
            self._tasks[name] = task

    async def stop(self) -> None:
        if not self._tasks:
            return

        for worker in self._workers.values():
            worker.stop()
        await asyncio.gather(*self._tasks.values(), return_exceptions=True)
        self._tasks.clear()
        self._workers.clear()
