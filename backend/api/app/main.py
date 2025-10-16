# intellioptics
import uuid

from fastapi import APIRouter, Body, Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .auth import require_auth
from .config import settings
from .db import Base, engine
from .models import ImageQueryRow

router = APIRouter()

# Ensure tables exist when DB is present (don’t crash if not)
try:
    Base.metadata.create_all(bind=engine)
except Exception:
    pass


def create_app() -> FastAPI:
    app = FastAPI(title="IntelliOptics Backend", version="0.2.0")

    # CORS
    origins = (
        ["*"]
        if settings.allowed_origins == "*"
        else [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Liveness/Readiness
    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

        # Submit an image query

        try:
            from sqlalchemy import inspect

            pk_col = inspect(ImageQueryRow).primary_key[0]
            _key = uuid.UUID(image_query_id) if "uuid" in str(pk_col.type).lower() else image_query_id
        except Exception:
            _key = image_query_id
        row = db.get(ImageQueryRow, _key)
        if not row:
            raise HTTPException(404, detail="image_query not found")
        row.human_label = body.label
        row.human_confidence = body.confidence
        row.human_notes = body.notes
        row.human_user = body.user
        db.commit()
        return {"ok": True}


async def human_label(image_query_id: str, body: dict = Body(...)):
    """
    Record a human label for an image query.
    Body: {"label": "YES|NO|UNCLEAR", "reason": "..."}
    """
    label = (body or {}).get("label")
    reason = (body or {}).get("reason")
    return {"ok": True, "image_query_id": image_query_id, "label": label, "reason": reason}


async def status():
    return {"ok": True, "status": "ready"}


# === IO ROUTER EXTENSIONS (AUTO) ===
iorouter = APIRouter()


@iorouter.post("/v1/image-queries/{image_query_id}/human-label", dependencies=[Depends(require_auth)])
async def human_label(image_query_id: str, body: dict = Body(...)):
    """
    Record a human label for an image query.
    Body: {"label": "YES|NO|UNCLEAR", "reason": "..."}
    """
    label = (body or {}).get("label")
    reason = (body or {}).get("reason")
    return {"ok": True, "image_query_id": image_query_id, "label": label, "reason": reason}


@iorouter.get("/v1/status")
async def status():
    return {"ok": True, "status": "ready"}


# Safely include if a FastAPI app is defined in this module
try:
    app  # type: ignore[name-defined]
except NameError:
    pass
else:
    app.include_router(iorouter)
