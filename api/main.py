import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .core.config import cfg
from .routers import auth, docker_ctrl, logs, metrics, netinfo, scripts, user_config

app = FastAPI(title="VM Hub API", version=cfg.HUB_VERSION, docs_url="/api/docs", redoc_url=None)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── API routes (must be registered before the static file catch-all) ──────────
app.include_router(auth.router)
app.include_router(metrics.router)
app.include_router(docker_ctrl.router)
app.include_router(scripts.router)
app.include_router(netinfo.router)
app.include_router(logs.router)
app.include_router(user_config.router)


@app.get("/api/health")
def health():
    return {"ok": True, "version": cfg.HUB_VERSION}


@app.get("/api/config")
def public_config():
    return {"hub_name": cfg.HUB_NAME, "version": cfg.HUB_VERSION, "port": cfg.HUB_PORT}


# ── Frontend static files (catch-all — must be last) ─────────────────────────
frontend_dir = os.path.join(os.path.dirname(__file__), "..", "frontend")
frontend_dir = os.path.abspath(frontend_dir)
if os.path.isdir(frontend_dir):
    app.mount("/", StaticFiles(directory=frontend_dir, html=True), name="frontend")
