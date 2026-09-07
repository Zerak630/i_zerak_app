"""Tests de la detection de montage.

Le cas qui compte est celui du disque debranche : le point de montage reste un
repertoire ordinaire sur la carte SD, et le confondre avec un disque present
ferait remplir la carte par les telechargements.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from izerak_agent.storage import MountInfo, probe, read_proc_mounts


def _force_distinct_devices(monkeypatch, point: Path) -> None:
    """Fait passer le point de montage pour un peripherique distinct du parent.

    Le faux resultat delegue au vrai stat et ne surcharge que st_dev : probe()
    appelle is_dir() avant de comparer les peripheriques, et is_dir() a besoin
    de st_mode. Un objet ne portant que st_dev faisait echouer le test bien
    avant la verification qu il visait.
    """

    class _PartialStat:
        def __init__(self, real, dev: int) -> None:
            self._real = real
            self.st_dev = dev

        def __getattr__(self, name):
            return getattr(self._real, name)

    real_stat = Path.stat

    def fake_stat(self, *args, **kwargs):
        result = real_stat(self, *args, **kwargs)
        if self == point:
            return _PartialStat(result, 42)
        if self == point.parent:
            return _PartialStat(result, 1)
        return result

    monkeypatch.setattr(Path, "stat", fake_stat)


def test_repertoire_absent(tmp_path: Path) -> None:
    status = probe(str(tmp_path / "inexistant"), "Disque Emby")
    assert status.mounted is False
    assert status.reason == "missing"


def test_repertoire_ordinaire_nest_pas_un_montage(tmp_path: Path) -> None:
    """Le cas du disque debranche : le dossier existe, rien n'est monte."""
    point = tmp_path / "media"
    point.mkdir()

    status = probe(str(point), "Disque Emby")

    assert status.mounted is False
    assert status.reason == "not_mounted"
    # Aucune taille ne doit etre rapportee : elle decrirait la carte SD.
    assert status.free_bytes is None
    assert status.quota_ratio is None


def test_montage_sur_le_meme_peripherique_que_le_parent(tmp_path: Path, monkeypatch) -> None:
    """Un montage lie vers le systeme de fichiers racine doit etre rejete."""
    point = tmp_path / "media"
    point.mkdir()

    monkeypatch.setattr("izerak_agent.storage.os.path.ismount", lambda _: True)

    status = probe(str(point), "Disque Emby")

    assert status.mounted is False
    assert status.reason == "same_device_as_root"


def test_volume_monte_calcule_le_quota(tmp_path: Path, monkeypatch) -> None:
    point = tmp_path / "media"
    point.mkdir()

    monkeypatch.setattr("izerak_agent.storage.os.path.ismount", lambda _: True)

    _force_distinct_devices(monkeypatch, point)
    monkeypatch.setattr(
        "izerak_agent.storage.shutil.disk_usage",
        lambda _: type("Usage", (), {"total": 2000, "used": 750, "free": 1250})(),
    )
    monkeypatch.setattr(
        "izerak_agent.storage.read_proc_mounts",
        lambda *_args, **_kwargs: MountInfo(device="/dev/sda1", fstype="ext4", readonly=False),
    )

    status = probe(str(point), "Disque Emby", quota_bytes=1000)

    assert status.mounted is True
    assert status.device == "/dev/sda1"
    assert status.readonly is False
    assert status.used_bytes == 750
    # Le quota est un plafond volontaire, distinct de la capacite reelle.
    assert status.quota_free_bytes == 250
    assert status.quota_ratio == pytest.approx(0.75)


def test_lecture_seule_est_signalee(tmp_path: Path, monkeypatch) -> None:
    """Un disque USB defaillant est remonte en lecture seule par le noyau."""
    point = tmp_path / "media"
    point.mkdir()

    monkeypatch.setattr("izerak_agent.storage.os.path.ismount", lambda _: True)

    _force_distinct_devices(monkeypatch, point)
    monkeypatch.setattr(
        "izerak_agent.storage.shutil.disk_usage",
        lambda _: type("Usage", (), {"total": 10, "used": 1, "free": 9})(),
    )
    monkeypatch.setattr(
        "izerak_agent.storage.read_proc_mounts",
        lambda *_args, **_kwargs: MountInfo(device="/dev/sda1", fstype="ext4", readonly=True),
    )

    status = probe(str(point), "Disque Emby")

    assert status.mounted is True
    assert status.readonly is True


def test_lecture_de_proc_mounts(tmp_path: Path) -> None:
    mounts = tmp_path / "mounts"
    mounts.write_text(
        "/dev/root / ext4 rw,relatime 0 0\n"
        "/dev/sda1 /mnt/disque\\040externe ext4 ro,nosuid 0 0\n",
        encoding="utf-8",
    )

    info = read_proc_mounts(Path("/mnt/disque externe"), mounts_file=mounts)

    assert info is not None
    assert info.device == "/dev/sda1"
    # Les espaces sont encodees en octal dans /proc/mounts.
    assert info.readonly is True

    assert read_proc_mounts(Path("/mnt/absent"), mounts_file=mounts) is None


def test_permission_refusee_ne_fait_pas_echouer_la_reponse(tmp_path: Path, monkeypatch) -> None:
    """Un volume inaccessible se signale, il ne leve pas.

    Les disques amovibles vivent sous /media/<utilisateur>, dont le parent n'est
    traversable que par son proprietaire : un compte de service s'y heurte a une
    PermissionError. Non rattrapee, elle renvoyait un 500 et emportait tous les
    autres volumes surveilles avec elle.
    """
    point = tmp_path / "media"
    point.mkdir()

    def refuse(self):  # noqa: ANN001
        raise PermissionError(13, "Permission denied")

    monkeypatch.setattr(Path, "is_dir", refuse)

    status = probe(str(point), "Disque Emby")

    assert status.mounted is False
    assert status.reason == "permission_denied"
    assert status.free_bytes is None


def test_sans_entree_de_montage_le_volume_n_est_pas_dit_en_lecture_seule(
    tmp_path: Path, monkeypatch
) -> None:
    """L'absence d'information de montage ne doit pas conclure a la lecture seule.

    L'agent tourne avec des droits minimaux et sous ProtectSystem=strict : il ne
    peut ecrire nulle part. Deduire l'etat du volume de sa propre incapacite a y
    ecrire rapportait un disque en lecture seule a tort, ce qui bloque l'ajout de
    telechargements cote application.
    """
    point = tmp_path / "media"
    point.mkdir()

    monkeypatch.setattr("izerak_agent.storage.os.path.ismount", lambda _: True)
    _force_distinct_devices(monkeypatch, point)
    monkeypatch.setattr(
        "izerak_agent.storage.shutil.disk_usage",
        lambda _: type("Usage", (), {"total": 10, "used": 1, "free": 9})(),
    )
    monkeypatch.setattr("izerak_agent.storage.read_proc_mounts", lambda *a, **k: None)

    status = probe(str(point), "Disque Emby")

    assert status.mounted is True
    assert status.readonly is False
    assert status.free_bytes == 9
