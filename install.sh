#!/usr/bin/env bash
# My Hub — Instalador interativo v1.0
# Requer: docker + docker compose v2, bash, curl, python3, git

set -euo pipefail
INSTALL_DIR="/opt/vm-hub"
VERSION="1.0.0"
GITHUB_REPO="https://github.com/trizzfilgueira/my-hub"   # repositório público

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
err()  { echo -e "${RED}✖${RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

header() {
  echo -e "\n${BOLD}${BLUE}╭─────────────────────────────────────╮${RESET}"
  echo -e "${BOLD}${BLUE}│  My Hub — Instalador v${VERSION}            │${RESET}"
  echo -e "${BOLD}${BLUE}╰─────────────────────────────────────╯${RESET}\n"
}

# ── 1. Pré-requisitos ─────────────────────────────────────────────────────────
check_prereqs() {
  if ! command -v docker &>/dev/null; then
    die "Docker não encontrado. Instale com: curl -fsSL https://get.docker.com | sh"
  fi
  if ! docker info &>/dev/null; then
    die "Docker não está rodando. Execute: sudo systemctl start docker"
  fi
  DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "?")
  ok "Docker detectado (v${DOCKER_VER})"

  if ! docker compose version &>/dev/null 2>&1; then
    die "Docker Compose v2 não encontrado. Atualize o Docker: https://docs.docker.com/compose/install/"
  fi
  COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "2.x")
  ok "Docker Compose v2 detectado (v${COMPOSE_VER})"

  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64|arm64) ARCH_LABEL="ARM64" ;;
    x86_64|amd64)  ARCH_LABEL="x86_64" ;;
    *)             ARCH_LABEL="$ARCH" ;;
  esac
  ok "Arquitetura: ${ARCH_LABEL}"

  CONTAINER_COUNT=$(docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
  ok "${CONTAINER_COUNT} containers encontrados"
}

# ── 2. Reinstalar? ────────────────────────────────────────────────────────────
check_existing() {
  if [ -d "$INSTALL_DIR" ]; then
    warn "My Hub já está instalado em ${INSTALL_DIR}"
    read -rp "Reinstalar? Dados persistidos serão mantidos. (s/N): " yn </dev/tty
    [[ "$yn" =~ ^[sS]$ ]] || die "Instalação cancelada."
    docker compose -f "${INSTALL_DIR}/docker-compose.yml" stop 2>/dev/null || true
  fi
}

