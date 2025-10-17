# IntelliOptics API main (clean baseline)
from typing import Dict
from fastapi import FastAPI, APIRouter, Body
from fastapi.middleware.cors import CORSMiddleware

# Config (tolerate missing settings in slim images)
try:
    from .config import settings  # type: ignore
except Exception:  # pragma: no cover
    class _S: allowed_origins = "*"
    settings = _S()  # type: ignore

# Optional DB init (no-op if DB not present)
try:
    from .db import Base, engine  # type: ignore
    Base.metadata.create_all(bind=engine)  # type: ignore
except Exception:
    pass

router = APIRouter()

@router.get("/v1/status")
async def v1_status():
    return {"ok": True, "status": "ready"}

@router.post("/v1/image-queries/{image_query_id}/human-label")
async def human_label(image_query_id: str, body: Dict = Body(...)):
    label  = (body or {}).get("label")
    reason = (body or {}).get("reason")
    return {"ok": True, "image_query_id": image_query_id, "label": label, "reason": reason}

def create_app() -> FastAPI:
    app = FastAPI(title="IntelliOptics Backend", version="0.2.0")

    # CORS
    allowed = getattr(settings, "allowed_origins", "*")
    origins = ["*"] if allowed == "*" else [o.strip() for o in str(allowed).split(",") if o.strip()]
    app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["*"], allow_headers=["*"])

    # Liveness
    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

    app.include_router(router)
    return app

app = create_app()
