"""Tests du releve du temps de jeu : une panne ne vaut jamais « 0 h »."""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from izerak_agent import gaming
from izerak_agent.config import AgentConfig, ConfigError, GamingConfig, load
from izerak_agent.main import app, config

TOKEN = "un-jeton-de-test-suffisamment-long-pour-passer"
PARIS = ZoneInfo("Europe/Paris")
STEAM_ONLY = GamingConfig(steam_api_key="cle-steam", steam_id="7656")
LOL_ONLY = GamingConfig(riot_api_key="cle-riot", riot_game_name="Pseudo", riot_tag_line="EUW")
BOTH = GamingConfig(
    steam_api_key="cle-steam",
    steam_id="7656",
    riot_api_key="cle-riot",
    riot_game_name="Pseudo",
    riot_tag_line="EUW",
)


def steam(**totals: int):
    games = [
        {"appid": int(app[1:]), "name": app, "playtime_forever": minutes}
        for app, minutes in totals.items()
    ]
    return lambda url, headers: {"response": {"games": games}}


def at(day: int, hour: int = 12) -> datetime:
    return datetime(2026, 11, day, hour, tzinfo=PARIS)


def test_le_premier_releve_steam_ne_compte_pas_le_cumul() -> None:
    state = gaming.empty_state()
    gaming.poll_steam(STEAM_ONLY, state, at(22), steam(a1=5000))
    assert state["days"]["2026-11-22"]["steam"] == {}
    assert state["steam"]["since"] == "2026-11-22"


def test_le_temps_steam_est_la_difference_entre_deux_releves() -> None:
    state = gaming.empty_state()
    gaming.poll_steam(STEAM_ONLY, state, at(22), steam(a1=100))
    gaming.poll_steam(STEAM_ONLY, state, at(23), steam(a1=190))
    assert state["days"]["2026-11-23"]["steam"] == {"1": 90}


def test_un_profil_prive_nest_pas_zero_heure() -> None:
    state = gaming.empty_state()
    with pytest.raises(gaming.GamingError) as error:
        gaming.poll_steam(STEAM_ONLY, state, at(22), lambda url, headers: {"response": {}})
    assert error.value.code == "profile_private"
    assert state["days"] == {}


def test_un_jeu_qui_reapparait_ne_verse_pas_son_cumul() -> None:
    state = gaming.empty_state()
    gaming.poll_steam(STEAM_ONLY, state, at(22), steam(a1=10))
    gaming.poll_steam(STEAM_ONLY, state, at(22, 13), steam(a1=10, a2=9000))
    assert state["days"]["2026-11-22"]["steam"] == {}


def test_un_vieux_jeu_de_retour_ne_compte_pas_meme_sous_la_marge() -> None:
    state = gaming.empty_state()
    gaming.poll_steam(STEAM_ONLY, state, at(22), steam(a1=10))
    old = {"appid": 2, "name": "x", "playtime_forever": 480, "rtime_last_played": 1000}
    fetch = lambda url, headers: {"response": {"games": [old]}}
    gaming.poll_steam(STEAM_ONLY, state, at(22, 13), fetch)
    assert state["days"]["2026-11-22"]["steam"] == {}


def test_un_jeu_tout_juste_lance_compte() -> None:
    state = gaming.empty_state()
    gaming.poll_steam(STEAM_ONLY, state, at(22), steam(a1=10))
    new = {
        "appid": 2,
        "name": "x",
        "playtime_forever": 120,
        "rtime_last_played": int(at(22, 13).timestamp()),
    }
    fetch = lambda url, headers: {"response": {"games": [new]}}
    gaming.poll_steam(STEAM_ONLY, state, at(22, 13), fetch)
    assert state["days"]["2026-11-22"]["steam"] == {"2": 120}


def test_un_creux_du_cumul_nest_pas_recompte() -> None:
    state = gaming.empty_state()
    gaming.poll_steam(STEAM_ONLY, state, at(23, 10), steam(a1=5000))
    gaming.poll_steam(STEAM_ONLY, state, at(23, 11), steam(a1=4700))
    gaming.poll_steam(STEAM_ONLY, state, at(23, 12), steam(a1=5000))
    assert state["days"]["2026-11-23"]["steam"] == {}


def test_un_changement_de_compte_ninvente_pas_de_temps() -> None:
    state = gaming.empty_state()
    gaming.poll(STEAM_ONLY, state, at(22), steam(a1=100))
    other = GamingConfig(steam_api_key="cle-steam", steam_id="9999")
    gaming.poll(other, state, at(23), steam(a1=5000))
    assert state["days"]["2026-11-23"]["steam"] == {}
    assert state["steam"]["since"] == "2026-11-23"


