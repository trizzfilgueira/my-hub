#!/bin/bash
# Limpeza — executa comandos no host via nsenter (pid:host + privileged)

NSE="nsenter -t 1 -m -u -i -n --"

# Limpar page cache do host
if ${NSE} sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null; then
    CACHE_OK=true
else
    CACHE_OK=false
fi

# Limpar logs antigos no host
if ${NSE} journalctl --vacuum-time=7d 2>/dev/null; then
    JOURNAL_OK=true
else
    JOURNAL_OK=false
fi

# Limpar cache do APT no host
if ${NSE} apt-get clean -qq 2>/dev/null; then
    APT_OK=true
else
    APT_OK=false
fi

# Docker prune — roda direto no container (acessa o daemon via socket)
if docker system prune -f 2>/dev/null; then
    DOCKER_OK=true
else
    DOCKER_OK=false
fi

# Memória disponível no host (lê /host/proc/meminfo)
RAM_CACHE=$(awk '/^MemAvailable:/ {printf "%.1fGB", $2/1024/1024}' /host/proc/meminfo 2>/dev/null || echo "N/A")

# Disco livre no host
DISK_FREE=$(${NSE} df -h / 2>/dev/null | awk 'NR==2{print $4}' || echo "N/A")

# Espaço recuperável do Docker
DOCKER_WASTE=$(docker system df --format '{{.Reclaimable}}' 2>/dev/null | head -1 || echo "N/A")

echo "CACHE_OK=$CACHE_OK"
echo "JOURNAL_OK=$JOURNAL_OK"
echo "APT_OK=$APT_OK"
echo "DOCKER_OK=$DOCKER_OK"
echo "RAM_CACHE=$RAM_CACHE"
echo "DISK_FREE=$DISK_FREE"
echo "DOCKER_WASTE=$DOCKER_WASTE"
