"""Consultation et pilotage des unites systemd autorisees.

Deux regles gouvernent ce module, et elles ne sont pas negociables :

1. Le nom d'unite recu du client n'est jamais transmis a ``systemctl``. Il sert
   uniquement de cle de recherche dans la liste blanche issue de la
   configuration ; une unite absente de cette liste provoque un 404 sans
   qu'aucun processus ne soit lance.
2. Aucune commande ne passe par un shell. ``subprocess.run`` recoit une liste
   d'arguments, ce qui rend toute injection sans effet.
"""

from __future__ import annotations

import subprocess
from dataclasses import asdict, dataclass
from enum import Enum

SYSTEMCTL = "/bin/systemctl"
SUDO = "/usr/bin/sudo"

_TIMEOUT_SECONDS = 15


class ServiceAction(str, Enum):
    start = "start"
    stop = "stop"
    restart = "restart"


@dataclass(frozen=True)
class ServiceStatus:
    name: str
    unit: str
    active_state: str
    sub_state: str
    enabled: bool
    since: str | None
    memory_bytes: int | None

    def to_dict(self) -> dict:
        return asdict(self)


class UnknownUnitError(LookupError):
    """L'unite demandee ne figure pas dans la liste blanche."""


def _show(unit: str) -> dict[str, str]:
    """Proprietes d'une unite. `systemctl show` ne requiert aucun privilege."""
    result = subprocess.run(
        [
            SYSTEMCTL,
            "show",
            unit,
            "--property=ActiveState,SubState,UnitFileState,ActiveEnterTimestamp,MemoryCurrent",
            "--no-pager",
        ],
        capture_output=True,
        text=True,
        timeout=_TIMEOUT_SECONDS,
        check=False,
    )
    properties: dict[str, str] = {}
    for line in result.stdout.splitlines():
        key, _, value = line.partition("=")
        if key:
            properties[key] = value
    return properties


def _memory(raw: str | None) -> int | None:
    # systemd renvoie [not set] quand la comptabilite memoire est desactivee, et
    # une valeur sentinelle 2^64-1 pour les unites inactives.
    if not raw or not raw.isdigit():
        return None
    value = int(raw)
    return None if value >= 2**63 else value


def status(name: str, unit: str) -> ServiceStatus:
    properties = _show(unit)
    since = properties.get("ActiveEnterTimestamp") or None
    return ServiceStatus(
        name=name,
        unit=unit,
        active_state=properties.get("ActiveState", "unknown"),
        sub_state=properties.get("SubState", "unknown"),
        enabled=properties.get("UnitFileState") == "enabled",
        since=since,
        memory_bytes=_memory(properties.get("MemoryCurrent")),
    )


def apply(unit: str, action: ServiceAction) -> None:
    """Applique une action. L'appelant a deja valide l'unite contre la liste."""
    result = subprocess.run(
        [SUDO, "-n", SYSTEMCTL, action.value, unit],
        capture_output=True,
        text=True,
        timeout=_TIMEOUT_SECONDS,
        check=False,
    )
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"systemctl {action.value} {unit} a echoue : {message}")
