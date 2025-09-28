# app/azure_io.py
import os
import json
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings
from azure.servicebus import ServiceBusClient, ServiceBusMessage

from .config import settings

# --- DEV ONLY: hard-wired SAS for sending to image-queries ---
# Using your provided key and scoping to EntityPath=image-queries.
# This bypasses env so the API always uses this during dev.
_DEV_SB_CONN_SEND_IQ = (
    "Endpoint=sb://sb-intellioptics.servicebus.windows.net/;"
    "SharedAccessKeyName=listen-worker;"
    "SharedAccessKey=3QvNhweL2/wbZ/RTtqNgonnDIXBeOwQgk+ASbDr57c4=;"
    "EntityPath=image-queries"
)


def _ensure_fqdn(ns: str) -> str:
    ns = (ns or "").strip()
    return ns if (not ns or "." in ns) else f"{ns}.servicebus.windows.net"


# ---------------- Blob helpers ----------------
def _blob_service_client() -> BlobServiceClient:
    """
    Prefer connection string; fall back to account URL + DefaultAzureCredential.
    """
    conn = (
        os.getenv("AZURE_STORAGE_CONNECTION_STRING")
        or os.getenv("AZ_BLOB_CONN_STR")
        or os.getenv("AZURE_STORAGE_CONN_STR")
    )
    account_url = os.getenv("AZURE_STORAGE_ACCOUNT_URL")  # e.g. https://<acct>.blob.core.windows.net
    if conn:
        return BlobServiceClient.from_connection_string(conn)
    if account_url:
        cred = DefaultAzureCredential(exclude_interactive_browser_credential=False)
        return BlobServiceClient(account_url=account_url, credential=cred)
    raise RuntimeError("Provide AZURE_STORAGE_CONNECTION_STRING (or AZ_BLOB_CONN_STR) or AZURE_STORAGE_ACCOUNT_URL")


def upload_bytes(container: str, blob_name: str, data: bytes, content_type: str = "application/octet-stream") -> str:
    """
    Upload bytes to Azure Blob and return the blob URL.
    (main.py will handle fallback if this raises)
    """
    svc = _blob_service_client()
    cc = svc.get_container_client(container)
    try:
        cc.create_container()
    except Exception:
        pass
    bc = cc.get_blob_client(blob_name)
    bc.upload_blob(
        data,
        overwrite=True,
        content_settings=ContentSettings(content_type=content_type or "application/octet-stream"),
    )
    return bc.url


# ---------------- Service Bus (SEND) ----------------
def _sb_client_for_send() -> ServiceBusClient:
    """Create a ServiceBusClient for sending messages using configured credentials."""
    if settings.sb_conn_str:
        return ServiceBusClient.from_connection_string(settings.sb_conn_str)

    if settings.sb_namespace:
        fqdn = _ensure_fqdn(settings.sb_namespace)
        credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)
        return ServiceBusClient(fully_qualified_namespace=fqdn, credential=credential)

    if settings.sb_use_dev_send_override:
        return ServiceBusClient.from_connection_string(_DEV_SB_CONN_SEND_IQ)

    raise RuntimeError(
        "Provide AZ_SB_CONN_STR/SERVICE_BUS_CONN or AZ_SB_NAMESPACE (or enable SB_USE_DEV_SEND_OVERRIDE)"
    )


def send_sb_message(
    queue_name: str,
    payload: dict,
    *,
    subject: Optional[str] = None,
    message_id: Optional[str] = None,
) -> None:
    sb = _sb_client_for_send()
    with sb, sb.get_queue_sender(queue_name=queue_name) as sender:
        msg = ServiceBusMessage(
            json.dumps(payload),
            content_type="application/json",
            subject=subject,
            message_id=message_id,
        )
        sender.send_messages(msg)
