"""Authentication helpers for Azure AD protected routes."""

from __future__ import annotations

import asyncio
import base64
import json
import time
from datetime import datetime, timezone
from typing import Any, Dict

import httpx
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from fastapi import HTTPException, Request, status

from .config import settings

_metadata_lock = asyncio.Lock()
_jwks_lock = asyncio.Lock()
_openid_metadata: Dict[str, Any] | None = None
_jwks_keys: Dict[str, Dict[str, Any]] = {}
_jwks_fetched_at: float | None = None


def _raise_unauthorized(detail: str = "Unauthorized") -> None:
    """Helper to consistently raise 401 errors."""

    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=detail)


async def _fetch_json(url: str) -> Dict[str, Any]:
    """Fetch JSON from a URL with a short timeout."""

    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(url)
        response.raise_for_status()
        return response.json()


def _openid_config_url() -> str:
    if settings.azure_openid_config:
        return settings.azure_openid_config
    if settings.azure_tenant_id:
        return f"https://login.microsoftonline.com/{settings.azure_tenant_id}/v2.0/.well-known/openid-configuration"
    _raise_unauthorized("Authentication not configured")


async def _get_openid_metadata() -> Dict[str, Any]:
    global _openid_metadata

    if _openid_metadata is not None:
        return _openid_metadata

    async with _metadata_lock:
        if _openid_metadata is not None:
            return _openid_metadata

        metadata = await _fetch_json(_openid_config_url())
        if "jwks_uri" not in metadata or "issuer" not in metadata:
            _raise_unauthorized("Invalid OpenID configuration")

        _openid_metadata = metadata
        return metadata


async def _load_jwks(force_refresh: bool = False) -> Dict[str, Dict[str, Any]]:
    global _jwks_keys, _jwks_fetched_at

    if not force_refresh and _jwks_keys and _jwks_fetched_at and (time.time() - _jwks_fetched_at < 3600):
        return _jwks_keys

    async with _jwks_lock:
        if not force_refresh and _jwks_keys and _jwks_fetched_at and (time.time() - _jwks_fetched_at < 3600):
            return _jwks_keys

        metadata = await _get_openid_metadata()
        jwks_uri = metadata.get("jwks_uri")
        if not jwks_uri:
            _raise_unauthorized("JWKS URI not available")

        jwks = await _fetch_json(jwks_uri)
        keys: Dict[str, Dict[str, Any]] = {}
        for key in jwks.get("keys", []):
            kid = key.get("kid")
            if kid:
                keys[kid] = key

        if not keys:
            _raise_unauthorized("No signing keys available")

        _jwks_keys = keys
        _jwks_fetched_at = time.time()
        return keys


def _b64url_decode(data: str) -> bytes:
    padding_len = (-len(data)) % 4
    if padding_len:
        data += "=" * padding_len
    return base64.urlsafe_b64decode(data.encode("ascii"))


def _load_public_key(key_data: Dict[str, Any]) -> rsa.RSAPublicKey:
    try:
        n_bytes = _b64url_decode(key_data["n"])
        e_bytes = _b64url_decode(key_data["e"])
        n = int.from_bytes(n_bytes, "big")
        e = int.from_bytes(e_bytes, "big")
        public_numbers = rsa.RSAPublicNumbers(e, n)
        return public_numbers.public_key()
    except Exception as exc:  # pragma: no cover - defensive
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signing key") from exc


def _decode_token(token: str) -> tuple[Dict[str, Any], Dict[str, Any], bytes, bytes]:
    try:
        header_b64, payload_b64, signature_b64 = token.split(".")
    except ValueError:
        _raise_unauthorized("Invalid token format")

    try:
        header = json.loads(_b64url_decode(header_b64))
        payload_bytes = _b64url_decode(payload_b64)
        payload = json.loads(payload_bytes)
        signature = _b64url_decode(signature_b64)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Malformed token") from exc

    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    return header, payload, signature, signing_input


def _verify_signature(public_key: rsa.RSAPublicKey, signing_input: bytes, signature: bytes) -> None:
    try:
        public_key.verify(signature, signing_input, padding.PKCS1v15(), hashes.SHA256())
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signature") from exc


def _validate_claims(payload: Dict[str, Any], *, audience: str, issuer: str | None) -> Dict[str, Any]:
    aud = payload.get("aud")
    if isinstance(aud, str):
        valid_aud = aud == audience
    elif isinstance(aud, list):
        valid_aud = audience in aud
    else:
        valid_aud = False
    if not valid_aud:
        _raise_unauthorized("Invalid audience")

    if issuer and payload.get("iss") != issuer:
        _raise_unauthorized("Invalid issuer")

    now = datetime.now(timezone.utc).timestamp()
    exp = payload.get("exp")
    if exp is None or now > float(exp):
        _raise_unauthorized("Token expired")

    nbf = payload.get("nbf")
    if nbf is not None and now < float(nbf):
        _raise_unauthorized("Token not yet valid")

    return payload


async def require_auth(request: Request) -> None:
    """Validate the Authorization header against Azure AD."""

    auth_header = request.headers.get("Authorization")
    if not auth_header:
        _raise_unauthorized()

    scheme, _, token = auth_header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        _raise_unauthorized()

    if not settings.azure_audience:
        _raise_unauthorized("Audience not configured")

    header, payload, signature, signing_input = _decode_token(token)

    kid = header.get("kid")
    if not kid:
        _raise_unauthorized("Token missing kid")

    metadata = await _get_openid_metadata()

    keys = await _load_jwks()
    key_data = keys.get(kid)
    if key_data is None:
        keys = await _load_jwks(force_refresh=True)
        key_data = keys.get(kid)
    if key_data is None:
        _raise_unauthorized("Signing key not found")

    if header.get("alg") != "RS256":
        _raise_unauthorized("Unsupported algorithm")

    public_key = _load_public_key(key_data)
    _verify_signature(public_key, signing_input, signature)

    claims = _validate_claims(payload, audience=settings.azure_audience, issuer=metadata.get("issuer"))

    request.state.user = claims


def _reset_auth_cache() -> None:
    """Utility for tests to clear cached metadata."""

    global _openid_metadata, _jwks_keys, _jwks_fetched_at
    _openid_metadata = None
    _jwks_keys = {}
    _jwks_fetched_at = None
