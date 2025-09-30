# app/storage/blob.py
from __future__ import annotations

import logging
import mimetypes
import os
import re
from contextlib import suppress
from dataclasses import dataclass
from typing import Optional
from uuid import uuid4

from azure.storage.blob import ContainerClient, ContentSettings
from fastapi import UploadFile

logger = logging.getLogger(__name__)

# Prefer common extensions
MIME_TO_EXT = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/bmp": "bmp",
    "image/tiff": "tif",
    "image/x-icon": "ico",
    "image/heic": "heic",
    "image/heif": "heif",
}

SAFE_NAME_RE = re.compile(r"[^a-zA-Z0-9_.-]")


@dataclass
class BlobRef:
    container: str
    name: str  # path within container
    url: str  # full HTTPS URL
    content_type: str
    size: int


def _ext_from_mime(mime: Optional[str]) -> str:
    if not mime:
        return "bin"
    ext = MIME_TO_EXT.get(mime)
    if ext:
        return ext
    guessed = mimetypes.guess_extension(mime, strict=False)
    if guessed:
        return guessed.lstrip(".")
    if "/" in mime:
        sub = SAFE_NAME_RE.sub("", mime.split("/")[-1])
        if sub:
            return sub[:8]
    return "bin"


def _safe_basename() -> str:
    return uuid4().hex


def make_blob_name(content_type: Optional[str], *, prefix: str = "image-queries") -> str:
    """Return a safe blob name like 'image-queries/2f1a...e9.png'."""
    ext = _ext_from_mime(content_type)
    base = _safe_basename()
    prefix_clean = SAFE_NAME_RE.sub("-", (prefix or "").strip("/"))
    return f"{prefix_clean}/{base}.{ext}" if prefix_clean else f"{base}.{ext}"


def get_container(name: str, *, connection_string: Optional[str] = None) -> ContainerClient:
    """Resolve a ContainerClient using provided or env connection string."""
    conn = connection_string or os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
    if not conn:
        raise RuntimeError("AZURE_STORAGE_CONNECTION_STRING is not set")
    return ContainerClient.from_connection_string(conn, name)


def upload_image_bytes(
    container_client: ContainerClient,
    data: bytes,
    *,
    content_type: Optional[str],
    prefix: str = "image-queries",
) -> BlobRef:
    """Upload raw image bytes with a safe name and content settings."""
    if not isinstance(data, (bytes, bytearray)):
        raise TypeError(f"data must be bytes, got {type(data)}")

    ct = content_type or "application/octet-stream"
    name = make_blob_name(ct, prefix=prefix)
    blob = container_client.get_blob_client(name)
    size = len(data)

    logger.info(
        "Uploading blob name=%s size=%dB content_type=%s container=%s",
        name,
        size,
        ct,
        container_client.container_name,
    )

    blob.upload_blob(
        data,
        overwrite=True,
        length=size,
        content_settings=ContentSettings(content_type=ct),
    )

    return BlobRef(
        container=container_client.container_name,
        name=name,
        url=blob.url,
        content_type=ct,
        size=size,
    )


# ------------------ Replaced upload_starlette_file with requested version ------------------


def _basename_no_path(name: str) -> str:
    name = (name or "").split("/")[-1].split("\\")[-1]
    return name or "upload.bin"


def _safe_stem(stem: str) -> str:
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-")
    return (stem or "file")[:80]


async def upload_starlette_file(container_client, upload: UploadFile, prefix: str = "") -> BlobRef:
    """
    Upload UploadFile to Azure Blob without assuming any headers or keys exist.
    Returns BlobRef(container, name, url, size, content_type).
    """
    original = _basename_no_path(getattr(upload, "filename", "") or "upload.bin")
    stem, ext = os.path.splitext(original)

    # Resolve content type with safe fallbacks
    guessed_type, _ = mimetypes.guess_type(original)
    content_type = getattr(upload, "content_type", None) or guessed_type or "application/octet-stream"

    # Ensure extension if missing
    if not ext:
        with suppress(Exception):
            ext = mimetypes.guess_extension(content_type) or ""
    ext = (ext or "").lower()

    safe_name = f"{_safe_stem(stem)}-{uuid4().hex}{ext}"
    blob_name = f"{prefix.strip('/')}/{safe_name}" if prefix else safe_name

    # Read bytes (don’t rely on stream state)
    with suppress(Exception):
        await upload.seek(0)
    with suppress(Exception):
        upload.file.seek(0)
    data = await upload.read()  # bytes

    # Upload
    blob = container_client.get_blob_client(blob=blob_name)
    blob.upload_blob(
        data,
        overwrite=True,
        content_settings=ContentSettings(content_type=content_type),
    )

    size = len(data)
    return BlobRef(
        container=container_client.container_name,
        name=blob_name,
        url=blob.url,
        size=size,
        content_type=content_type,
    )
