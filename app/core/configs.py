import logging
import os
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, model_validator
from typing_extensions import Self

logger = logging.getLogger(__name__)


class GlobalConfig(BaseModel):
    refresh_rate: float = Field(
        default=60.0,
        description="The interval (in seconds) at which the inference server checks for a new model binary update.",
    )
    confident_audit_rate: float = Field(
        default=1e-5,  # A detector running at 1 FPS = ~100,000 IQ/day, so 1e-5 is ~1 confident IQ/day audited
        description="The probability that any given confident prediction will be sent to the cloud for auditing.",
    )


class EdgeInferenceConfig(BaseModel):
    """
    Configuration for edge inference on a specific detector.
    """

    enabled: bool = Field(  # TODO investigate and update the functionality of this option
        default=True, description="Whether the edge endpoint should accept image queries for this detector."
    )
    api_token: str | None = Field(
        default=None, description="API token used to fetch the inference model for this detector."
    )
    always_return_edge_prediction: bool = Field(
        default=False,
        description=(
            "Indicates if the edge-endpoint should always provide edge ML predictions, regardless of confidence. "
            "When this setting is true, whether or not the edge-endpoint should escalate low-confidence predictions "
            "to the cloud is determined by `disable_cloud_escalation`."
        ),
    )
    disable_cloud_escalation: bool = Field(
        default=False,
        description=(
            "Never escalate ImageQueries from the edge-endpoint to the cloud."
            "Requires `always_return_edge_prediction=True`."
        ),
    )
    min_time_between_escalations: float = Field(
        default=2.0,
        description=(
            "The minimum time (in seconds) to wait between cloud escalations for a given detector. "
            "Cannot be less than 0.0. "
            "Only applies when `always_return_edge_prediction=True` and `disable_cloud_escalation=False`."
        ),
    )

    @model_validator(mode="after")
    def validate_configuration(self) -> Self:
        if self.disable_cloud_escalation and not self.always_return_edge_prediction:
            raise ValueError(
                "The `disable_cloud_escalation` flag is only valid when `always_return_edge_prediction` is set to True."
            )
        if self.min_time_between_escalations < 0.0:
            raise ValueError("`min_time_between_escalations` cannot be less than 0.0.")
        return self


class DetectorConfig(BaseModel):
    """
    Configuration for a specific detector.
    """

    detector_id: str = Field(..., description="Detector ID")
    edge_inference_config: str = Field(..., description="Config for edge inference.")


class StreamSubmissionMethod(str, Enum):
    EDGE = "edge"
    API = "api"


class StreamBackend(str, Enum):
    AUTO = "auto"
    FFMPEG = "ffmpeg"
    GSTREAMER = "gstreamer"


class StreamCredentialConfig(BaseModel):
    """Credentials used to authenticate against RTSP endpoints."""

    username: str | None = Field(default=None, description="Inline username for the RTSP source.")
    password: str | None = Field(default=None, description="Inline password for the RTSP source.")
    username_env: str | None = Field(
        default=None,
        description=(
            "Environment variable that contains the RTSP username. Overrides `username` when set."
        ),
    )
    password_env: str | None = Field(
        default=None,
        description=(
            "Environment variable that contains the RTSP password. Overrides `password` when set."
        ),
    )

    @model_validator(mode="after")
    def validate_credentials(self) -> Self:
        if self.username_env and self.username:
            raise ValueError("Specify either `username` or `username_env`, not both.")
        if self.password_env and self.password:
            raise ValueError("Specify either `password` or `password_env`, not both.")
        return self

    def resolve(self) -> tuple[Optional[str], Optional[str]]:
        username = self.username
        password = self.password

        if self.username_env:
            username = os.environ.get(self.username_env, username)
        if self.password_env:
            password = os.environ.get(self.password_env, password)

        return username, password


class StreamConfig(BaseModel):
    """Configuration describing how to ingest an RTSP stream."""

    name: str = Field(..., description="Unique identifier for this stream.")
    detector_id: str = Field(..., description="Detector that should handle frames from this stream.")
    url: str = Field(..., description="RTSP/GStreamer URL used to open the stream.")
    sampling_interval_seconds: float = Field(
        default=1.0,
        ge=0.05,
        description="Minimum delay between sampled frames. Must be > 0 for steady ingest.",
    )
    reconnect_delay_seconds: float = Field(
        default=5.0,
        ge=0.5,
        description="Delay before reconnecting after an ingest failure.",
    )
    backend: StreamBackend = Field(
        default=StreamBackend.AUTO,
        description="Preferred OpenCV backend when opening the stream.",
    )
    encoding: str = Field(
        default="jpeg",
        pattern="^(jpeg|png)$",
        description="Image codec used when serializing frames for inference.",
    )
    submission_method: StreamSubmissionMethod = Field(
        default=StreamSubmissionMethod.EDGE,
        description=(
            "How frames should be submitted for inference. "
            "Use 'edge' to call the in-process edge inference manager or 'api' to POST to /image-queries."
        ),
    )
    api_base_url: str = Field(
        default="http://127.0.0.1:30101",
        description="Base URL used when submitting frames via the local API.",
    )
    api_timeout_seconds: float = Field(
        default=10.0, ge=1.0, description="Timeout applied to HTTP submissions when using the API pathway."
    )
    api_token_env: str | None = Field(
        default=None,
        description="Environment variable that provides the API token when submitting via the API.",
    )
    credentials: StreamCredentialConfig | None = Field(
        default=None,
        description="Optional RTSP credentials. Supports inline values or environment variable references.",
    )

    @property
    def resolved_credentials(self) -> tuple[Optional[str], Optional[str]]:
        if self.credentials is None:
            return None, None
        return self.credentials.resolve()


class RootEdgeConfig(BaseModel):
    """
    Root configuration for edge inference.
    """

    global_config: GlobalConfig
    edge_inference_configs: dict[str, EdgeInferenceConfig]
    detectors: dict[str, DetectorConfig]
    streams: dict[str, StreamConfig] = Field(
        default_factory=dict,
        description=(
            "Streaming ingest configuration keyed by stream name."
        ),
    )

    @model_validator(mode="after")
    def validate_inference_configs(self):
        """
        Validate the edge inference configs specified for the detectors. Example model structure:
            {
                'global_config': {
                    'refresh_rate': 60.0,
                    'confident_audit_rate': 1e-5,
                },
                'edge_inference_configs': {
                    'default': EdgeInferenceConfig(
                                    enabled=True,
                                    api_token=None,
                                    always_return_edge_prediction=False,
                                    disable_cloud_escalation=False,
                                    min_time_between_escalations=2.0
                                )
                },
                'detectors': {
                    'detector_1': DetectorConfig(
                                    detector_id='det_123',
                                    edge_inference_config='default'
                                )
                }
            }
        """
        for detector_config in self.detectors.values():
            if detector_config.edge_inference_config not in self.edge_inference_configs:
                raise ValueError(f"Edge inference config {detector_config.edge_inference_config} not defined.")
        for stream_name, stream_config in self.streams.items():
            if stream_config.detector_id not in self.detectors:
                raise ValueError(
                    f"Stream '{stream_name}' references detector '{stream_config.detector_id}' which is not configured."
                )
        return self
