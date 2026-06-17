import json
import os
from pathlib import Path

import docker
from docker.errors import DockerException, NotFound
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from .auth import require_auth
from .user_config import load_user_config, save_user_config

router = APIRouter(prefix="/api/docker", tags=["docker"])

_client: docker.DockerClient | None = None


def _docker() -> docker.DockerClient:
    global _client
    if _client is None:
        _client = docker.from_env()
    return _client


def _status_norm(status: str) -> str:
    s = status.lower()
    if "running" in s:
        return "running"
    if "restart" in s:
        return "restarting"
    if "paused" in s:
        return "paused"
    if "exited" in s or "stopped" in s:
        return "stopped"
    return s


@router.get("", dependencies=[Depends(require_auth)])
def list_containers():
    try:
        client = _docker()
        containers = client.containers.list(all=True)
    except DockerException as e:
        raise HTTPException(status_code=503, detail=f"Docker indisponível: {e}")

    cfg_data = load_user_config()
    container_meta: dict = cfg_data.get("containers", {})

    result = []
    for c in containers:
        name = c.name
        meta = container_meta.get(name, {})
        image = ""
        try:
            image = c.image.tags[0] if c.image.tags else c.image.short_id
        except Exception:
            pass
        started_at = ""
        try:
            started_at = c.attrs.get("State", {}).get("StartedAt", "")
        except Exception:
            pass

        result.append({
            "name": name,
            "display_name": meta.get("display_name", name.capitalize()),
            "description": meta.get("description", ""),
            "icon": meta.get("icon", "📦"),
            "status": _status_norm(c.status),
            "image": image,
            "started_at": started_at,
        })

    return result


@router.post("/{name}/restart", dependencies=[Depends(require_auth)])
def restart_container(name: str):
    try:
        c = _docker().containers.get(name)
        c.restart(timeout=10)
        return {"ok": True, "name": name, "action": "restart"}
    except NotFound:
        raise HTTPException(status_code=404, detail=f"Container '{name}' não encontrado")
    except DockerException as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{name}/stop", dependencies=[Depends(require_auth)])
def stop_container(name: str):
    try:
        c = _docker().containers.get(name)
        c.stop(timeout=10)
        return {"ok": True, "name": name, "action": "stop"}
    except NotFound:
        raise HTTPException(status_code=404, detail=f"Container '{name}' não encontrado")
    except DockerException as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{name}/start", dependencies=[Depends(require_auth)])
def start_container(name: str):
    try:
        c = _docker().containers.get(name)
        c.start()
        return {"ok": True, "name": name, "action": "start"}
    except NotFound:
        raise HTTPException(status_code=404, detail=f"Container '{name}' não encontrado")
    except DockerException as e:
        raise HTTPException(status_code=500, detail=str(e))


def _parse_port_bindings(pb: dict) -> dict | None:
    if not pb:
        return None
    result = {}
    for port, bindings in pb.items():
        if bindings:
            result[port] = [{"HostIp": b.get("HostIp", ""), "HostPort": b.get("HostPort", "")} for b in bindings]
        else:
            result[port] = None
    return result


@router.post("/{name}/pull", dependencies=[Depends(require_auth)])
def pull_and_restart(name: str):
    try:
        client = _docker()
        c = client.containers.get(name)

        image_name = c.image.tags[0] if c.image.tags else None
        if not image_name:
            raise HTTPException(status_code=400, detail=f"Container '{name}' não tem tag de imagem — atualize manualmente.")

        # Pull new image from Docker Hub (may take a while for large images)
        client.images.pull(image_name)

        # Save container config before removing it
        attrs = c.attrs
        hc = attrs.get("HostConfig", {})
        cfg = attrs.get("Config", {})
        container_name = c.name

        # Stop and remove so we can recreate with the new image
        c.stop(timeout=15)
        c.remove()

        # Recreate container with identical config but fresh image layers
        new_c = client.api.create_container(
            image=image_name,
            name=container_name,
            environment=cfg.get("Env"),
            volumes=list(cfg.get("Volumes") or {}).keys() or None,
            ports=list(cfg.get("ExposedPorts") or {}).keys() or None,
            host_config=client.api.create_host_config(
                binds=hc.get("Binds"),
                port_bindings=_parse_port_bindings(hc.get("PortBindings")),
                restart_policy=hc.get("RestartPolicy"),
                network_mode=hc.get("NetworkMode"),
                volumes_from=hc.get("VolumesFrom"),
                cap_add=hc.get("CapAdd"),
                cap_drop=hc.get("CapDrop"),
                dns=hc.get("Dns"),
                extra_hosts=hc.get("ExtraHosts"),
                privileged=hc.get("Privileged", False),
                devices=hc.get("Devices"),
                shm_size=hc.get("ShmSize"),
                ulimits=hc.get("Ulimits"),
                log_config=hc.get("LogConfig"),
            ),
        )
        client.api.start(new_c["Id"])

        # Reconnect to any additional networks beyond the primary one
        primary_net = hc.get("NetworkMode", "")
        for net_name, net_cfg in (attrs.get("NetworkSettings") or {}).get("Networks", {}).items():
            if net_name == primary_net:
                continue
            try:
                aliases = (net_cfg or {}).get("Aliases") or []
                client.networks.get(net_name).connect(new_c["Id"], aliases=aliases or None)
            except Exception:
                pass

        return {"ok": True, "name": name, "action": "pull"}
    except NotFound:
        raise HTTPException(status_code=404, detail=f"Container '{name}' não encontrado")
    except DockerException as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{name}/logs", dependencies=[Depends(require_auth)])
def container_logs(name: str, lines: int = 100):
    try:
        c = _docker().containers.get(name)
        raw = c.logs(tail=lines, timestamps=True).decode("utf-8", errors="replace")
        return {"name": name, "logs": raw}
    except NotFound:
        raise HTTPException(status_code=404, detail=f"Container '{name}' não encontrado")
    except DockerException as e:
        raise HTTPException(status_code=500, detail=str(e))


class ContainerConfigBody(BaseModel):
    display_name: str | None = None
    description: str | None = None
    icon: str | None = None


@router.put("/{name}/config", dependencies=[Depends(require_auth)])
def update_container_config(name: str, body: ContainerConfigBody):
    data = load_user_config()
    containers = data.setdefault("containers", {})
    meta = containers.setdefault(name, {})
    if body.display_name is not None:
        meta["display_name"] = body.display_name
    if body.description is not None:
        meta["description"] = body.description
    if body.icon is not None:
        meta["icon"] = body.icon
    save_user_config(data)
    return {"ok": True, "name": name, "config": meta}
