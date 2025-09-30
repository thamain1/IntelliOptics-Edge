# backend/api/app/security.py
from __future__ import annotations

import os
from typing import Optional

from fastapi import Header, HTTPException

API_KEY_HEADER_NAME = "X-IntelliOptics-Key"
INTELLIOPTICS_API_KEY = os.getenv("INTELLIOPTICS_API_KEY")


def require_api_key(x_intellioptics_key: Optional[str] = Header(default=None, alias=API_KEY_HEADER_NAME)):
    """
    Enforce API key when INTELLIOPTICS_API_KEY is set in the environment.
    If the env var is empty or missing, the check is bypassed (useful for dev).
    """
    if INTELLIOPTICS_API_KEY and (x_intellioptics_key != INTELLIOPTICS_API_KEY):
        raise HTTPException(status_code=401, detail="Unauthorized")
