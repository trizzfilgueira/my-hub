#!/usr/bin/env bash
# My Hub — Desinstalador

set -uo pipefail
INSTALL_DIR="/opt/vm-hub"

echo "Removendo My Hub..."

if [ -d "$INSTALL_DIR" ]; then
  cd "$INSTALL_DIR" && docker compose down -v 2>/dev/null || true
fi

rm -f /usr/local/bin/vm-hub 2>/dev/null || \
  sudo rm -f /usr/local/bin/vm-hub 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/my-hub 2>/dev/null || true
rm -f /etc/nginx/sites-available/my-hub 2>/dev/null || true
systemctl reload nginx 2>/dev/null || true

read -rp "Remover todos os arquivos em ${INSTALL_DIR}? (s/N): " confirm </dev/tty
if [[ "$confirm" =~ ^[sS]$ ]]; then
  rm -rf "$INSTALL_DIR"
  echo "✔ Arquivos removidos"
fi

echo "✔ My Hub removido com sucesso"
