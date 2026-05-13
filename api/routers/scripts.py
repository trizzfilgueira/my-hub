import json
import re
import subprocess
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException

from .auth import require_auth
from .logs import add_log

router = APIRouter(prefix="/api/scripts", tags=["scripts"])

SCRIPTS_DIR = Path("/app/scripts")
SNIPPETS_FILE = SCRIPTS_DIR / "snippets.json"
DEFAULT_TIMEOUT = 30
SPEEDTEST_TIMEOUT = 120


def _run(script: str, timeout: int = DEFAULT_TIMEOUT) -> str:
    path = SCRIPTS_DIR / script
    if not path.exists():
        raise HTTPException(status_code=500, detail=f"Script '{script}' não encontrado")
    try:
        result = subprocess.run(
            ["bash", str(path)],
            capture_output=True, text=True, timeout=timeout
        )
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao executar '{script}': {e}")


def _parse_kv(output: str) -> dict[str, str]:
    """Parse KEY=VALUE lines from script output."""
    kv = {}
    for line in output.splitlines():
        m = re.match(r"^([A-Z_]+)=(.*)$", line.strip())
        if m:
            kv[m.group(1)] = m.group(2).strip()
    return kv


@router.get("", dependencies=[Depends(require_auth)])
def list_snippets():
    """Retorna a lista de snippets de manutenção configurados em snippets.json."""
    if not SNIPPETS_FILE.exists():
        return []
    try:
        return json.loads(SNIPPETS_FILE.read_text(encoding="utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="Erro ao ler snippets.json")


@router.post("/run/{script_id}", dependencies=[Depends(require_auth)])
def run_snippet(script_id: str):
    """Executa qualquer snippet registrado em snippets.json e retorna a saída bruta."""
    if not SNIPPETS_FILE.exists():
        raise HTTPException(status_code=404, detail="snippets.json não encontrado")
    try:
        snippets = json.loads(SNIPPETS_FILE.read_text(encoding="utf-8"))
    except Exception:
        raise HTTPException(status_code=500, detail="Erro ao ler snippets.json")

    snippet = next((s for s in snippets if s["id"] == script_id), None)
    if not snippet:
        raise HTTPException(status_code=404, detail=f"Snippet '{script_id}' não encontrado")

    try:
        out = _run(snippet["script"])
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail=f"Timeout ao executar '{script_id}'")

    add_log("OK", f"Snippet '{snippet['title']}' executado")
    return {"ok": True, "output": out}


@router.post("/limpeza", dependencies=[Depends(require_auth)])
def run_limpeza():
    try:
        out = _run("limpeza.sh")
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Timeout ao executar limpeza")

    kv = _parse_kv(out)
    steps = [
        {"label": "Cache da RAM esvaziado",        "ok": kv.get("CACHE_OK",   "false") == "true"},
        {"label": "Logs antigos removidos (7 dias)", "ok": kv.get("JOURNAL_OK","false") == "true"},
        {"label": "Cache do APT limpo",              "ok": kv.get("APT_OK",    "false") == "true"},
        {"label": "Imagens Docker removidas",        "ok": kv.get("DOCKER_OK", "false") == "true"},
    ]
    result = {
        "ok": True,
        "steps": steps,
        "stats": {
            "ram_cache":    kv.get("RAM_CACHE",    "N/A"),
            "disk_free":    kv.get("DISK_FREE",    "N/A"),
            "docker_waste": kv.get("DOCKER_WASTE", "N/A"),
        },
    }
    add_log("OK", "Limpeza executada com sucesso")
    return result


@router.post("/seguranca", dependencies=[Depends(require_auth)])
def run_seguranca():
    try:
        out = _run("seguranca.sh")
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Timeout ao executar verificação de segurança")

    kv = _parse_kv(out)
    result = {
        "ok": True,
        "updates_pending":  int(kv.get("UPDATES",  "0") or "0"),
        "security_updates": int(kv.get("SECURITY", "0") or "0"),
        "reboot_required":  kv.get("REBOOT", "false").lower() == "true",
        "ssh_active":       kv.get("SSH", "inactive") == "active",
    }
    add_log("OK", f"Segurança verificada — {result['updates_pending']} updates pendentes")
    return result


@router.post("/swap", dependencies=[Depends(require_auth)])
def run_swap():
    try:
        out = _run("swap.sh")
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Timeout ao executar reset de swap")

    kv = _parse_kv(out)
    result = {
        "ok": True,
        "swap_before_mb": int(kv.get("SWAP_BEFORE_MB", "0") or "0"),
        "swap_after_mb":  int(kv.get("SWAP_AFTER_MB",  "0") or "0"),
    }
    add_log("OK", f"Swap resetado — antes: {result['swap_before_mb']} MB, depois: {result['swap_after_mb']} MB")
    return result


@router.post("/speedtest", dependencies=[Depends(require_auth)])
def run_speedtest():
    try:
        out = _run("speedtest.sh", timeout=SPEEDTEST_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Timeout no speedtest (>60s)")

    kv = _parse_kv(out)
    dl = round(float(kv.get("DL_MBPS", "0") or "0"), 1)
    ul = round(float(kv.get("UL_MBPS", "0") or "0"), 1)
    result = {"ok": True, "dl_mbps": dl, "ul_mbps": ul}
    add_log("OK", f"Speedtest: ↓{dl} Mbps / ↑{ul} Mbps")
    return result
