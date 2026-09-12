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

# Memes valeurs que systemd.ServiceAction, dans le meme ordre.
ALL_ACTIONS: tuple[str, ...] = ("start", "stop", "restart")


@dataclass(frozen=True)
class ServiceEntry:
    name: str
    unit: str
    # Interface web du service, facultative. L'agent ne publie que le port, le
    # schema et le chemin : l'hote reste celui par lequel l'application joint
    # deja le Pi, qu'il s'agisse de son adresse locale ou d'un nom Tailscale.
    web_port: int | None = None
    web_scheme: str = "http"
    web_path: str = "/"
    # Actions permises sur ce service. Retirer « stop » protege un service dont
    # l'arret couperait l'acces a l'agent lui-meme — un tunnel VPN par lequel
    # passe le telephone, typiquement : une fois arrete, plus rien ne permet de
    # le relancer a distance. Les regles sudo doivent suivre la meme liste.
    actions: tuple[str, ...] = ALL_ACTIONS

    def web(self) -> dict | None:
        if self.web_port is None:
            return None
        return {"scheme": self.web_scheme, "port": self.web_port, "path": self.web_path}


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

    def entry_for(self, name: str) -> ServiceEntry | None:
        for entry in self.services:
            if entry.name == name:
                return entry
        return None

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


def _service_entry(item: dict) -> ServiceEntry:
    name = str(item["name"])
    port = item.get("web_port")
    if port is not None:
        # bool herite de int : « web_port: yes » passerait sinon pour le port 1.
        if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
            raise ConfigError(f"web_port invalide pour le service {name} : {port!r}")
    scheme = str(item.get("web_scheme") or "http")
    if scheme not in ("http", "https"):
        raise ConfigError(f"web_scheme invalide pour le service {name} : {scheme!r}")
    path = str(item.get("web_path") or "/")
    if not path.startswith("/"):
        path = "/" + path

    raw_actions = item.get("actions")
    if raw_actions is None:
        actions = ALL_ACTIONS
    else:
        if not isinstance(raw_actions, list) or any(
            action not in ALL_ACTIONS for action in raw_actions
        ):
            raise ConfigError(
                f"actions invalides pour le service {name} : {raw_actions!r} "
                f"(valeurs permises : {', '.join(ALL_ACTIONS)})"
            )
        # Ordre canonique et sans doublon, quel que soit l'ordre ecrit.
        actions = tuple(action for action in ALL_ACTIONS if action in raw_actions)

    return ServiceEntry(
        name=name,
        unit=str(item["unit"]),
        web_port=port,
        web_scheme=scheme,
        web_path=path,
        actions=actions,
    )


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
        _service_entry(item)
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