def match(started: datetime, seconds: int, win: bool, remake: bool = False) -> dict:
    return {
        "info": {
            "gameStartTimestamp": int(started.timestamp() * 1000),
            "gameEndTimestamp": int(started.timestamp() * 1000) + seconds * 1000,
            "gameDuration": seconds,
            "participants": [
                {"puuid": "moi", "win": win, "gameEndedInEarlySurrender": remake},
            ],
        }
    }


def riot(matches: dict, failing: dict = None):
    failing = failing or {}

    def fetch(url: str, headers: dict):
        assert headers["X-Riot-Token"] == "cle-riot"
        if "/accounts/" in url:
            return {"puuid": "moi"}
        if "/ids?" in url:
            return list(reversed(list(matches)))
        match_id = url.rsplit("/", 1)[1]
        if match_id in failing:
            raise gaming.GamingError(failing[match_id])
        return matches[match_id]

    return fetch


def test_les_parties_lol_se_comptent_une_fois_sans_les_remakes() -> None:
    state = gaming.empty_state()
    gaming.poll_lol(LOL_ONLY, state, at(23, 8), riot({}))
    matches = {
        "EUW1_1": match(at(23, 20), 1800, True),
        "EUW1_2": match(at(23, 21), 1500, False),
        "EUW1_3": match(at(23, 22), 200, False, remake=True),
    }
    gaming.poll_lol(LOL_ONLY, state, at(23, 23), riot(matches))
    gaming.poll_lol(LOL_ONLY, state, at(24, 0), riot(matches))

    day = state["days"]["2026-11-23"]
    assert (day["lol_minutes"], day["lol_games"], day["lol_wins"]) == (55, 2, 1)


def test_une_erreur_en_cours_de_lot_ne_fait_pas_recompter() -> None:
    state = gaming.empty_state()
    gaming.poll_lol(LOL_ONLY, state, at(23, 8), riot({}))
    matches = {"A": match(at(23, 20), 1800, True), "B": match(at(23, 21), 1500, True)}
    for hour in (22, 23):
        gaming.poll(LOL_ONLY, state, at(23, hour), riot(matches, {"B": "rate_limited"}))
    assert state["days"]["2026-11-23"]["lol_minutes"] == 30
    assert "lol" not in state["days"]["2026-11-23"]["measured"][1:]

    gaming.poll(LOL_ONLY, state, at(24, 0), riot(matches))
    assert state["days"]["2026-11-23"]["lol_minutes"] == 55


def test_une_partie_disparue_ne_bloque_pas_les_suivantes() -> None:
    state = gaming.empty_state()
    gaming.poll_lol(LOL_ONLY, state, at(23, 8), riot({}))
    matches = {"A": match(at(23, 20), 60, True), "B": match(at(23, 21), 1800, True)}
    gaming.poll(LOL_ONLY, state, at(23, 22), riot(matches, {"A": "not_found"}))
    assert state["days"]["2026-11-23"]["lol_minutes"] == 30
    assert state["errors"] == {}


def test_une_partie_mal_formee_nannule_pas_le_releve() -> None:
    state = gaming.empty_state()
    gaming.poll_lol(LOL_ONLY, state, at(23, 8), riot({}))
    gaming.poll(LOL_ONLY, state, at(23, 22), riot({"A": {"info": {"participants": 5}}}))
    assert state["errors"] == {}
    assert state["lol"]["seen"] == ["A"]


def final_week(monday: date) -> dict:
    """Une semaine Steam relevee a ses deux bouts, lundi suivant franchi."""
    state = gaming.empty_state()
    state["steam"]["since"] = (monday - timedelta(days=1)).isoformat()
    next_monday = monday + timedelta(days=7)
    state["steam"]["polled_at"] = datetime(
        next_monday.year, next_monday.month, next_monday.day, 1, tzinfo=PARIS
    ).timestamp()
    for offset in (0, 6):
        state["days"][(monday + timedelta(days=offset)).isoformat()] = {
            "steam": {"1": 60},
            "lol_minutes": 0,
            "lol_games": 0,
            "lol_wins": 0,
            "measured": ["steam"],
        }
    return state


def test_une_semaine_est_definitive_une_fois_le_lundi_suivant_franchi() -> None:
    monday = date(2026, 11, 23)
    summary = gaming.week_summary(STEAM_ONLY, final_week(monday), monday)
    assert (summary["minutes"], summary["complete"], summary["measured"]) == (120, True, True)


