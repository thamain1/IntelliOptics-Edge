from __future__ import annotations

import base64
import io
import os
import re
import ssl
import urllib.request
from dataclasses import dataclass
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, HttpUrl, validator

router = APIRouter(prefix="/v1/email", tags=["email"])

# ---------------------------
# Env & feature flags
# ---------------------------
SENDGRID_API_KEY = os.getenv("SENDGRID_API_KEY", "").strip()
EMAIL_FROM = os.getenv("EMAIL_FROM", "alerts@4wardmotions.com").strip()
EMAIL_FROM_NAME = os.getenv("EMAIL_FROM_NAME", "IntelliOptics Alerts").strip()
EMAIL_LOGO_URL = os.getenv("EMAIL_LOGO_URL", "").strip()

INLINE_IMAGES = os.getenv("EMAIL_INLINE_IMAGES", "true").lower() not in ("0", "false", "no")
INLINE_LOGO = os.getenv("EMAIL_INLINE_LOGO", "true").lower() not in ("0", "false", "no")

# Inline size guardrails
MAX_INLINE_BYTES = int(os.getenv("EMAIL_MAX_INLINE_BYTES", str(3 * 1024 * 1024)))  # 3 MB

# Snapshot overlay (disabled per request)
DRAW_QUERY = False  # Do not draw on image
# ---------------------------

class EmailSendRequest(BaseModel):
    to: List[str] = Field(..., description="List of recipient emails")
    subject: str = Field(..., description="Email subject")
    detector_id: str = Field(..., description="Detector ID")
    query_text: str = Field(..., description="Detector query text")
    answer: str = Field(..., description="Answer label such as YES/NO/COUNT")
    consecutive: Optional[int] = Field(None, description="Streak count if applicable")
    snapshot_url: Optional[HttpUrl] = Field(None, description="SAS or public URL to snapshot image")
    extra: Optional[dict] = Field(default=None)

    @validator("to")
    def _emails_valid(cls, v):
        if not v:
            raise ValueError("At least one recipient is required")
        email_re = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
        for addr in v:
            if not email_re.match(addr):
                raise ValueError(f"Invalid email: {addr}")
        return v


@dataclass
class FetchedAsset:
    content: bytes
    mime: str  # "image/jpeg", "image/png"
    filename: str


def _safe_fetch_bytes(url: str, timeout: float = 10.0) -> Optional[FetchedAsset]:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "IntelliOptics-EmailBot/1.0"})
        with urllib.request.urlopen(req, timeout=timeout, context=ssl.create_default_context()) as resp:
            content = resp.read()
            ctype = resp.headers.get_content_type() or "application/octet-stream"
            from urllib.parse import urlparse
            fname = os.path.basename(urlparse(url).path) or "image"
            return FetchedAsset(content=content, mime=ctype, filename=fname)
    except Exception:
        return None


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def _html_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#39;")
    )


def _build_email_html(
    *,
    detector_id: str,
    query_text: str,
    answer: str,
    consecutive: Optional[int],
    snapshot_href: Optional[str],
    use_cid_logo: bool,
    use_cid_snapshot: bool,
    logo_cid: str = "logo",
    snapshot_cid: str = "snapshot",
) -> str:
    title = "IntelliOptics"
    question = _html_escape(query_text)

    # Header logo (centered, larger)
    if use_cid_logo:
        logo_html = (
            f'<img src="cid:{logo_cid}" alt="IntelliOptics" '
            f'style="height:96px;display:block;margin:0 auto;border:0;" />'
        )
    elif EMAIL_LOGO_URL:
        logo_html = (
            f'<img src="{_html_escape(EMAIL_LOGO_URL)}" alt="IntelliOptics" '
            f'style="height:96px;display:block;margin:0 auto;border:0;" />'
        )
    else:
        logo_html = (
            f'<span style="font-weight:700;font-size:20px;letter-spacing:.5px;display:block;text-align:center">{title}</span>'
        )

    # Centered “query pill” (outside the image, not covering it)
    query_pill = f'''
      <div style="text-align:center;margin:10px 0 4px 0">
        <span style="
          display:inline-block;padding:8px 14px;border-radius:999px;
          background:#2a2a2a;border:1px solid #3a3a3a;color:#e6e6e6;
          font-size:14px;line-height:1.1;">
          {question}
        </span>
      </div>
    '''

    # Detector line (centered)
    detector_line = f'''
      <div style="font-size:13px;color:#bdbdbd;margin-bottom:8px;text-align:center">
        Detector: <span style="font-family:Consolas,Menlo,monospace">{_html_escape(detector_id)}</span>
      </div>
    '''

    # Snapshot block (centered)
    if use_cid_snapshot:
        snap_block = f"""
        <div style="margin-top:8px;text-align:center">
          <img src="cid:{snapshot_cid}" alt="Snapshot"
               style="max-width:100%;height:auto;border-radius:12px;border:1px solid #2d2d2d;display:block;margin:0 auto" />
        </div>
        """
    else:
        snap_link = _html_escape(snapshot_href) if snapshot_href else "#"
        snap_block = f"""
        <div style="margin-top:8px;text-align:center">
          <a href="{snap_link}" style="display:inline-block;padding:6px 10px;border-radius:999px;background:#333;border:1px solid #444;color:#ddd;text-decoration:none;font-size:12px">Snapshot</a>
          <div style="margin-top:6px;font-size:12px;line-height:1.3">
            <a href="{snap_link}" style="color:#8ab4f8;text-decoration:underline;word-break:break-all">{snap_link}</a>
          </div>
        </div>
        """

    html = f"""
<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#121212;color:#e0e0e0;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif">
    <div style="max-width:680px;margin:24px auto;padding:0 16px">
      <div style="background:#1c1c1c;border-radius:18px;padding:24px;border:1px solid #2a2a2a">
        <div style="margin-bottom:12px;text-align:center">{logo_html}</div>

        {query_pill}
        {detector_line}
        {snap_block}

        <div style="margin-top:16px;font-size:11px;color:#9e9e9e;text-align:center">
          © 4wardmotions Solutions, Inc
        </div>
      </div>
    </div>
  </body>
</html>
"""
    return html


