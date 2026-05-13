import json
from pathlib import Path

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .auth import require_auth

router = APIRouter(prefix="/api", tags=["user-config"])

DATA_FILE = Path("/app/data/user_config.json")

_DEFAULT: dict = {
    "links": [],
    "containers": {},
}


def load_user_config() -> dict:
    if DATA_FILE.exists():
        try:
            return json.loads(DATA_FILE.read_text())
        except Exception:
            pass
    return dict(_DEFAULT)


def save_user_config(data: dict) -> None:
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    DATA_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2))


@router.get("/user-config", dependencies=[Depends(require_auth)])
def get_config():
    return load_user_config()


class UserConfigBody(BaseModel):
    links: list | None = None
    containers: dict | None = None


@router.put("/user-config", dependencies=[Depends(require_auth)])
def put_config(body: UserConfigBody):
    data = load_user_config()
    if body.links is not None:
        data["links"] = body.links
    if body.containers is not None:
        data["containers"] = body.containers
    save_user_config(data)
    return {"ok": True}
