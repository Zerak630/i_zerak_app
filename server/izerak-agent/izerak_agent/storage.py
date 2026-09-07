"""Etat des volumes surveilles, notamment le disque externe de la bibliotheque.

Le piege central est ici : lorsqu'un disque USB est debranche, son point de
montage subsiste sous la forme d'un repertoire vide sur la carte SD. Un simple
``os.path.exists()`` repondrait donc « present », et qBittorrent ecrirait sur la
carte SD jusqu'a la saturer. La detection croise trois verifications pour eviter
cela.
"""

from __future__ import annotations

import os
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path

# Vue de l'init, et non celle du service.
#
# systemd place les unites durcies par ProtectSystem=strict dans un espace de
# noms de montage ou toute la hierarchie est remontee en lecture seule. Dans cet
# espace, /proc/mounts affiche « ro » pour des volumes parfaitement
# inscriptibles par les autres processus, et l'agent rapporterait alors un
# disque en lecture seule a tort — ce qui bloque l'ajout de telechargements cote
# application. /proc/1/mounts donne la vue du systeme, la seule pertinente ici.
_PROC_MOUNTS = Path("/proc/1/mounts")
_PROC_MOUNTS_FALLBACK = Path("/proc/mounts")


@dataclass(frozen=True)
class MountInfo:
    device: str
    fstype: str
    readonly: bool


@dataclass(frozen=True)
class VolumeStatus:
    path: str
    label: str
    mounted: bool
    reason: str | None = None
    device: str | None = None
    fstype: str | None = None
    readonly: bool = False
    total_bytes: int | None = None
    used_bytes: int | None = None
    free_bytes: int | None = None
    quota_bytes: int | None = None
    quota_used_bytes: int | None = None
    quota_free_bytes: int | None = None
    quota_ratio: float | None = None

    def to_dict(self) -> dict:
        return asdict(self)


def _unescape(field: str) -> str:
    """/proc/mounts encode espaces et tabulations en octal."""
    return (
        field.replace("\\040", " ")
        .replace("\\011", "\t")
        .replace("\\012", "\n")
        .replace("\\134", "\\")
    )


def read_proc_mounts(target: Path, mounts_file: Path = _PROC_MOUNTS) -> MountInfo | None:
    """Entree de la table des montages correspondant exactement au chemin donne."""
    try:
        content = mounts_file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        # /proc/1/mounts peut etre inaccessible selon la configuration de
        # hidepid : on retombe alors sur la vue locale, moins fiable mais
        # toujours meilleure que rien.
        if mounts_file == _PROC_MOUNTS:
            return read_proc_mounts(target, mounts_file=_PROC_MOUNTS_FALLBACK)
        return None

    resolved = str(target)
    for line in content.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        device, mount_point, fstype, options = (
            _unescape(parts[0]),
            _unescape(parts[1]),
            parts[2],
            parts[3],
        )
        if mount_point == resolved:
            flags = options.split(",")
            return MountInfo(device=device, fstype=fstype, readonly="ro" in flags)
    return None


def probe(path: str, label: str, quota_bytes: int | None = None) -> VolumeStatus:
    """Etat complet d'un volume : presence, inscriptibilite et occupation."""
    target = Path(path)

    # Les disques amovibles sont montes sous /media/<utilisateur>, dont le
    # repertoire parent n'est traversable que par son proprietaire. Un compte de
    # service s'y heurte a une PermissionError. Elle est rattrapee ici : l'agent
    # surveille plusieurs volumes, et l'un d'eux inaccessible ne doit pas faire
    # echouer la reponse entiere.
    try:
        if not target.is_dir():
            return VolumeStatus(path=path, label=label, mounted=False, reason="missing")

        # 1. Le chemin est-il reellement un point de montage, ou un simple dossier ?
        if not os.path.ismount(target):
            return VolumeStatus(path=path, label=label, mounted=False, reason="not_mounted")
    except PermissionError:
        return VolumeStatus(path=path, label=label, mounted=False, reason="permission_denied")
    except OSError:
        return VolumeStatus(path=path, label=label, mounted=False, reason="stat_failed")

    # 2. Le peripherique diffe-t-il de celui du parent ? Attrape le cas ou un
    #    montage lie ferait pointer le chemin vers le systeme de fichiers racine.
    try:
        if target.stat().st_dev == target.parent.stat().st_dev:
            return VolumeStatus(
                path=path, label=label, mounted=False, reason="same_device_as_root"
            )
    except OSError:
        return VolumeStatus(path=path, label=label, mounted=False, reason="stat_failed")

    mount = read_proc_mounts(target)

    # 3. Le noyau remonte un disque USB defaillant en lecture seule. Le volume
    #    est alors bien present, mais plus inscriptible : signaler « monte »
    #    sans le preciser serait trompeur.
    #
    #    L'etat vient exclusivement des options de montage. Il ne faut surtout
    #    pas le deduire de os.access(target, os.W_OK) : l'agent a volontairement
    #    des droits minimaux, et son incapacite a ecrire ne dit rien de l'etat du
    #    volume — c'est qBittorrent, sous un autre compte, qui y ecrit. Faute
    #    d'entree de montage, on ne conclut pas.
    readonly = mount.readonly if mount else False

    try:
        usage = shutil.disk_usage(target)
    except OSError:
        return VolumeStatus(path=path, label=label, mounted=False, reason="usage_failed")

    quota_used = quota_free = None
    ratio = None
    if quota_bytes and quota_bytes > 0:
        quota_used = usage.used
        quota_free = max(quota_bytes - usage.used, 0)
        ratio = min(usage.used / quota_bytes, 1.0)

    return VolumeStatus(
        path=path,
        label=label,
        mounted=True,
        reason=None,
        device=mount.device if mount else None,
        fstype=mount.fstype if mount else None,
        readonly=readonly,
        total_bytes=usage.total,
        used_bytes=usage.used,
        free_bytes=usage.free,
        quota_bytes=quota_bytes,
        quota_used_bytes=quota_used,
        quota_free_bytes=quota_free,
        quota_ratio=ratio,
    )
