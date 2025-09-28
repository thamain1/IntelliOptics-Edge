"""Pydantic models shared by the IntelliOptics SDK and Edge runtime."""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, Union

from pydantic import BaseModel, Field


class ImageQueryTypeEnum(str, Enum):
    image_query = "IMAGE_QUERY"


class ModeEnum(str, Enum):
    BINARY = "BINARY"
    COUNT = "COUNT"
    MULTI_CLASS = "MULTI_CLASS"


class ResultTypeEnum(str, Enum):
    BINARY_CLASSIFICATION = "BINARY"
    COUNTING = "COUNTING"
    MULTI_CLASSIFICATION = "MULTI_CLASSIFICATION"


class Label(str, Enum):
    YES = "YES"
    NO = "NO"
    UNKNOWN = "UNKNOWN"


class Source(str, Enum):
    ALGORITHM = "ALGORITHM"
    HUMAN = "HUMAN"
    CLOUD = "CLOUD"


class ROI(BaseModel):
    """Region of interest returned by detectors."""

    x: float
    y: float
    width: float
    height: float
    label: Optional[str] = None
    confidence: Optional[float] = None


class CountModeConfiguration(BaseModel):
    max_count: Optional[int] = Field(default=None, description="Maximum count value that can be produced")
    greater_than_max_label: Optional[str] = Field(default=None, description="Label used when exceeding max count")


class MultiClassModeConfiguration(BaseModel):
    class_names: List[str]


class BinaryClassificationResult(BaseModel):
    confidence: float
    label: Label
    source: Source = Source.ALGORITHM
    from_edge: bool = False


class CountingResult(BaseModel):
    confidence: float
    count: int
    greater_than_max: bool = False
    source: Source = Source.ALGORITHM
    from_edge: bool = False


class MultiClassificationResult(BaseModel):
    confidence: float
    label: str
    source: Source = Source.ALGORITHM
    from_edge: bool = False


DetectorResult = Union[BinaryClassificationResult, CountingResult, MultiClassificationResult]


class ImageQuery(BaseModel):
    id: str
    detector_id: str
    created_at: datetime
    query: Optional[str] = None
    type: ImageQueryTypeEnum = ImageQueryTypeEnum.image_query
    result_type: Optional[ResultTypeEnum] = None
    result: Optional[DetectorResult] = None
    patience_time: Optional[float] = None
    confidence_threshold: Optional[float] = None
    metadata: Optional[Dict[str, Any]] = None
    rois: Optional[List[ROI]] = None
    text: Optional[str] = None
    done_processing: bool = False


class Detector(BaseModel):
    id: str
    name: str
    query: str
    mode: ModeEnum = ModeEnum.BINARY
    confidence_threshold: float = Field(default=0.75, ge=0.0, le=1.0)
    mode_configuration: Optional[Dict[str, Any]] = None
