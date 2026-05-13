#!/bin/bash
# Speedtest — usa speedtest-go (instalado no container via Dockerfile)

DL_MBPS="0"
UL_MBPS="0"

if command -v speedtest-go &>/dev/null; then
    OUTPUT=$(speedtest-go --thread 8 2>/dev/null)
    DL_RAW=$(printf '%s' "$OUTPUT" | grep -i "Download:" | grep -oP '[0-9]+\.[0-9]+(?=Mbps)' | head -1)
    UL_RAW=$(printf '%s' "$OUTPUT" | grep -i "Upload:"   | grep -oP '[0-9]+\.[0-9]+(?=Mbps)' | head -1)
    [ -n "$DL_RAW" ] && DL_MBPS="$DL_RAW"
    [ -n "$UL_RAW" ] && UL_MBPS="$UL_RAW"
fi

# Fallback via Cloudflare se speedtest-go falhar ou não estiver disponível
if [ "$DL_MBPS" = "0" ]; then
    TMPDIR_SPD=$(mktemp -d)

    for i in 1 2 3 4; do
        curl -o /dev/null -s -w "%{speed_download}\n" --max-time 20 \
            "https://speed.cloudflare.com/__down?bytes=104857600&r=$i" \
            > "${TMPDIR_SPD}/dl_${i}" 2>/dev/null &
    done
    wait
    DL_MBPS=$(cat "${TMPDIR_SPD}"/dl_* 2>/dev/null | awk '{s+=$1} END{printf "%.1f", s*8/1000000}')
    rm -rf "$TMPDIR_SPD"
fi

if [ "$UL_MBPS" = "0" ]; then
    UL_TMPFILE=$(mktemp)
    python3 -c "import sys,os; sys.stdout.buffer.write(os.urandom(52428800))" > "$UL_TMPFILE" 2>/dev/null
    UL_SPEED=$(curl -s -X POST \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$UL_TMPFILE" \
        --max-time 20 \
        "https://speed.cloudflare.com/__up" \
        -w "%{speed_upload}\n" \
        -o /dev/null 2>/dev/null || echo "0")
    rm -f "$UL_TMPFILE"
    UL_MBPS=$(echo "${UL_SPEED:-0}" | awk '{printf "%.1f", $1*8/1000000}')
fi

echo "DL_MBPS=$DL_MBPS"
echo "UL_MBPS=$UL_MBPS"
