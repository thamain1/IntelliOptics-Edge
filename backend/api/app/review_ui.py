"""UI endpoints that render the human-in-the-loop review console."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from .config import settings

_templates = Jinja2Templates(
    directory=str(Path(__file__).resolve().parent / "templates")
)

router = APIRouter()


@router.get("/review", response_class=HTMLResponse)
async def review_console(request: Request):
    """Render the review console shell page."""

    return _templates.TemplateResponse(
        "review/index.html",
        {
            "request": request,
            "api_base": settings.api_base_path,
        },
    )
