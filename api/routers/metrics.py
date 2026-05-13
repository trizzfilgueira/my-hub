import os
import time

import psutil
from fastapi import APIRouter, Depends

from .auth import require_auth
from ..core.config import cfg

router = APIRouter(prefix="/api", tags=["metrics"])

# Track previous net counters for delta calculation
_prev_net: dict = {}
_prev_net_time: float = 0.0


def _get_net_rates() -> tuple[float, float]:
    global _prev_net, _prev_net_time
    now = time.monotonic()

    # Read from host proc if available
    proc_net = os.path.join(cfg.HOST_PROC, "net", "dev")
    if os.path.exists(proc_net):
        counters: dict[str, tuple[int, int]] = {}
        with open(proc_net) as f:
            for line in f:
                parts = line.split()
                if len(parts) < 10 or ":" not in parts[0]:
                    continue
                iface = parts[0].rstrip(":")
                if iface == "lo":
                    continue
                rx, tx = int(parts[1]), int(parts[9])
                counters[iface] = (rx, tx)

        total_rx = sum(v[0] for v in counters.values())
        total_tx = sum(v[1] for v in counters.values())
    else:
        net = psutil.net_io_counters()
        total_rx = net.bytes_recv
        total_tx = net.bytes_sent

    rx_mbps = tx_mbps = 0.0
    elapsed = now - _prev_net_time
    if _prev_net and elapsed > 0:
        rx_mbps = (total_rx - _prev_net.get("rx", total_rx)) / elapsed / 1_000_000
        tx_mbps = (total_tx - _prev_net.get("tx", total_tx)) / elapsed / 1_000_000
        rx_mbps = max(0.0, rx_mbps)
        tx_mbps = max(0.0, tx_mbps)

    _prev_net = {"rx": total_rx, "tx": total_tx}
    _prev_net_time = now
    return round(rx_mbps, 2), round(tx_mbps, 2)


@router.get("/metrics", dependencies=[Depends(require_auth)])
def get_metrics():
    # psutil uses HOST_PROC env var when set at import time; we also pass explicit paths
    cpu = psutil.cpu_percent(interval=0.2)
    cpu_cores = psutil.cpu_count(logical=True)

    vm = psutil.virtual_memory()
    ram_total_gb = round(vm.total / 1e9, 1)
    ram_used_gb = round(vm.used / 1e9, 1)
    ram_percent = round(vm.percent, 1)

    sw = psutil.swap_memory()
    swap_total_gb = round(sw.total / 1e9, 1)
    swap_used_gb = round(sw.used / 1e9, 1)
    swap_percent = round(sw.percent, 1)

    disk = psutil.disk_usage("/")
    disk_total_gb = round(disk.total / 1e9, 1)
    disk_used_gb = round(disk.used / 1e9, 1)
    disk_percent = round(disk.percent, 1)

    uptime_seconds = int(time.time() - psutil.boot_time())

    load = psutil.getloadavg()

    rx_mbps, tx_mbps = _get_net_rates()

    return {
        "cpu_percent": cpu,
        "cpu_cores": cpu_cores,
        "ram_used_gb": ram_used_gb,
        "ram_total_gb": ram_total_gb,
        "ram_percent": ram_percent,
        "swap_used_gb": swap_used_gb,
        "swap_total_gb": swap_total_gb,
        "swap_percent": swap_percent,
        "disk_used_gb": disk_used_gb,
        "disk_total_gb": disk_total_gb,
        "disk_percent": disk_percent,
        "uptime_seconds": uptime_seconds,
        "load_1": round(load[0], 2),
        "load_5": round(load[1], 2),
        "load_15": round(load[2], 2),
        "net_rx_mbps": rx_mbps,
        "net_tx_mbps": tx_mbps,
    }
