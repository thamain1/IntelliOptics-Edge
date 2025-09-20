# backend/api/app/azure_blob.py
from __future__ import annotations
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from azure.storage.blob import (
    BlobServiceClient,
    ContentSettings,
    BlobSasPermissions,
    generate_blob_sas,
)

_ACCOUNT_CONN_STR_ENV = "AZURE_STORAGE_CONNECTION_STRING"
_CONTAINER_ENV = "AZ_BLOB_CONTAINER"

class AzureBlobClient:
    def __init__(self, connection_string: Optional[str] = None, container_name: Optional[str] = None):
        self.connection_string = connection_string or os.getenv(_ACCOUNT_CONN_STR_ENV)
        self.container_name = container_name or os.getenv(_CONTAINER_ENV, "images")
        if not self.connection_string:
            raise RuntimeError(f"Missing {_ACCOUNT_CONN_STR_ENV}")
        self._svc = BlobServiceClient.from_connection_string(self.connection_string)
        self._container = self._svc.get_container_client(self.container_name)

    def ensure_container(self, public_access: bool = False):
        try:
            self._container.create_container(public_access="blob" if public_access else None)
        except Exception:
            # Already exists is fine
            pass

    def upload_bytes_with_sas(
        self,
        blob_path: str,
        data: bytes,
        content_type: str = "image/jpeg",
        expires_in_hours: int = 24,
    ) -> str:
        """
        Uploads bytes to 'blob_path' and returns a time-limited SAS URL.
        """
        # Upload
        blob = self._container.get_blob_client(blob_path)
        blob.upload_blob(
            data,
            overwrite=True,
            content_settings=ContentSettings(content_type=content_type),
        )

        # SAS
        # Parse account & container info for SAS generation
        account_name = self._svc.account_name
        # Expiry
        expiry = datetime.now(timezone.utc) + timedelta(hours=expires_in_hours)
        sas = generate_blob_sas(
            account_name=account_name,
            container_name=self.container_name,
            blob_name=blob_path,
            account_key=self._svc.credential.account_key,  # present when using connection string
            permission=BlobSasPermissions(read=True),
            expiry=expiry,
        )
        # Build URL
        base_url = blob.url
        return f"{base_url}?{sas}"
