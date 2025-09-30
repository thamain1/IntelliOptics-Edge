# queues/servicebus.py  (drop-in replacement)

from __future__ import annotations

import json
import logging

from azure.identity.aio import DefaultAzureCredential
from azure.servicebus import ServiceBusMessage
from azure.servicebus.aio import ServiceBusClient

from ..config import settings

logger = logging.getLogger(__name__)

# ----- Internal helper ---------------------------------------------------------


async def _send_json(queue_name: str, payload: dict, *, kind: str) -> None:
    """Serialize payload to JSON and send as a single message.
    Uses a fresh client/sender per call to avoid 'handler already been shutdown'.
    Adds a 'kind' field to preserve your previous behavior.
    """
    body = json.dumps({**payload, "kind": kind}, separators=(",", ":"))

    if settings.sb_conn_str:
        # Connection string path
        async with ServiceBusClient.from_connection_string(settings.sb_conn_str) as client:
            sender = client.get_queue_sender(queue_name=queue_name)
            async with sender:
                msg = ServiceBusMessage(body)
                msg.content_type = "application/json"
                await sender.send_messages(msg)
    else:
        # AAD path
        if not settings.sb_namespace:
            raise RuntimeError("Provide SERVICE_BUS_CONN or AZ_SB_NAMESPACE")
        fqdn = f"{settings.sb_namespace}.servicebus.windows.net"
        async with DefaultAzureCredential(exclude_shared_token_cache_credential=True) as cred:
            async with ServiceBusClient(fully_qualified_namespace=fqdn, credential=cred) as client:
                sender = client.get_queue_sender(queue_name=queue_name)
                async with sender:
                    msg = ServiceBusMessage(body)
                    msg.content_type = "application/json"
                    await sender.send_messages(msg)

    logger.info("Sent ServiceBus message to %s (%d bytes, kind=%s)", queue_name, len(body), kind)


# ----- Public API --------------------------------------------------------------


async def enqueue_image_query(payload: dict) -> None:
    await _send_json(settings.sb_image_queue, payload, kind="image-query")


async def enqueue_result(payload: dict) -> None:
    await _send_json(settings.sb_results_queue, payload, kind="result")


async def enqueue_feedback(payload: dict) -> None:
    await _send_json(settings.sb_feedback_queue, payload, kind="feedback")
