from fastapi import APIRouter
from pydantic import BaseModel
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
import os, json, threading, pathlib, time

router = APIRouter(prefix="/v1", tags=["labels"])

LABELS_PATH = os.getenv("IO_LABELS_PATH", "data/labels.jsonl")
_lock = threading.Lock()
pathlib.Path(os.path.dirname(LABELS_PATH) or ".").mkdir(parents=True, exist_ok=True)

class LabelIn(BaseModel):
    image_query_id: str
    label: str
    confidence: Optional[float] = None
    detector_id: Optional[str] = None
    user_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

class LabelOut(LabelIn):
    id: str
    ts: str

@router.post("/labels", response_model=LabelOut)
def create_label(body: LabelIn) -> LabelOut:
    ts = datetime.now(timezone.utc).isoformat()
    rec = {
        "id": f"lbl_{int(time.time()*1000)}",
        "ts": ts,
        **body.model_dump(),
    }
    os.makedirs(os.path.dirname(LABELS_PATH) or ".", exist_ok=True)
    with _lock, open(LABELS_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
    return rec  # type: ignore[return-value]

@router.get("/labels")
def list_labels(limit: int = 100, offset: int = 0):
    items: List[Dict[str, Any]] = []
    if os.path.exists(LABELS_PATH):
        with open(LABELS_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        items.append(json.loads(line))
                    except Exception:
                        pass
    total = len(items)
    return {"items": items[offset:offset+limit], "total": total}