def test_le_dimanche_en_cours_est_mesure_mais_pas_definitif() -> None:
    monday = date(2026, 11, 23)
    state = final_week(monday)
    state["steam"]["polled_at"] = at(29, 18).timestamp()
    summary = gaming.week_summary(STEAM_ONLY, state, monday)
    assert (summary["complete"], summary["measured"]) == (False, True)


def test_la_semaine_du_premier_releve_est_incomplete() -> None:
    monday = date(2026, 11, 23)
    state = final_week(monday)
    state["steam"]["since"] = "2026-11-23"
    assert not gaming.week_summary(STEAM_ONLY, state, monday)["complete"]


def test_un_trou_qui_franchit_un_lundi_invalide_les_deux_semaines() -> None:
    state = gaming.empty_state()
    gaming.poll_steam(STEAM_ONLY, state, at(15), steam(a1=0))
    for day in (16, 20):
        gaming.poll_steam(STEAM_ONLY, state, at(day), steam(a1=0))
    # Pi eteint du vendredi 20 au lundi 23, puis releves normaux.
    gaming.poll_steam(STEAM_ONLY, state, at(23, 9), steam(a1=600))
    for day in (29, 30):
        gaming.poll_steam(STEAM_ONLY, state, at(day), steam(a1=600))

    assert not gaming.week_summary(STEAM_ONLY, state, date(2026, 11, 16))["complete"]
    assert not gaming.week_summary(STEAM_ONLY, state, date(2026, 11, 23))["complete"]


def test_ajouter_une_source_ne_rend_pas_le_passe_incomplet() -> None:
    monday = date(2026, 11, 2)
    state = final_week(monday)
    state["steam"]["tracked_from"] = "2026-11-01"
    state["lol"]["tracked_from"] = "2026-11-20"
    assert gaming.week_summary(BOTH, state, monday)["complete"]
    assert not gaming.week_summary(BOTH, state, date(2026, 11, 16))["complete"]


def test_une_partie_du_dimanche_soir_attend_lundi_3h() -> None:
    monday = date(2026, 11, 23)
    state = gaming.empty_state()
    state["lol"].update(since="2026-11-22", synced_at=int(at(30, 1).timestamp()))
    assert not gaming.week_summary(LOL_ONLY, state, monday)["complete"]
    state["lol"]["tracked_from"] = "2026-11-22"
    assert not gaming.week_summary(LOL_ONLY, state, monday)["complete"]
    state["lol"]["synced_at"] = int(at(30, 3).timestamp())
    assert gaming.week_summary(LOL_ONLY, state, monday)["complete"]


def test_une_source_en_panne_nempeche_pas_lautre() -> None:
    def fetch(url: str, headers: dict):
        if "steampowered" in url:
            return {"response": {"games": []}}
        raise gaming.GamingError("unauthorized")

    state = gaming.empty_state()
    gaming.poll(BOTH, state, at(22), fetch)
    assert state["errors"] == {"lol": "unauthorized"}
    assert state["days"]["2026-11-22"]["measured"] == ["steam"]


def test_une_erreur_imprevue_nempeche_pas_lautre_source() -> None:
    def fetch(url: str, headers: dict):
        if "steampowered" in url:
            raise TypeError("forme imprevue")
        if "/accounts/" in url:
            return {"puuid": "moi"}
        return []

    state = gaming.empty_state()
    gaming.poll(BOTH, state, at(22), fetch)
    assert state["errors"] == {"steam": "unexpected"}
    assert state["days"]["2026-11-22"]["measured"] == ["lol"]


def test_un_fichier_abime_est_mis_de_cote_et_non_ecrase(tmp_path: Path) -> None:
    path = tmp_path / "gaming.json"
    path.write_text('{"version": 1, "days"', encoding="utf-8")
    gaming.poll_once(GamingConfig(steam_api_key="k", steam_id="1"), path, steam(a1=1))
    kept = list(tmp_path.glob("gaming.json.corrompu-*"))
    assert len(kept) == 1 and kept[0].read_text(encoding="utf-8") == '{"version": 1, "days"'
    assert json.loads(path.read_text(encoding="utf-8"))["steam"]["totals"] == {"1": 1}


def test_une_panne_de_lecture_ne_touche_pas_au_fichier(tmp_path: Path, monkeypatch) -> None:
    path = tmp_path / "gaming.json"
    gaming.save_state(path, gaming.empty_state())
    before = path.read_text(encoding="utf-8")

    def broken(self, encoding=None):
        raise OSError("EIO")

    monkeypatch.setattr(Path, "read_text", broken)
    with pytest.raises(gaming.GamingStateError):
        gaming.poll_once(GamingConfig(steam_api_key="k", steam_id="1"), path, steam(a1=1))
    monkeypatch.undo()
    assert path.read_text(encoding="utf-8") == before


