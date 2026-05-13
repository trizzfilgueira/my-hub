#!/bin/bash
# Speedtest — usa speedtest-go (instalado no container via Dockerfile)
# Fallback: Cloudflare multi-curl se speedtest-go não estiver disponível

DL_MBPS="0"
UL_MBPS="0"

# ── speedtest-go ───────────────────────────────────────────────────────────────
if command -v speedtest-go &>/dev/null; then
    OUTPUT=$(speedtest-go --thread 8 2>/dev/null)

    # Extrai valores — extended regex (sem Perl lookahead para máxima compatibilidade)
    DL_LINE=$(printf '%s' "$OUTPUT" | grep -i "Download:")
    UL_LINE=$(printf '%s' "$OUTPUT" | grep -i "Upload:")

    DL_RAW=$(printf '%s' "$DL_LINE" | grep -oE '[0-9]+\.[0-9]+Mbps' | grep -oE '[0-9]+\.[0-9]+' | head -1)
    UL_RAW=$(printf '%s' "$UL_LINE" | grep -oE '[0-9]+\.[0-9]+Mbps' | grep -oE '[0-9]+\.[0-9]+' | head -1)

    # Converte Gbps → Mbps se necessário
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

# ── Fallback download via Cloudflare ──────────────────────────────────────────
if [ "$DL_MBPS" = "0" ]; then
    START=$(date +%s%N)
    BYTES=$(curl -s --max-time 15 \
        "https://speed.cloudflare.com/__down?bytes=52428800" \
        | wc -c)
    END=$(date +%s%N)
    ELAPSED=$(awk "BEGIN{printf \"%.3f\", ($END - $START) / 1000000000}")
    DL_MBPS=$(awk "BEGIN{printf \"%.1f\", ($BYTES * 8) / ($ELAPSED * 1000000)}")
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
