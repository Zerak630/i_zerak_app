"""Chargement et validation de la configuration de l'agent."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml

DEFAULT_CONFIG_PATH = Path("/etc/izerak-agent/config.yaml")

# Longueur minimale du jeton. 32 octets aleatoires produisent 43 caracteres en
# base64 url-safe ; refuser plus court evite qu'un jeton d'essai ne se retrouve
# en production.
MIN_TOKEN_LENGTH = 32


@dataclass(frozen=True)
class ServiceEntry:
    name: str
    unit: str


@dataclass(frozen=True)
class VolumeEntry:
    path: str
    label: str
    quota_bytes: int | None = None


@dataclass(frozen=True)
class AgentConfig:
    token: str
    bind_host: str = "0.0.0.0"
    bind_port: int = 8081
    tls_certificate: str | None = None
    tls_private_key: str | None = None
    services: list[ServiceEntry] = field(default_factory=list)
    storage: list[VolumeEntry] = field(default_factory=list)

    def unit_for(self, name: str) -> str | None:
        """Traduit un nom expose en unite systemd, ou None s'il est inconnu.

        C'est le seul point ou une entree client devient un nom d'unite : tout
        ce qui n'est pas dans la liste ressort a None.
        """
        for entry in self.services:
            if entry.name == name:
                return entry.unit
        return None


class ConfigError(RuntimeError):
    pass


def load(path: Path | None = None) -> AgentConfig:
    config_path = path or Path(os.environ.get("IZERAK_AGENT_CONFIG", DEFAULT_CONFIG_PATH))
    if not config_path.is_file():
        raise ConfigError(f"Configuration introuvable : {config_path}")

    raw = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    if not isinstance(raw, dict):
        raise ConfigError("La configuration doit etre un mapping YAML")

    token = str(raw.get("token") or "").strip()
    if len(token) < MIN_TOKEN_LENGTH:
        raise ConfigError(
            f"Le jeton doit faire au moins {MIN_TOKEN_LENGTH} caracteres "
            "(voir install.sh, qui en genere un)"
        )

    services = [
        ServiceEntry(name=str(item["name"]), unit=str(item["unit"]))
        for item in raw.get("services", [])
        if isinstance(item, dict) and item.get("name") and item.get("unit")
    ]

    storage = [
        VolumeEntry(
            path=str(item["path"]),
            label=str(item.get("label") or item["path"]),
            quota_bytes=int(item["quota_bytes"]) if item.get("quota_bytes") else None,
        )
        for item in raw.get("storage", [])
        if isinstance(item, dict) and item.get("path")
    ]

    return AgentConfig(
        token=token,
        bind_host=str(raw.get("bind_host", "0.0.0.0")),
        bind_port=int(raw.get("bind_port", 8081)),
        tls_certificate=raw.get("tls_certificate"),
        tls_private_key=raw.get("tls_private_key"),
        services=services,
        storage=storage,
    )
