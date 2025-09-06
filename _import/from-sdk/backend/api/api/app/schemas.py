from pydantic import BaseModel, Field

class SubmitQueryResponse(BaseModel):
    image_query_id: str
    status: str

class QueryStatusResponse(BaseModel):
    id: str
    status: str
    label: str | None = None
    confidence: float | None = None
    result_type: str | None = None
    count: float | None = None
    extra: dict | None = None

class HumanLabelRequest(BaseModel):
    label: str = Field(description="YES | NO | COUNT | UNCLEAR")
    confidence: float | None = None
    count: float | None = None
    notes: str | None = None
    user: str | None = None
    extra: dict | None = None