# ── 3. Configuração interativa ────────────────────────────────────────────────
collect_config() {
  echo ""
  read -rp "? Nome do seu Hub [My Hub]: " HUB_NAME </dev/tty
  HUB_NAME="${HUB_NAME:-My Hub}"

  DEFAULT_PORT=8765
  while true; do
    read -rp "? Porta interna [${DEFAULT_PORT}]: " HUB_PORT </dev/tty
    HUB_PORT="${HUB_PORT:-$DEFAULT_PORT}"
    if ! [[ "$HUB_PORT" =~ ^[0-9]+$ ]] || [ "$HUB_PORT" -lt 1 ] || [ "$HUB_PORT" -gt 65535 ]; then
      warn "Porta inválida. Use um número entre 1 e 65535."; continue
    fi
    if ss -tlnp 2>/dev/null | grep -q ":${HUB_PORT} "; then
      warn "Porta ${HUB_PORT} já está em uso. Escolha outra."; continue
    fi
    break
  done

  while true; do
    read -rsp "? Senha de acesso ao painel: " HUB_PASSWORD </dev/tty; echo ""
    if [ ${#HUB_PASSWORD} -lt 8 ]; then
      warn "Senha muito curta (mínimo 8 caracteres)."; continue
    fi
    read -rsp "? Confirmar senha: " HUB_PASSWORD2 </dev/tty; echo ""
    [ "$HUB_PASSWORD" = "$HUB_PASSWORD2" ] && break
    warn "Senhas não coincidem. Tente novamente."
  done
}

# ── 4. Gerar arquivos ─────────────────────────────────────────────────────────
generate_files() {
  # Criar diretório com permissões corretas (suporta sudo e usuário normal)
  REAL_USER="${SUDO_USER:-$USER}"
  mkdir -p "${INSTALL_DIR}/extras"
  chown -R "${REAL_USER}:${REAL_USER}" "${INSTALL_DIR}" 2>/dev/null || true

  # Token JWT de 64 hex chars
  HUB_TOKEN=$(openssl rand -hex 32 2>/dev/null || \
    tr -dc 'a-f0-9' < /dev/urandom | head -c 64)

  # Garantir bcrypt disponível
  if ! python3 -c "import bcrypt" 2>/dev/null; then
    echo -e "${CYAN}Instalando python3-bcrypt...${RESET}"
    apt-get install -y python3-bcrypt -qq 2>/dev/null || \
    pip3 install bcrypt -q 2>/dev/null || \
    python3 -m pip install --break-system-packages bcrypt -q 2>/dev/null || true
  fi
  python3 -c "import bcrypt" 2>/dev/null || \
    die "Falha ao instalar bcrypt. Execute manualmente: sudo apt-get install python3-bcrypt"

  # Gerar hash via stdin (seguro para qualquer caractere na senha)
  HUB_PASSWORD_HASH=$(printf '%s' "$HUB_PASSWORD" | python3 - <<'PYEOF'
import bcrypt, sys
pwd = sys.stdin.read().encode()
print(bcrypt.hashpw(pwd, bcrypt.gensalt(rounds=12)).decode())
PYEOF
)
  [ -z "$HUB_PASSWORD_HASH" ] && die "Falha ao gerar hash da senha."

  # Escapar $ como $$ — docker compose faz interpolação de variáveis nos valores do .env
  HUB_PASSWORD_HASH_SAFE=$(printf '%s' "$HUB_PASSWORD_HASH" | sed 's/\$/\$\$/g')

  INSTALL_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "${INSTALL_DIR}/.env" <<EOF
HUB_NAME="${HUB_NAME}"
HUB_PORT=${HUB_PORT}
HUB_TOKEN="${HUB_TOKEN}"
HUB_PASSWORD_HASH="${HUB_PASSWORD_HASH_SAFE}"
INSTALL_DATE="${INSTALL_DATE}"
HUB_VERSION="${VERSION}"
GITHUB_REPO="${GITHUB_REPO}"
EOF
  chmod 600 "${INSTALL_DIR}/.env"
  ok "Configuração salva em ${INSTALL_DIR}/.env"

  echo ""
  ok "Containers descobertos:"
  docker ps -a --format '  • {{.Names}}' 2>/dev/null | head -20 || true
  echo ""
}

# ── 5. Copiar código-fonte ────────────────────────────────────────────────────
copy_source() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"

  # Sempre apagar e recriar para evitar aninhamento em reinstalações
  rm -rf "${INSTALL_DIR}/api" "${INSTALL_DIR}/frontend"

  if [ -n "$SCRIPT_DIR" ] && [ -d "${SCRIPT_DIR}/api" ]; then
    # Modo local: script está ao lado do código-fonte
    cp -r "${SCRIPT_DIR}/api"      "${INSTALL_DIR}/"
    cp -r "${SCRIPT_DIR}/frontend" "${INSTALL_DIR}/"
  else
    # Modo remoto: baixar do GitHub (público — sem token necessário)
    echo ""
    echo -e "${CYAN}Baixando código-fonte do GitHub...${RESET}"

    rm -rf /tmp/vm-hub-src

    if command -v git &>/dev/null; then
      git clone --depth=1 \
        "${GITHUB_REPO}.git" \
        /tmp/vm-hub-src 2>&1 | grep -v 'Cloning into' || true
    else
      mkdir -p /tmp/vm-hub-src
      curl -fsSL \
        "${GITHUB_REPO}/archive/refs/heads/main.tar.gz" \
        | tar -xz -C /tmp/vm-hub-src --strip-components=1
    fi

    [ -d /tmp/vm-hub-src/api ] || die "Falha ao baixar o repositório. Verifique a URL e tente novamente."

    cp -r /tmp/vm-hub-src/api      "${INSTALL_DIR}/"
    cp -r /tmp/vm-hub-src/frontend "${INSTALL_DIR}/"
    rm -rf /tmp/vm-hub-src
    ok "Código-fonte baixado"
  fi

  # Validar estrutura mínima
  [ -f "${INSTALL_DIR}/api/main.py" ]        || die "Estrutura inválida: api/main.py não encontrado. Verifique o repositório."
  [ -f "${INSTALL_DIR}/api/Dockerfile" ]     || die "Estrutura inválida: api/Dockerfile não encontrado."
  [ -f "${INSTALL_DIR}/frontend/index.html" ] || die "Estrutura inválida: frontend/index.html não encontrado."

  chmod +x "${INSTALL_DIR}/api/scripts/"*.sh 2>/dev/null || true
  ok "Código-fonte copiado e validado"
}

# ── 6. docker-compose.yml ─────────────────────────────────────────────────────
generate_compose() {
  # Usar <<'COMPOSE' para não expandir variáveis — docker compose lê do .env
  cat > "${INSTALL_DIR}/docker-compose.yml" <<'COMPOSE'
services:
  vm-hub-api:
    build:
      context: .
      dockerfile: api/Dockerfile
    container_name: vm-hub-api
    restart: unless-stopped
    pid: host
    ports:
      - "0.0.0.0:${HUB_PORT}:8000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /run/systemd:/run/systemd:ro
      - vm-hub-data:/app/data
    environment:
      - HUB_NAME=${HUB_NAME}
      - HUB_PORT=${HUB_PORT}
      - HUB_TOKEN=${HUB_TOKEN}
      - HUB_PASSWORD_HASH=${HUB_PASSWORD_HASH}
      - HUB_VERSION=${HUB_VERSION}
      - INSTALL_DATE=${INSTALL_DATE}
      - HOST_PROC=/host/proc
      - HOST_SYS=/host/sys
    privileged: true

volumes:
  vm-hub-data:
COMPOSE
}

# ── 7. Templates proxy reverso ────────────────────────────────────────────────
generate_extras() {
  cat > "${INSTALL_DIR}/extras/nginx.conf" <<EOF
# My Hub — Cole em /etc/nginx/sites-available/my-hub
# ln -s /etc/nginx/sites-available/my-hub /etc/nginx/sites-enabled/
# SSL: certbot --nginx -d SEU_DOMINIO

server {
    listen 80;
    server_name SEU_DOMINIO;

    location / {
        proxy_pass http://127.0.0.1:${HUB_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }
}
EOF

  cat > "${INSTALL_DIR}/extras/Caddyfile" <<EOF
# My Hub — Caddy obtém SSL automaticamente

SEU_DOMINIO {
    reverse_proxy localhost:${HUB_PORT}
}
EOF

  cat > "${INSTALL_DIR}/extras/traefik-labels.yml" <<EOF
# My Hub — Labels para adicionar ao seu docker-compose
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.my-hub.rule=Host(\`SEU_DOMINIO\`)"
  - "traefik.http.routers.my-hub.entrypoints=websecure"
  - "traefik.http.routers.my-hub.tls.certresolver=letsencrypt"
  - "traefik.http.services.my-hub.loadbalancer.server.port=${HUB_PORT}"
EOF
}

# ── 8. CLI helper vm-hub ──────────────────────────────────────────────────────
install_cli() {
  cat > "${INSTALL_DIR}/vm-hub" <<'CLI'
#!/usr/bin/env bash
INSTALL_DIR="/opt/vm-hub"
cd "$INSTALL_DIR" || { echo "My Hub não encontrado em $INSTALL_DIR"; exit 1; }

case "${1:-}" in
  start)   docker compose up -d ;;
  stop)    docker compose stop ;;
  restart) docker compose restart ;;
  logs)    docker compose logs -f vm-hub-api ;;

  status)
    if docker ps --format '{{.Names}}' | grep -q '^vm-hub-api$'; then
      PORT=$(grep '^HUB_PORT=' .env | cut -d= -f2)
      echo "My Hub rodando em http://localhost:${PORT}"
    else
      echo "My Hub parado. Use: vm-hub start"
    fi
    ;;

  reset-pwd)
    read -rsp "Nova senha (mín. 8 caracteres): " PWD1; echo ""
    [ ${#PWD1} -lt 8 ] && echo "Senha muito curta." && exit 1
    read -rsp "Confirmar nova senha: " PWD2; echo ""
    [ "$PWD1" != "$PWD2" ] && echo "Senhas não coincidem." && exit 1

    # Gerar hash via stdin — seguro para qualquer caractere
    HASH=$(printf '%s' "$PWD1" | python3 - <<'PYEOF'
import bcrypt, sys
pwd = sys.stdin.read().encode()
print(bcrypt.hashpw(pwd, bcrypt.gensalt(rounds=12)).decode())
PYEOF
)
    [ -z "$HASH" ] && echo "Erro ao gerar hash. Instale: sudo apt-get install python3-bcrypt" && exit 1

    # Escapar $ para compatibilidade com docker compose
    HASH_SAFE=$(printf '%s' "$HASH" | sed 's/\$/\$\$/g')

    # Atualizar .env de forma segura
    grep -v '^HUB_PASSWORD_HASH=' .env > .env.tmp
    printf 'HUB_PASSWORD_HASH="%s"\n' "$HASH_SAFE" >> .env.tmp
    mv .env.tmp .env
    chmod 600 .env

    docker compose up -d --force-recreate vm-hub-api
    echo "✔ Senha redefinida. Todos os tokens anteriores foram invalidados."
    ;;

  update)
    REPO=$(grep '^GITHUB_REPO=' .env 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    REPO="${REPO:-https://github.com/trizzfilgueira/my-hub}"
    git -C "$INSTALL_DIR" pull "${REPO}.git" main 2>/dev/null || true
    docker compose up -d --build
    echo "✔ My Hub atualizado."
    ;;

  uninstall)
    bash "${INSTALL_DIR}/uninstall.sh"
    ;;

  --help|help|"")
    echo "vm-hub — Gerenciador do My Hub"
    echo ""
    echo "Uso: vm-hub <comando>"
    echo ""
    echo "  start        Inicia o Hub"
    echo "  stop         Para o Hub"
    echo "  restart      Reinicia o Hub"
    echo "  logs         Exibe logs em tempo real"
    echo "  status       Mostra status e porta"
    echo "  reset-pwd    Redefine a senha (invalida todos os tokens)"
    echo "  update       Atualiza para a versão mais recente"
    echo "  uninstall    Remove o My Hub completamente"
    ;;

  *)
    echo "Comando desconhecido: $1. Use: vm-hub --help"
    exit 1
    ;;
esac
CLI

  chmod +x "${INSTALL_DIR}/vm-hub"
  ln -sf "${INSTALL_DIR}/vm-hub" /usr/local/bin/vm-hub 2>/dev/null || \
    sudo ln -sf "${INSTALL_DIR}/vm-hub" /usr/local/bin/vm-hub 2>/dev/null || \
    warn "Não foi possível criar /usr/local/bin/vm-hub. Use: ${INSTALL_DIR}/vm-hub"
  ok "CLI vm-hub instalado"
}

# ── 9. Subir o Hub ────────────────────────────────────────────────────────────
start_hub() {
  cd "$INSTALL_DIR"
  echo ""
  echo -e "${CYAN}Construindo e iniciando o Hub...${RESET}"
  docker compose --env-file .env up -d --build

  echo -e "${CYAN}Aguardando API iniciar...${RESET}"
  for i in $(seq 1 45); do
    if curl -sf "http://localhost:${HUB_PORT}/api/health" &>/dev/null; then
      ok "My Hub iniciado com sucesso"
      return
    fi
    sleep 2
  done
  warn "API não respondeu em 90s. Verifique os logs: vm-hub logs"
}

# ── 10. Resumo final ──────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${BOLD}────────────────────────────────────────────${RESET}"
  echo -e "  ${GREEN}${BOLD}My Hub rodando em http://localhost:${HUB_PORT}${RESET}"
  echo -e "${BOLD}────────────────────────────────────────────${RESET}"
  echo ""
  echo "Templates de proxy reverso prontos:"
  echo ""
  echo "  Nginx:   cat ${INSTALL_DIR}/extras/nginx.conf"
  echo "  Caddy:   cat ${INSTALL_DIR}/extras/Caddyfile"
  echo "  Traefik: cat ${INSTALL_DIR}/extras/traefik-labels.yml"
  echo ""
  echo "Gerenciar: vm-hub --help"
  echo -e "${BOLD}────────────────────────────────────────────${RESET}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  header
  check_prereqs
  check_existing
  collect_config
  generate_files
  copy_source
  generate_compose
  generate_extras
  install_cli
  start_hub
  print_summary
}

main "$@"
