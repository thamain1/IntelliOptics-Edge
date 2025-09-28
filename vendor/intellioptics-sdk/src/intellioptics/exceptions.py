"""Custom exception hierarchy used by the IntelliOptics SDK."""
from __future__ import annotations

from typing import Optional


class IntelliOpticsError(Exception):
    """Base class for all IntelliOptics SDK errors."""


class IntelliOpticsClientError(IntelliOpticsError):
    """Raised for client side configuration issues."""


class ApiException(IntelliOpticsError):
    """Raised when the IntelliOptics API returns a non-successful response."""

    def __init__(self, status: int, reason: str, body: Optional[str] = None):
        self.status = status
        self.reason = reason
        self.body = body
        super().__init__(f"HTTP {status}: {reason}")


class ApiTokenError(ApiException):
    """Raised when an API token is invalid or missing."""

    def __init__(self, reason: str = "Missing or invalid API token"):
        super().__init__(status=401, reason=reason)
