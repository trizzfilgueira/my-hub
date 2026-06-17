#!/bin/bash
# Speedtest — usa speedtest-go (instalado no container via Dockerfile)
# Fallback: Cloudflare se speedtest-go não estiver disponível

DL_MBPS="0"
UL_MBPS="0"

# ── speedtest-go ───────────────────────────────────────────────────────────────
if command -v speedtest-go &>/dev/null; then
    OUTPUT=$(speedtest-go --thread 8 2>/dev/null)

    DL_LINE=$(printf '%s' "$OUTPUT" | grep -i "Download:")
    UL_LINE=$(printf '%s' "$OUTPUT" | grep -i "Upload:")

    # Tenta Mbps
    DL_RAW=$(printf '%s' "$DL_LINE" | grep -oE '[0-9]+\.[0-9]+Mbps' | grep -oE '[0-9]+\.[0-9]+' | head -1)
    UL_RAW=$(printf '%s' "$UL_LINE" | grep -oE '[0-9]+\.[0-9]+Mbps' | grep -oE '[0-9]+\.[0-9]+' | head -1)

    # Tenta Gbps → converte para Mbps
    if [ -z "$DL_RAW" ]; then
        DL_G=$(printf '%s' "$DL_LINE" | grep -oE '[0-9]+\.[0-9]+Gbps' | grep -oE '[0-9]+\.[0-9]+' | head -1)
        [ -n "$DL_G" ] && DL_RAW=$(awk "BEGIN{printf \"%.1f\", $DL_G * 1000}")
    fi
    if [ -z "$UL_RAW" ]; then
        UL_G=$(printf '%s' "$UL_LINE" | grep -oE '[0-9]+\.[0-9]+Gbps' | grep -oE '[0-9]+\.[0-9]+' | head -1)
        [ -n "$UL_G" ] && UL_RAW=$(awk "BEGIN{printf \"%.1f\", $UL_G * 1000}")
    fi

    [ -n "$DL_RAW" ] && DL_MBPS="$DL_RAW"
    [ -n "$UL_RAW" ] && UL_MBPS="$UL_RAW"
fi

# ── Fallback download: 4 conexões paralelas, mede bytes reais recebidos ────────
if [ "$DL_MBPS" = "0" ]; then
    TMPDIR_SPD=$(mktemp -d)
    T0=$SECONDS
    for i in 1 2 3 4; do
        curl -s -L --max-time 12 \
            "https://speed.cloudflare.com/__down?bytes=26214400&r=${i}" \
            | wc -c > "${TMPDIR_SPD}/dl_${i}" 2>/dev/null &
    done
    wait
    T1=$SECONDS
    ELAPSED=$((T1 - T0))
    [ "$ELAPSED" -lt 1 ] && ELAPSED=1
    TOTAL=$(cat "${TMPDIR_SPD}"/dl_* 2>/dev/null | awk '{s+=$1} END{print s+0}')
    rm -rf "$TMPDIR_SPD"
    DL_MBPS=$(awk "BEGIN{printf \"%.1f\", ($TOTAL * 8) / ($ELAPSED * 1000000)}")
fi

# ── Fallback upload via Cloudflare ────────────────────────────────────────────
if [ "$UL_MBPS" = "0" ]; then
    UL_TMPFILE=$(mktemp)
    python3 -c "import sys,os; sys.stdout.buffer.write(os.urandom(26214400))" > "$UL_TMPFILE" 2>/dev/null
    UL_SPEED=$(curl -s -X POST \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$UL_TMPFILE" \
        --max-time 20 \
        "https://speed.cloudflare.com/__up" \
        -w "%{speed_upload}" \
        -o /dev/null 2>/dev/null || echo "0")
    rm -f "$UL_TMPFILE"
    UL_MBPS=$(awk "BEGIN{printf \"%.1f\", ${UL_SPEED:-0} * 8 / 1000000}")
fi

echo "DL_MBPS=$DL_MBPS"
echo "UL_MBPS=$UL_MBPS"
