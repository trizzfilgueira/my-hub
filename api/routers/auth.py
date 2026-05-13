from collections import defaultdict
from datetime import datetime, timezone
from time import time

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from pydantic import BaseModel

from ..core.auth import create_token, decode_token, verify_password
from ..core.config import cfg

router = APIRouter(prefix="/api/auth", tags=["auth"])
bearer = HTTPBearer(auto_error=False)

# Simple in-process rate limiter: max 5 attempts/IP/minute
_attempts: dict[str, list[float]] = defaultdict(list)
_RATE_WINDOW = 60.0
_RATE_MAX = 5


def _check_rate(ip: str) -> None:
    now = time()
    window = _attempts[ip]
    _attempts[ip] = [t for t in window if now - t < _RATE_WINDOW]
    if len(_attempts[ip]) >= _RATE_MAX:
        raise HTTPException(status_code=429, detail="Muitas tentativas. Aguarde 1 minuto.")
    _attempts[ip].append(now)


class LoginBody(BaseModel):
    password: str


@router.post("/login")
def login(body: LoginBody, request: Request):
    ip = request.client.host if request.client else "unknown"
    _check_rate(ip)

    if not cfg.HUB_PASSWORD_HASH:
        raise HTTPException(status_code=503, detail="Hub não configurado. Execute o instalador.")

    if not verify_password(body.password, cfg.HUB_PASSWORD_HASH):
        raise HTTPException(status_code=401, detail="Senha incorreta")

    token, expires_at = create_token()
    return {
        "token": token,
        "expires_at": expires_at.isoformat(),
        "hub_name": cfg.HUB_NAME,
    }


@router.get("/verify")
def verify(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    if not credentials:
        raise HTTPException(status_code=401, detail="Token ausente")
    try:
        payload = decode_token(credentials.credentials)
        exp = payload.get("exp")
        expires_at = datetime.fromtimestamp(exp, tz=timezone.utc).isoformat() if exp else None
        return {"valid": True, "expires_at": expires_at}
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido ou expirado")


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    """Dependency — use in protected routes."""
    if not credentials:
        raise HTTPException(status_code=401, detail="Token ausente")
    try:
        decode_token(credentials.credentials)
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido ou expirado")
