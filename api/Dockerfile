FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc bash curl util-linux iproute2 procps \
    && rm -rf /var/lib/apt/lists/*

# Install speedtest-go (auto-detect arch: arm64 or amd64)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      aarch64|arm64) SPD_ARCH="arm64" ;; \
      *) SPD_ARCH="amd64" ;; \
    esac && \
    curl -fsSL "https://github.com/showwin/speedtest-go/releases/download/v1.6.0/speedtest-go_1.6.0_Linux_${SPD_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin speedtest-go && \
    chmod +x /usr/local/bin/speedtest-go

WORKDIR /app

# Build context é a raiz /opt/vm-hub/, então todos os paths são relativos a ela
COPY api/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY api/ /app/api/
COPY frontend/ /app/frontend/
RUN mkdir -p /app/data /app/scripts
COPY api/scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh 2>/dev/null || true

EXPOSE 8000

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
