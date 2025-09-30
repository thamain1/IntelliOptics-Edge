from __future__ import annotations

import base64
import json
import pathlib
import sys
from datetime import datetime, timedelta, timezone

import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from fastapi import Depends, FastAPI, Request
from fastapi.testclient import TestClient

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend" / "api"))

from app import auth as auth_module
from app.auth import require_auth
from app.config import settings


def _b64url(value: int) -> str:
    raw = value.to_bytes((value.bit_length() + 7) // 8, "big")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


@pytest.fixture()
def rsa_key() -> rsa.RSAPrivateKey:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture(autouse=True)
def configure_settings():
    original = settings.model_dump()
    auth_module._reset_auth_cache()
    yield
    auth_module._reset_auth_cache()
    for field, value in original.items():
        setattr(settings, field, value)


def _setup_auth(monkeypatch: pytest.MonkeyPatch, rsa_key: rsa.RSAPrivateKey, kid: str = "test-kid") -> str:
    public_numbers = rsa_key.public_key().public_numbers()
    jwk = {
        "kty": "RSA",
        "kid": kid,
        "use": "sig",
        "n": _b64url(public_numbers.n),
        "e": _b64url(public_numbers.e),
        "alg": "RS256",
    }

    issuer = "https://login.microsoftonline.com/test-tenant/v2.0"
    jwks_uri = "https://example.com/tenant/keys"
    metadata = {
        "issuer": issuer,
        "jwks_uri": jwks_uri,
        "id_token_signing_alg_values_supported": ["RS256"],
    }
    jwks = {"keys": [jwk]}

    settings.azure_openid_config = "https://example.com/.well-known/openid-configuration"
    settings.azure_audience = "test-audience"
    settings.azure_tenant_id = "test-tenant"

    async def fake_fetch(url: str):
        if url == settings.azure_openid_config:
            return metadata
        if url == jwks_uri:
            return jwks
        raise AssertionError(f"Unexpected URL {url}")

    monkeypatch.setattr(auth_module, "_fetch_json", fake_fetch)
    auth_module._reset_auth_cache()
    return issuer


def _b64url_bytes(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _make_token(
    rsa_key: rsa.RSAPrivateKey, issuer: str, *, audience: str, kid: str = "test-kid", subject: str = "user-123"
) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "aud": audience,
        "iss": issuer,
        "sub": subject,
        "iat": int(now.timestamp()),
        "nbf": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=5)).timestamp()),
    }
    header = {"alg": "RS256", "typ": "JWT", "kid": kid}
    header_b64 = _b64url_bytes(json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    payload_b64 = _b64url_bytes(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    signature = rsa_key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
    token = f"{header_b64}.{payload_b64}.{_b64url_bytes(signature)}"
    return token


def _make_client():
    app = FastAPI()

    @app.get("/secure")
    async def secure(request: Request, _: None = Depends(require_auth)):
        return {"subject": request.state.user["sub"]}

    return TestClient(app)


def test_require_auth_allows_valid_token(monkeypatch: pytest.MonkeyPatch, rsa_key: rsa.RSAPrivateKey):
    issuer = _setup_auth(monkeypatch, rsa_key)
    token = _make_token(rsa_key, issuer, audience=settings.azure_audience)
    client = _make_client()

    response = client.get("/secure", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json() == {"subject": "user-123"}


def test_require_auth_rejects_invalid_token(monkeypatch: pytest.MonkeyPatch, rsa_key: rsa.RSAPrivateKey):
    issuer = _setup_auth(monkeypatch, rsa_key)
    bad_token = _make_token(rsa_key, issuer, audience="wrong-audience")
    client = _make_client()

    response = client.get("/secure", headers={"Authorization": f"Bearer {bad_token}"})
    assert response.status_code == 401
