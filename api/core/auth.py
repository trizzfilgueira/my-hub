from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
from jose import JWTError, jwt

from .config import cfg


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode(), hashed.encode())
    except Exception:
        return False


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt(rounds=12)).decode()


def create_token(payload_extra: Optional[dict] = None) -> tuple[str, datetime]:
    expires_at = datetime.now(timezone.utc) + timedelta(days=cfg.JWT_EXPIRE_DAYS)
    payload = {
        "sub": "hub-user",
        "exp": expires_at,
        "iat": datetime.now(timezone.utc),
        # Include a fingerprint of the current password hash so tokens are
        # automatically invalidated when `vm-hub reset-pwd` changes the hash.
        "pwfp": cfg.HUB_PASSWORD_HASH[-8:] if cfg.HUB_PASSWORD_HASH else "",
    }
    if payload_extra:
        payload.update(payload_extra)
    token = jwt.encode(payload, cfg.HUB_TOKEN, algorithm=cfg.JWT_ALGORITHM)
    return token, expires_at


def decode_token(token: str) -> dict:
    """Raises JWTError on any validation failure."""
    payload = jwt.decode(token, cfg.HUB_TOKEN, algorithms=[cfg.JWT_ALGORITHM])
    # Validate password fingerprint — invalidates tokens after reset-pwd
    current_fp = cfg.HUB_PASSWORD_HASH[-8:] if cfg.HUB_PASSWORD_HASH else ""
    if payload.get("pwfp", "") != current_fp:
        raise JWTError("Token invalidated by password reset")
    return payload
