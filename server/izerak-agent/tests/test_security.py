"""Tests de la liste blanche d'unites, de l'authentification et du decodage
des drapeaux de bridage.

Le test le plus important est celui de l'injection : un nom d'unite fabrique ne
doit jamais atteindre systemctl, et aucun processus ne doit etre lance.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from izerak_agent import metrics
from izerak_agent.config import AgentConfig, ConfigError, ServiceEntry, load
from izerak_agent.main import app, config

TOKEN = "un-jeton-de-test-suffisamment-long-pour-passer"


@pytest.fixture()
def settings() -> AgentConfig:
    return AgentConfig(
        token=TOKEN,
        services=[ServiceEntry(name="emby", unit="emby-server.service")],
        storage=[],
    )


@pytest.fixture()
def client(settings: AgentConfig) -> TestClient:
    app.dependency_overrides[config] = lambda: settings
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_jeton_absent(client: TestClient) -> None:
    assert client.get("/api/v1/health").status_code == 401


def test_jeton_invalide(client: TestClient) -> None:
    response = client.get("/api/v1/health", headers={"Authorization": "Bearer faux"})
    assert response.status_code == 401


def test_jeton_valide(client: TestClient) -> None:
    response = client.get("/api/v1/health", headers={"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 200
    assert "version" in response.json()


def test_unite_inconnue_est_refusee_sans_executer(client: TestClient, monkeypatch) -> None:
    appels: list = []
    monkeypatch.setattr(
        "izerak_agent.main.apply", lambda *args: appels.append(args)
    )

    response = client.post(
        "/api/v1/services/inconnu/restart",
        headers={"Authorization": f"Bearer {TOKEN}"},
    )

    assert response.status_code == 404
    assert appels == []


def test_tentative_injection(client: TestClient, monkeypatch) -> None:
    """Le nom recu sert de cle de recherche, jamais d'argument de commande."""
    appels: list = []
    monkeypatch.setattr("izerak_agent.main.apply", lambda *args: appels.append(args))

    response = client.post(
        "/api/v1/services/emby-server.service; rm -rf ~/restart",
        headers={"Authorization": f"Bearer {TOKEN}"},
    )

    assert response.status_code in (404, 405)
    assert appels == []


def test_action_hors_enum_est_refusee(client: TestClient, monkeypatch) -> None:
    appels: list = []
    monkeypatch.setattr("izerak_agent.main.apply", lambda *args: appels.append(args))

    response = client.post(
        "/api/v1/services/emby/reboot",
        headers={"Authorization": f"Bearer {TOKEN}"},
    )

    # L'enum FastAPI n'accepte que start, stop et restart.
    assert response.status_code == 422
    assert appels == []


def test_unit_for_ne_renvoie_que_les_unites_declarees(settings: AgentConfig) -> None:
    assert settings.unit_for("emby") == "emby-server.service"
    assert settings.unit_for("emby-server.service") is None
    assert settings.unit_for("../../etc/passwd") is None


def test_interface_web_publiee_avec_l_etat(settings: AgentConfig, monkeypatch) -> None:
    from izerak_agent.systemd import ServiceStatus

    monkeypatch.setattr(
        "izerak_agent.main.status",
        lambda name, unit: ServiceStatus(name, unit, "active", "running", True, None, None),
    )
    avec_web = AgentConfig(
        token=TOKEN,
        services=[
            ServiceEntry(name="emby", unit="emby-server.service"),
            ServiceEntry(name="cora", unit="commandes-coraboeuf.service", web_port=5000),
        ],
    )
    app.dependency_overrides[config] = lambda: avec_web
    try:
        response = TestClient(app).get(
            "/api/v1/services", headers={"Authorization": f"Bearer {TOKEN}"}
        )
    finally:
        app.dependency_overrides.clear()

    services = {item["name"]: item for item in response.json()["services"]}
    assert services["emby"]["web"] is None
    assert services["cora"]["web"] == {"scheme": "http", "port": 5000, "path": "/"}


def test_configuration_web_lue_et_validee(tmp_path: Path) -> None:
    config_file = tmp_path / "config.yaml"
    config_file.write_text(
        f'token: "{TOKEN}"\n'
        "services:\n"
        "  - name: cora\n"
        "    unit: commandes-coraboeuf.service\n"
        "    web_port: 5000\n"
        "    web_path: recap\n",
        encoding="utf-8",
    )
    entry = load(config_file).entry_for("cora")
    assert entry is not None
    assert entry.web() == {"scheme": "http", "port": 5000, "path": "/recap"}

    config_file.write_text(
        f'token: "{TOKEN}"\n'
        "services:\n"
        "  - name: cora\n"
        "    unit: commandes-coraboeuf.service\n"
        "    web_port: 99999\n",
        encoding="utf-8",
    )
    with pytest.raises(ConfigError):
        load(config_file)


def test_jeton_trop_court_est_refuse(tmp_path: Path) -> None:
    config_file = tmp_path / "config.yaml"
    config_file.write_text('token: "court"\n', encoding="utf-8")

    with pytest.raises(ConfigError):
        load(config_file)


def test_decodage_des_drapeaux_de_bridage(monkeypatch) -> None:
    # 0x50005 : sous-tension actuelle et survenue, plus bridage survenu.
    monkeypatch.setattr("izerak_agent.metrics.shutil.which", lambda _: "/usr/bin/vcgencmd")
    monkeypatch.setattr(
        "izerak_agent.metrics.subprocess.run",
        lambda *args, **kwargs: type(
            "Result", (), {"returncode": 0, "stdout": "throttled=0x50005\n"}
        )(),
    )

    flags = metrics.throttled()

    assert flags["available"] is True
    assert flags["under_voltage_now"] is True
    assert flags["under_voltage_occurred"] is True
    assert flags["throttling_occurred"] is True
    assert flags["arm_frequency_capped_now"] is False


def test_bridage_indisponible_hors_raspberry(monkeypatch) -> None:
    monkeypatch.setattr("izerak_agent.metrics.shutil.which", lambda _: None)
    assert metrics.throttled() == {"available": False}
