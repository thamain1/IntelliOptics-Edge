"""UI endpoints for the stream configuration console."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from .config import settings

_templates = Jinja2Templates(directory=str(Path(__file__).resolve().parent / "templates"))

router = APIRouter()


@router.get("/config/streams", response_class=HTMLResponse)
async def stream_console(request: Request):
    return _templates.TemplateResponse(
        "config/streams.html",
        {
            "request": request,
            "api_base": settings.api_base_path,
        },
    )
