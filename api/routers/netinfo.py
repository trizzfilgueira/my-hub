import subprocess
from pathlib import Path

from fastapi import APIRouter, Depends

from .auth import require_auth

router = APIRouter(prefix="/api", tags=["netinfo"])

SCRIPTS_DIR = Path("/app/scripts")


def _parse_kv(output: str) -> dict[str, str]:
    kv = {}
    for line in output.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            kv[k.strip()] = v.strip()
    return kv


@router.get("/netinfo", dependencies=[Depends(require_auth)])
def get_netinfo():
    try:
        result = subprocess.run(
            ["bash", str(SCRIPTS_DIR / "netinfo.sh")],
            capture_output=True, text=True, timeout=15
        )
        kv = _parse_kv(result.stdout)
        return {
            "pub_ip":      kv.get("PUB_IP", "N/A"),
            "iface":       kv.get("IFACE", "N/A"),
            "ssh_active":  kv.get("SSH_ACTIVE", "false") == "true",
            "firewall":    kv.get("FIREWALL", "inativo"),
            "fail2ban":    kv.get("FAIL2BAN", "inativo"),
        }
    except Exception:
        return {
            "pub_ip": "N/A", "iface": "N/A",
            "ssh_active": False, "firewall": "N/A", "fail2ban": "N/A",
        }