@pytest.mark.parametrize(
    "raw",
    [
        {"version": 1, "days": None},
        {"version": 1, "steam": None},
        {"version": 1, "days": {"2026-11-23": {"steam": {}, "measured": []}}},
        {"version": 1, "steam": {"totals": {"1": "x"}}},
    ],
)
def test_un_etat_de_forme_invalide_est_refuse(tmp_path: Path, raw: dict) -> None:
    path = tmp_path / "gaming.json"
    path.write_text(json.dumps(raw), encoding="utf-8")
    with pytest.raises(gaming.GamingStateError):
        gaming.load_state(path)


def test_un_nom_avec_demi_caractere_se_sauvegarde(tmp_path: Path) -> None:
    path = tmp_path / "gaming.json"
    state = gaming.empty_state()
    state["steam"]["names"] = {"1": json.loads('"jeu \\ud83d"')}
    gaming.save_state(path, state)
    assert gaming.load_state(path)["steam"]["names"]["1"] == "jeu \ud83d"


def test_les_redirections_ne_sont_pas_suivies() -> None:
    handler = gaming._NoRedirect()
    assert handler.redirect_request(None, None, 302, "Found", {}, "http://autre.example/") is None


@pytest.fixture()
def client(tmp_path: Path):
    settings = AgentConfig(
        token=TOKEN,
        gaming=GamingConfig(
            steam_api_key="cle-steam-secrete",
            steam_id="7656",
            state_path=str(tmp_path / "gaming.json"),
        ),
    )
    app.dependency_overrides[config] = lambda: settings
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_le_rapport_exige_le_jeton_et_ne_dit_pas_les_cles(client: TestClient) -> None:
    assert client.get("/api/v1/gaming").status_code == 401
    response = client.get("/api/v1/gaming", headers={"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 200
    assert response.json()["sources"] == ["steam"]
    assert "cle-steam-secrete" not in response.text


def test_un_etat_illisible_repond_503(client: TestClient, tmp_path: Path) -> None:
    (tmp_path / "gaming.json").write_text("abime", encoding="utf-8")
    response = client.get("/api/v1/gaming", headers={"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 503


def test_le_jeton_derive_nouvre_que_le_total_de_la_semaine(client: TestClient) -> None:
    derived = {"Authorization": f"Bearer {gaming.notify_token(TOKEN)}"}
    response = client.get("/api/v1/gaming/week?monday=2026-11-23", headers=derived)
    assert response.status_code == 200
    assert set(response.json()) == {"minutes", "measured"}
    assert client.get("/api/v1/gaming", headers=derived).status_code == 401
    assert client.get("/api/v1/system", headers=derived).status_code == 401
    assert client.post("/api/v1/services/emby/restart", headers=derived).status_code == 401


def test_la_semaine_attend_un_lundi(client: TestClient) -> None:
    derived = {"Authorization": f"Bearer {gaming.notify_token(TOKEN)}"}
    for monday in ("2026-11-24", "x", "9999-12-27"):
        response = client.get(f"/api/v1/gaming/week?monday={monday}", headers=derived)
        assert response.status_code == 422


def test_une_region_inconnue_est_refusee(tmp_path: Path) -> None:
    path = tmp_path / "config.yaml"
    path.write_text(
        f'token: "{TOKEN}"\ngaming:\n  riot:\n    region: "evil.example#"\n', encoding="utf-8"
    )
    with pytest.raises(ConfigError):
        load(path)


def test_un_fuseau_inconnu_est_refuse(tmp_path: Path) -> None:
    path = tmp_path / "config.yaml"
    path.write_text(f'token: "{TOKEN}"\ngaming:\n  timezone: Europe/Pari\n', encoding="utf-8")
    with pytest.raises(ConfigError):
        load(path)


def test_le_compte_sea_se_lit_sur_asia() -> None:
    urls = []

    def fetch(url: str, headers: dict):
        urls.append(url)
        return {"puuid": "moi"} if "/accounts/" in url else []

    settings = GamingConfig(
        riot_api_key="k", riot_game_name="P", riot_tag_line="T", riot_region="sea"
    )
    gaming.poll_lol(settings, gaming.empty_state(), at(22), fetch)
    assert urls[0].startswith("https://asia.api.riotgames.com/riot/account/")
    assert urls[1].startswith("https://sea.api.riotgames.com/lol/match/")


def test_les_cles_ne_paraissent_pas_dans_la_representation() -> None:
    assert "cle-steam" not in repr(STEAM_ONLY)
