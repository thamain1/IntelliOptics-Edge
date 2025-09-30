from sqlalchemy import JSON, Boolean, Float, String
# Cross-dialect JSON: use JSON on SQLite, JSONB on Postgres
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, declarative_base, mapped_column

JSONType = JSON().with_variant(JSONB, "postgresql")

Base = declarative_base()


class ImageQueryRow(Base):
    __tablename__ = "image_queries"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    detector_id: Mapped[str] = mapped_column(String)
    blob_url: Mapped[str] = mapped_column(String)
    status: Mapped[str] = mapped_column(String, default="SUBMITTED")
    label: Mapped[str | None] = mapped_column(String, nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    result_type: Mapped[str | None] = mapped_column(String, nullable=True)
    count: Mapped[float | None] = mapped_column(Float, nullable=True)
    extra: Mapped[dict | None] = mapped_column(JSONType, nullable=True)
    done_processing: Mapped[bool] = mapped_column(Boolean, default=False)