def _send_via_sendgrid(
    *,
    req: EmailSendRequest,
    html: str,
    text: str,
    inline_logo: Optional[FetchedAsset],
    inline_snapshot: Optional[FetchedAsset],
) -> dict:
    if not SENDGRID_API_KEY:
        raise HTTPException(status_code=400, detail="SENDGRID_API_KEY is not configured")

    import json
    import urllib.request

    personalizations = [{"to": [{"email": addr} for addr in req.to]}]

    attachments = []
    if inline_logo:
        attachments.append(
            {
                "content": _b64(inline_logo.content),
                "type": inline_logo.mime,
                "filename": inline_logo.filename or "logo.png",
                "disposition": "inline",
                "content_id": "logo",
            }
        )
    if inline_snapshot:
        attachments.append(
            {
                "content": _b64(inline_snapshot.content),
                "type": inline_snapshot.mime,
                "filename": inline_snapshot.filename or "snapshot.jpg",
                "disposition": "inline",
                "content_id": "snapshot",
            }
        )

    payload = {
        "from": {"email": EMAIL_FROM, "name": EMAIL_FROM_NAME},
        "subject": req.subject,
        "personalizations": personalizations,
        "content": [
            {"type": "text/plain", "value": text},
            {"type": "text/html", "value": html},
        ],
    }
    if attachments:
        payload["attachments"] = attachments

    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        "https://api.sendgrid.com/v3/mail/send",
        data=data,
        headers={"Authorization": f"Bearer {SENDGRID_API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as resp:
            status = resp.getcode()
            return {"ok": True, "provider": "sendgrid", "status": f"accepted={status}"}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "ignore")
        raise HTTPException(status_code=e.code, detail=f"SendGrid error: {detail or e.reason}")
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"SendGrid transport error: {e}")


@router.post("/send")
def send_email(req: EmailSendRequest):
    """
    Send an email alert. Prefers SendGrid Web API with inline images (CID).
    Layout shows only the centered query pill above the image (no large headline).
    """
    # Plain-text alt (kept minimal; no big headline)
    text = (
        f"{req.query_text}?\n"
        f"Detector: {req.detector_id}\n"
        f"Answer: {req.answer.upper()}\n"
    )
    if req.consecutive and req.consecutive > 1:
        text += f"Consecutive: {req.consecutive}\n"
    if req.snapshot_url:
        text += f"Snapshot: {req.snapshot_url}\n"

    # Inline assets (logo + snapshot)
    logo_asset: Optional[FetchedAsset] = None
    if INLINE_LOGO and EMAIL_LOGO_URL:
        asset = _safe_fetch_bytes(EMAIL_LOGO_URL)
        if asset and asset.mime in ("image/png", "image/jpeg") and len(asset.content) <= MAX_INLINE_BYTES:
            logo_asset = asset

    snapshot_asset: Optional[FetchedAsset] = None
    if INLINE_IMAGES and req.snapshot_url:
        asset = _safe_fetch_bytes(str(req.snapshot_url))
        if asset and asset.mime in ("image/png", "image/jpeg") and len(asset.content) <= MAX_INLINE_BYTES:
            # Do not modify the image (no overlay)
            snapshot_asset = asset

    html = _build_email_html(
        detector_id=req.detector_id,
        query_text=req.query_text,
        answer=req.answer,
        consecutive=req.consecutive,
        snapshot_href=str(req.snapshot_url) if req.snapshot_url else None,
        use_cid_logo=bool(logo_asset),
        use_cid_snapshot=bool(snapshot_asset),
    )

    return _send_via_sendgrid(
        req=req,
        html=html,
        text=text,
        inline_logo=logo_asset,
        inline_snapshot=snapshot_asset,
    )
