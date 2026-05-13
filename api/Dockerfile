FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc bash curl util-linux iproute2 procps \
    && rm -rf /var/lib/apt/lists/*

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
