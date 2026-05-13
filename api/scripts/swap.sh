#!/bin/bash
# Reset de swap — executa no host via nsenter (pid:host + privileged)

NSE="nsenter -t 1 -m -u -i -n --"

# Swap usado antes (lê /host/proc/meminfo)
TOTAL_KB=$(awk '/SwapTotal:/ {print $2}' /host/proc/meminfo 2>/dev/null || echo "0")
FREE_KB=$(awk '/SwapFree:/ {print $2}' /host/proc/meminfo 2>/dev/null || echo "0")
SWAP_BEFORE_MB=$(( (TOTAL_KB - FREE_KB) / 1024 ))

# Reset no host
${NSE} swapoff -a 2>/dev/null || true
sleep 1
${NSE} swapon -a 2>/dev/null || true
sleep 1

# Swap usado depois
FREE_AFTER_KB=$(awk '/SwapFree:/ {print $2}' /host/proc/meminfo 2>/dev/null || echo "0")
SWAP_AFTER_MB=$(( (TOTAL_KB - FREE_AFTER_KB) / 1024 ))

echo "SWAP_BEFORE_MB=$SWAP_BEFORE_MB"
echo "SWAP_AFTER_MB=$SWAP_AFTER_MB"
