# backend/api/app/routers/image_queries.py
from __future__ import annotations

import json
import os
import time
import uuid
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, HttpUrl

# Azure Service Bus (SDK)
try:
    from azure.servicebus import ServiceBusClient, ServiceBusMessage, ServiceBusReceiveMode  # type: ignore
except Exception as e:  # pragma: no cover
    raise RuntimeError("azure-servicebus is required. Install with: pip install azure-servicebus") from e


router = APIRouter(prefix="/v1/image-queries", tags=["image-queries"])


class CreateImageQuery(BaseModel):
    blob_url: HttpUrl
    detector_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class EnqueuedResponse(BaseModel):
    image_query_id: str
    blob_url: HttpUrl
    queued: bool = True


class ResultEnvelope(BaseModel):
    image_query_id: str
    ok: bool
    result: Dict[str, Any]


def _get_sb_in() -> tuple[str, str]:
    conn = os.getenv("SERVICE_BUS_CONN")
    if not conn:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="SERVICE_BUS_CONN not configured on API",
        )
    queue_in = os.getenv("QUEUE_IN", "image-queries")
    return conn, queue_in


def _get_sb_out() -> tuple[str, str]:
    conn = os.getenv("SERVICE_BUS_CONN")
    if not conn:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="SERVICE_BUS_CONN not configured on API",
        )
    queue_out = os.getenv("QUEUE_OUT", "inference-results")
    return conn, queue_out


@router.post("", response_model=EnqueuedResponse, status_code=status.HTTP_202_ACCEPTED)
def create_image_query(body: CreateImageQuery) -> EnqueuedResponse:
    """
    Enqueue an image query for the inference worker.

    Payload placed on SB queue (JSON):
        {"image_query_id": "<uuid4>", "blob_url": "<url>"}
    """
    image_query_id = str(uuid.uuid4())
    payload = {"image_query_id": image_query_id, "blob_url": str(body.blob_url)}

    conn, queue_name = _get_sb_in()

    try:
        with ServiceBusClient.from_connection_string(conn) as sb:
            with sb.get_queue_sender(queue_name=queue_name) as sender:
                sender.send_messages(ServiceBusMessage(json.dumps(payload)))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to publish to Service Bus: {e}",
        )

    return EnqueuedResponse(image_query_id=image_query_id, blob_url=body.blob_url)


@router.get("/{iq_id}/wait", response_model=ResultEnvelope)
def wait_for_result(
    iq_id: str,
    timeout_s: int = Query(15, ge=1, le=120, description="Total seconds to wait"),
) -> ResultEnvelope:
    """
    Wait (up to timeout_s) for the result message with matching image_query_id
    from the OUT queue. Uses PEEK_LOCK; only completes (deletes) the *matched*
    message. Non-matching messages are abandoned immediately.
    """
    conn, queue_out = _get_sb_out()

    deadline = time.time() + float(timeout_s)
    try:
        with ServiceBusClient.from_connection_string(conn) as sb:
            # PEEK_LOCK so we don't eat unrelated messages
            receiver = sb.get_queue_receiver(
                queue_name=queue_out,
                receive_mode=ServiceBusReceiveMode.PEEK_LOCK,
                max_wait_time=5,
            )
            with receiver:
                while time.time() < deadline:
                    msgs = receiver.receive_messages(max_message_count=10)
                    if not msgs:
                        continue
                    for m in msgs:
                        try:
                            body = b"".join([b for b in m.body]) if hasattr(m, "body") else m
                            text = (
                                body.decode("utf-8", "replace") if isinstance(body, (bytes, bytearray)) else str(body)
                            )
                            j = json.loads(text)
                        except Exception:
                            # Can't parse; abandon and continue
                            try:
                                receiver.abandon_message(m)
                            except Exception:
                                pass
                            continue

                        mid = j.get("image_query_id")
                        if mid == iq_id:
                            # Matched: complete (delete) and return
                            try:
                                receiver.complete_message(m)
                            except Exception:
                                pass
                            ok = bool(j.get("ok", False))
                            result = j.get("result") or {}
                            return ResultEnvelope(image_query_id=mid, ok=ok, result=result)
                        else:
                            # Not ours: immediately abandon
                            try:
                                receiver.abandon_message(m)
                            except Exception:
                                pass

        raise HTTPException(
            status_code=status.HTTP_408_REQUEST_TIMEOUT,
            detail=f"Timed out waiting for result for {iq_id}",
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed while reading results queue: {e}",
        )
