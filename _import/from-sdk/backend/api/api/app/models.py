from sqlalchemy.orm import Mapped, mapped_column, declarative_base
from sqlalchemy import String, Float, Boolean, JSON, TIMESTAMP, func

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

    # portable JSON (works on SQLite and Postgres)
    extra = mapped_column(JSON, nullable=True)

    done_processing: Mapped[bool] = mapped_column(Boolean, default=False)

    # human review fields
    human_label: Mapped[str | None] = mapped_column(String, nullable=True)
    human_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    human_notes: Mapped[str | None] = mapped_column(String, nullable=True)
    human_user: Mapped[str | None] = mapped_column(String, nullable=True)
    human_labeled_at = mapped_column(TIMESTAMP(timezone=True), nullable=True)

    created_at = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
