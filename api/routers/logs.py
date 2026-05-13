import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock

from fastapi import APIRouter, Depends

from .auth import require_auth

router = APIRouter(prefix="/api", tags=["logs"])

LOG_FILE = Path("/app/data/hub.log")
_lock = Lock()
_buffer: deque = deque(maxlen=200)
_loaded = False


def _ensure_loaded():
    global _loaded
    if _loaded:
        return
    if LOG_FILE.exists():
        try:
            lines = LOG_FILE.read_text().splitlines()
            for line in lines[-200:]:
                try:
                    _buffer.append(json.loads(line))
                except Exception:
                    pass
        except Exception:
            pass
    _loaded = True


def add_log(level: str, message: str) -> None:
    entry = {
        "time": datetime.now(timezone.utc).strftime("%H:%M"),
        "level": level.upper(),
        "message": message,
    }
    with _lock:
        _ensure_loaded()
        _buffer.append(entry)
        try:
            LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
            with LOG_FILE.open("a") as f:
                f.write(json.dumps(entry) + "\n")
        except Exception:
            pass


@router.get("/logs", dependencies=[Depends(require_auth)])
def get_logs(limit: int = 50):
    with _lock:
        _ensure_loaded()
        entries = list(_buffer)
    return entries[-limit:]
