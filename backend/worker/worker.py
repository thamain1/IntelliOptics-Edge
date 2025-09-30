import json
import logging
import os
import sys
import time
from typing import Any, Dict

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from db import SessionLocal, engine
from intellioptics import IntelliOptics
from models import Base, ImageQueryRow

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("worker-shim")

NS = os.getenv("AZ_SB_NAMESPACE")
CONN = os.getenv("SERVICE_BUS_CONN") or os.getenv("AZ_SB_CONN_STR")
QUEUE_IN = os.getenv("SB_QUEUE_LISTEN", "image-queries")
QUEUE_OUT = os.getenv("SB_QUEUE_SEND", "inference-results")

DEFAULT_CONFIDENCE = float(os.getenv("DEFAULT_CONFIDENCE", 0.9))
DEFAULT_TIMEOUT = float(os.getenv("DEFAULT_TIMEOUT", 30))

IO_TOKEN = os.getenv("INTELLIOPTICS_API_TOKEN") or os.getenv("INTELLOPTICS_API_TOKEN")
IO_ENDPOINT = os.getenv("INTELLIOPTICS_ENDPOINT") or os.getenv("INTELLOPTICS_API_BASE") or None

if not IO_TOKEN:
    log.error("INTELLIOPTICS_API_TOKEN is required")
    sys.exit(2)

cred = DefaultAzureCredential(exclude_shared_token_cache_credential=True)
if CONN:
    sb = ServiceBusClient.from_connection_string(CONN)
else:
    if not NS:
        log.error("Provide AZ_SB_NAMESPACE or SERVICE_BUS_CONN")
        sys.exit(2)
    sb = ServiceBusClient(fully_qualified_namespace=f"{NS}.servicebus.windows.net", credential=cred)

io = IntelliOptics(endpoint=IO_ENDPOINT, api_token=IO_TOKEN)
Base.metadata.create_all(bind=engine)


def _ensure_dict(msg_body: Any) -> Dict[str, Any]:
    if isinstance(msg_body, (bytes, bytearray)):
        msg_body = msg_body.decode("utf-8")
    if isinstance(msg_body, str):
        return json.loads(msg_body)
    if isinstance(msg_body, dict):
        return msg_body
    raise ValueError("Unsupported message body type")


def process_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    if payload.get("kind") != "image-query":
        return {"skipped": True, "reason": f"unknown kind: {payload.get('kind')}"}

    det = payload["detector_id"]
    blob_url = payload["blob_url"]
    conf = float(payload.get("confidence_threshold", DEFAULT_CONFIDENCE))
    timeout = float(payload.get("timeout", DEFAULT_TIMEOUT))
    metadata = payload.get("metadata")

    iq = io.ask_async(detector=det, image=blob_url, metadata=metadata)
    iq = io.wait_for_confident_result(image_query=iq, confidence_threshold=conf, timeout_sec=timeout)

    r = getattr(iq, "result", None)
    count_val = None
    if r is not None:
        if getattr(iq, "result_type", None) == "COUNT":
            count_val = getattr(r, "count", None) or getattr(r, "value", None)
        try:
            extra = {k: v for k, v in r.__dict__.items() if k not in {"label", "confidence", "count", "value"}}
        except Exception:
            extra = None
    else:
        extra = None

    return {
        "image_query_id": iq.id,
        "status": "DONE" if getattr(iq, "done_processing", False) else "PROCESSING",
        "label": r.label if r else None,
        "confidence": r.confidence if r else None,
        "result_type": getattr(iq, "result_type", None),
        "count": count_val,
        "extra": extra,
        "detector_id": det,
        "blob_url": blob_url,
        "done_processing": bool(getattr(iq, "done_processing", False)),
        "metadata": metadata,
    }


def write_result_db(res: Dict[str, Any]):
    with SessionLocal() as db:  # type: Session
        row = db.get(ImageQueryRow, res["image_query_id"]) or ImageQueryRow(
            id=res["image_query_id"], detector_id=res["detector_id"], blob_url=res["blob_url"]
        )
        row.status = res["status"]
        row.label = res.get("label")
        row.confidence = res.get("confidence")
        row.result_type = res.get("result_type")
        row.count = res.get("count")
        row.extra = res.get("extra")
        row.done_processing = res.get("done_processing", False)
        db.add(row)
        db.commit()


def send_result_queue(res: Dict[str, Any]):
    with sb.get_queue_sender(QUEUE_OUT) as sender:
        sender.send_messages(ServiceBusMessage(json.dumps({"kind": "result", **res})))


def run():
    log.info("Listening on '%s'", QUEUE_IN)
    with sb.get_queue_receiver(QUEUE_IN, max_wait_time=5) as receiver:
        for msg in receiver:
            try:
                payload = _ensure_dict(msg.body)
                res = process_payload(payload)
                if res.get("skipped"):
                    log.info("Skipping: %s", res["reason"])
                else:
                    try:
                        write_result_db(res)
                    except Exception as db_err:
                        log.warning("DB unavailable (%s). Sending to results queue.", db_err)
                        send_result_queue(res)
                receiver.complete_message(msg)
            except Exception as e:
                log.exception("Processing failed: %s", e)
                receiver.abandon_message(msg)
                time.sleep(1)


if __name__ == "__main__":
    run()
