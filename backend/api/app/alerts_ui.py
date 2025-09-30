"""UI endpoints for configuring alert rules."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from .config import settings

_templates = Jinja2Templates(directory=str(Path(__file__).resolve().parent / "templates"))

router = APIRouter()


@router.get("/alerts", response_class=HTMLResponse)
async def alerts_console(request: Request):
    """Render the alerts configuration console."""

    return _templates.TemplateResponse(
        "alerts/index.html",
        {
            "request": request,
            "api_base": settings.api_base_path,
        },
    )
