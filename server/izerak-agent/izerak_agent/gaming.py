"""Releve du temps de jeu : Steam et League of Legends.

Les deux sources ne se mesurent pas de la meme facon.

  - Steam ne publie qu'un cumul par jeu, sans historique date. Le temps d'une
    journee est donc la difference entre deux releves, ce qui oblige a relever
    depuis une machine toujours allumee plutot que depuis le telephone.
  - Riot publie chaque partie avec sa date et sa duree.

Une panne ne doit jamais se lire comme « 0 h de jeu » : une reponse vide ou en
erreur ne marque pas la journee comme mesuree. Une semaine n'est definitive
qu'une fois franchi le lundi suivant, sans trou autour de ses deux bords.

Les cles d'API restent dans la configuration de l'agent. Elles ne figurent ni
dans l'etat enregistre, ni dans les reponses, ni dans les journaux : les erreurs
sont reduites a un code, parce qu'un message d'urllib peut citer l'adresse, et
celle de Steam porte la cle.
"""

from __future__ import annotations

import hashlib
import hmac
import http.client
import json
import logging
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from datetime import time as day_time
from pathlib import Path
from typing import Callable, Optional
from zoneinfo import ZoneInfo

from izerak_agent.config import GamingConfig

log = logging.getLogger("izerak_agent.gaming")

STEAM = "steam"
LOL = "lol"

_STEAM_URL = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
_HTTP_TIMEOUT_SECONDS = 15

# Le pare-feu devant l'API Riot rejette l'en-tete par defaut d'urllib
# (« Python-urllib/x.y ») par un 403, que rien ne distingue d'une cle refusee.
_USER_AGENT = "izerak-agent/1.0"

# Garde-fou du calcul par difference : un jeu qui reapparait apres un retrait
# de la bibliotheque ne doit pas verser tout son cumul sur la journee.
_STEAM_MARGIN_MINUTES = 12 * 60

# Au-dela, un trou entre deux releves Steam qui franchit un lundi ne permet plus
# de dire de quelle semaine vient le temps joue.
_STEAM_BOUNDARY_GAP_MINUTES = 3 * 60

# Riot limite le debit des cles personnelles : le reste attend le releve suivant.
_LOL_MAX_MATCHES_PER_POLL = 20
_LOL_LOOKBACK_SECONDS = 14 * 24 * 3600
_LOL_SEEN_KEPT = 500

# Une partie commencee dimanche soir n'apparait qu'une fois terminee, et se
# range sous son jour de debut : la semaine attend donc lundi 3 h pour se figer.
_LOL_SETTLE_HOURS = 3

_DAYS_KEPT = 120
_WEEKS_REPORTED = 10

# Ce que l'etat enregistre ne peut pas dire, puisque c'est lui qui a echoue.
_runtime_errors: dict = {}

Fetch = Callable[[str, dict], object]


class GamingError(RuntimeError):
    """Un releve qui a echoue. Le code est le seul detail qui sort d'ici."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


class GamingStateError(RuntimeError):
    """L'etat existe mais n'a pas pu etre relu.

    Surtout pas un etat vide : il serait ensuite enregistre par-dessus le vrai.
    """

    def __init__(self, corrupt: bool) -> None:
        super().__init__("corrupt" if corrupt else "unreadable")
        self.corrupt = corrupt


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """urllib recopie tous les en-tetes vers la cible d'une redirection, y
    compris la cle Riot, meme vers un autre hote ou en clair."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def fetch_json(url: str, headers: dict) -> object:
    request = urllib.request.Request(
        url, headers={"Accept": "application/json", "User-Agent": _USER_AGENT, **headers}
    )
    try:
        with _opener.open(request, timeout=_HTTP_TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise GamingError("unauthorized") from None
        if error.code == 404:
            raise GamingError("not_found") from None
        if error.code == 429:
            raise GamingError("rate_limited") from None
        raise GamingError("unavailable") from None
    except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError, ValueError):
        # « from None » : la cause citerait l'adresse, donc la cle Steam.
        raise GamingError("unavailable") from None


def notify_token(agent_token: str) -> str:
    """Le jeton de la notification du dimanche, derive du jeton de l'agent.

    Le natif Android doit joindre le Pi application fermee, sans acces au
    stockage securise. Ce jeton-la n'ouvre que le total d'une semaine : s'il
    fuit, il ne donne aucun pouvoir sur les services.
    """
    return hmac.new(agent_token.encode(), b"izerak-gaming-notify", hashlib.sha256).hexdigest()


def empty_state() -> dict:
    return {"version": 1, STEAM: {}, LOL: {}, "days": {}, "errors": {}}


def _is_count(value: object) -> bool:
    # bool herite de int.
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _valid_day(day: object) -> bool:
    return (
        isinstance(day, dict)
        and isinstance(day.get("steam"), dict)
        and all(_is_count(minutes) for minutes in day["steam"].values())
        and all(_is_count(day.get(field)) for field in ("lol_minutes", "lol_games", "lol_wins"))
        and isinstance(day.get("measured"), list)
    )


def _valid_source(source: dict) -> bool:
    totals = source.get("totals", {})
    return (
        isinstance(totals, dict)
        and all(_is_count(minutes) for minutes in totals.values())
        and isinstance(source.get("names", {}), dict)
        and isinstance(source.get("seen", []), list)
        and isinstance(source.get("broken", []), list)
        and all(
            isinstance(source.get(field, 0), (int, float))
            and not isinstance(source.get(field, 0), bool)
            for field in ("polled_at", "started_at", "synced_at")
        )
        and all(
            isinstance(source.get(field, ""), str)
            for field in ("since", "tracked_from", "account")
        )
    )


def _valid_state(raw: object) -> bool:
    if not isinstance(raw, dict) or raw.get("version") != 1:
        return False
    for key in (STEAM, LOL, "days", "errors"):
        if key in raw and not isinstance(raw[key], dict):
            return False
    return (
        _valid_source(raw.get(STEAM, {}))
        and _valid_source(raw.get(LOL, {}))
        and all(_valid_day(day) for day in raw.get("days", {}).values())
    )


def load_state(path: Path) -> dict:
    """L'etat enregistre. Seul un fichier absent vaut un etat vide."""
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return empty_state()
    except OSError as error:
        raise GamingStateError(corrupt=False) from error
    except ValueError as error:
        raise GamingStateError(corrupt=True) from error
    try:
        raw = json.loads(text)
    except ValueError as error:
        raise GamingStateError(corrupt=True) from error
    if not _valid_state(raw):
        raise GamingStateError(corrupt=True)
    return {**empty_state(), **raw}


def save_state(path: Path, state: dict) -> None:
    # Ecriture atomique et forcee sur le support : une coupure de courant ne
    # doit pas perdre les cumuls Steam, donc tout l'historique a venir. En ASCII,
    # parce qu'un nom de jeu peut porter un demi-caractere que UTF-8 refuse.
    temporary = path.with_suffix(".tmp")
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)
    if hasattr(os, "O_DIRECTORY"):
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)


def _set_aside(path: Path) -> None:
    """Garde un fichier illisible pour un examen a la main."""
    os.replace(path, path.with_name(f"{path.name}.corrompu-{int(time.time())}"))


def _monday(day: date) -> date:
    return day - timedelta(days=day.weekday())


def _day(state: dict, key: str) -> dict:
    return state["days"].setdefault(
        key, {"steam": {}, "lol_minutes": 0, "lol_games": 0, "lol_wins": 0, "measured": []}
    )


def _mark_measured(state: dict, source: str, key: str) -> None:
    measured = _day(state, key)["measured"]
    if source not in measured:
        measured.append(source)


def _mark_broken(source: dict, before: float, now: datetime) -> None:
    """Note chaque lundi franchi pendant un trou dans les releves."""
    monday = _monday(datetime.fromtimestamp(before, now.tzinfo).date()) + timedelta(days=7)
    last = _monday(now.date())
    broken = source.setdefault("broken", [])
    while monday <= last:
        if monday.isoformat() not in broken:
            broken.append(monday.isoformat())
        monday += timedelta(days=7)


def _recently_played(game: dict, total: int, last_poll: float, elapsed: float, limit: float) -> bool:
    """Le cumul d'un jeu tout juste apparu est-il du temps recent ?"""
    last_played = game.get("rtime_last_played")
    if _is_count(last_played) and last_played > 0:
        return last_played >= last_poll - _STEAM_MARGIN_MINUTES * 60 and total <= limit
    return total <= elapsed


def poll_steam(settings: GamingConfig, state: dict, now: datetime, fetch: Fetch = fetch_json) -> None:
    query = urllib.parse.urlencode(
        {
            "key": settings.steam_api_key,
            "steamid": settings.steam_id,
            "include_appinfo": 1,
            "include_played_free_games": 1,
            "format": "json",
        }
    )
    body = fetch(f"{_STEAM_URL}?{query}", {})
    response = body.get("response") if isinstance(body, dict) else None
    games = response.get("games") if isinstance(response, dict) else None
    # Un profil dont les details de jeu sont prives repond 200 et un objet
    # vide : surtout pas « aucune heure jouee ».
    if not isinstance(games, list):
        raise GamingError("profile_private")

    source = state[STEAM]
    today = now.date().isoformat()
    previous = source.get("totals")
    last_poll = source.get("polled_at") or 0
    elapsed = max(0, (now.timestamp() - last_poll) / 60) if last_poll else 0
    limit = elapsed + _STEAM_MARGIN_MINUTES

    # Tout est calcule avant d'ecrire : une reponse abimee ne laisse pas un
    # temps credite sans le cumul qui empeche de le recompter.
    totals: dict = {}
    names = dict(source.get("names") or {})
    credited: dict = {}
    for game in games:
        if not isinstance(game, dict) or not _is_count(game.get("appid")):
            continue
        app = str(game["appid"])
        total = game.get("playtime_forever")
        if not _is_count(total):
            continue
        if isinstance(game.get("name"), str):
            names[app] = game["name"]
        if previous is None:
            totals[app] = total
        elif app in previous:
            # Le plus haut cumul connu : un creux passager ne doit pas etre
            # recompte quand la valeur remonte.
            totals[app] = max(total, previous[app])
            delta = min(max(0, total - previous[app]), int(limit))
            if delta > 0:
                credited[app] = delta
        else:
            totals[app] = total
            if total > 0 and _recently_played(game, total, last_poll, elapsed, limit):
                credited[app] = total

    if previous is None:
        source["since"] = today
    else:
        # Un jeu retire de la bibliotheque garde son cumul, pour ne pas etre
        # recompte s'il revient.
        totals = {**previous, **totals}
        if last_poll and elapsed > _STEAM_BOUNDARY_GAP_MINUTES:
            _mark_broken(source, last_poll, now)
    played = _day(state, today)["steam"]
    for app, delta in credited.items():
        played[app] = played.get(app, 0) + delta
    source.update(totals=totals, names=names, polled_at=now.timestamp())
    _mark_measured(state, STEAM, today)


def poll_lol(settings: GamingConfig, state: dict, now: datetime, fetch: Fetch = fetch_json) -> None:
    base = f"https://{settings.riot_region}.api.riotgames.com"
    # account-v1 n'existe pas sur « sea » : ces comptes se lisent sur « asia ».
    account_region = "asia" if settings.riot_region == "sea" else settings.riot_region
    account_base = f"https://{account_region}.api.riotgames.com"
    headers = {"X-Riot-Token": settings.riot_api_key}
    name = urllib.parse.quote(settings.riot_game_name, safe="")
    tag = urllib.parse.quote(settings.riot_tag_line, safe="")

    # Relu a chaque fois : le PUUID est chiffre par cle, il change donc quand
    # on passe de la cle de developpement a la cle personnelle.
    account = fetch(f"{account_base}/riot/account/v1/accounts/by-riot-id/{name}/{tag}", headers)
    puuid = account.get("puuid") if isinstance(account, dict) else None
    if not isinstance(puuid, str):
        raise GamingError("unavailable")

    source = state[LOL]
    today = now.date().isoformat()
    started = source.get("started_at")
    if started is None:
        started = int(now.timestamp())
        source.update(started_at=started, since=today, seen=[])
    start = max(started, int(now.timestamp()) - _LOL_LOOKBACK_SECONDS)
    # Une panne plus longue que la fenetre de lecture perd des parties.
    synced = source.get("synced_at")
    if synced is not None and synced < start:
        _mark_broken(source, synced, datetime.fromtimestamp(start, now.tzinfo))

    identifiers = fetch(
        f"{base}/lol/match/v5/matches/by-puuid/{puuid}/ids?startTime={start}&count=100", headers
    )
    if not isinstance(identifiers, list):
        raise GamingError("unavailable")

    seen = list(source.get("seen") or [])
    known = set(seen)
    # Du plus ancien au plus recent : Riot renvoie l'inverse.
    fresh = [
        match for match in reversed(identifiers) if isinstance(match, str) and match not in known
    ]
    for match_id in fresh[:_LOL_MAX_MATCHES_PER_POLL]:
        try:
            match = fetch(
                f"{base}/lol/match/v5/matches/{urllib.parse.quote(match_id, safe='')}", headers
            )
        except GamingError as error:
            # Une partie disparue reviendrait en tete a chaque releve et
            # bloquerait toutes les suivantes. Les autres erreurs se retentent.
            if error.code != "not_found":
                raise
            log.warning("Partie LoL introuvable, ecartee")
            match = None
        _record_match(state, settings, match, puuid)
        # Partie par partie : une erreur sur la suivante ne doit pas faire
        # recompter celle-ci.
        seen.append(match_id)
        source["seen"] = seen[-_LOL_SEEN_KEPT:]

    # Des parties restent a lire : la journee n'est pas encore mesuree.
    if len(fresh) <= _LOL_MAX_MATCHES_PER_POLL:
        source["synced_at"] = int(now.timestamp())
        _mark_measured(state, LOL, today)


def _record_match(state: dict, settings: GamingConfig, match: object, puuid: str) -> None:
    info = match.get("info") if isinstance(match, dict) else None
    participants = info.get("participants") if isinstance(info, dict) else None
    if not isinstance(participants, list):
        return
    player = next(
        (p for p in participants if isinstance(p, dict) and p.get("puuid") == puuid),
        None,
    )
    started = info.get("gameStartTimestamp")
    duration = info.get("gameDuration")
    if player is None or not _is_count(started) or not _is_count(duration):
        return
    # Une partie annulee en debut de jeu n'a pas ete jouee.
    if player.get("gameEndedInEarlySurrender") is True:
        return
    # Les anciennes parties, sans gameEndTimestamp, sont en millisecondes.
    seconds = duration if "gameEndTimestamp" in info else duration / 1000
    try:
        when = datetime.fromtimestamp(started / 1000, ZoneInfo(settings.timezone))
    except (OverflowError, ValueError, OSError):
        return
    day = _day(state, when.date().isoformat())
    day["lol_minutes"] += round(seconds / 60)
    day["lol_games"] += 1
    if player.get("win") is True:
        day["lol_wins"] += 1


def _bind_account(state: dict, source: str, account: str, today: str) -> None:
    """Un autre compte repart d'une nouvelle base.

    Comparer ses cumuls a ceux du precedent inventerait du temps de jeu.
    """
    data = state[source]
    if data.get("account") not in (None, account):
        data.clear()
    data["account"] = account
    data.setdefault("tracked_from", today)


def poll(settings: GamingConfig, state: dict, now: datetime, fetch: Fetch = fetch_json) -> None:
    """Un releve complet. Une source en panne n'empeche pas l'autre."""
    errors: dict = {}
    pollers = []
    if settings.steam_enabled:
        pollers.append((STEAM, settings.steam_id, poll_steam))
    if settings.lol_enabled:
        riot_id = f"{settings.riot_region}/{settings.riot_game_name}#{settings.riot_tag_line}"
        pollers.append((LOL, riot_id.casefold(), poll_lol))
    today = now.date().isoformat()
    for source, account, poller in pollers:
        _bind_account(state, source, account, today)
        try:
            poller(settings, state, now, fetch)
        except GamingError as error:
            errors[source] = error.code
            log.warning("Releve %s en echec : %s", source, error.code)
        except Exception as error:  # noqa: BLE001
            # Une reponse d'une forme imprevue. Seul le type est journalise.
            errors[source] = "unexpected"
            log.error("Releve %s interrompu : %s", source, type(error).__name__)
    state["errors"] = errors
    state["updated_at"] = int(now.timestamp())
    oldest = (now.date() - timedelta(days=_DAYS_KEPT)).isoformat()
    state["days"] = {key: day for key, day in state["days"].items() if key >= oldest}
    for source in (STEAM, LOL):
        if "broken" in state[source]:
            state[source]["broken"] = [key for key in state[source]["broken"] if key >= oldest]


def _sources(settings: GamingConfig) -> list:
    return [
        source
        for source, enabled in ((STEAM, settings.steam_enabled), (LOL, settings.lol_enabled))
        if enabled
    ]


def _is_final(settings: GamingConfig, state: dict, source: str, monday: date) -> bool:
    """La source a-t-elle tout vu de cette semaine, jusqu'au lundi suivant ?"""
    data = state[source]
    since = data.get("since")
    next_monday = monday + timedelta(days=7)
    broken = data.get("broken") or []
    if since is None or since >= monday.isoformat():
        return False
    if monday.isoformat() in broken or next_monday.isoformat() in broken:
        return False
    zone = ZoneInfo(settings.timezone)
    if source == STEAM:
        polled = data.get("polled_at")
        return polled is not None and datetime.fromtimestamp(polled, zone).date() >= next_monday
    synced = data.get("synced_at")
    settled = datetime.combine(next_monday, day_time(_LOL_SETTLE_HOURS), zone).timestamp()
    return synced is not None and synced >= settled


def _is_measured(state: dict, source: str, monday: date) -> bool:
    """La source a-t-elle suivi la semaine jusqu'a son dimanche ?"""
    data = state[source]
    since = data.get("since")
    if since is None or since >= monday.isoformat():
        return False
    if monday.isoformat() in (data.get("broken") or []):
        return False
    sunday = (monday + timedelta(days=6)).isoformat()
    return source in (state["days"].get(sunday) or {}).get("measured", [])


def week_summary(settings: GamingConfig, state: dict, monday: date) -> dict:
    """Le temps de jeu d'une semaine, et ce qu'on peut en dire.

    `measured` : le total est bon a la date de son dernier releve du dimanche,
    ce qui suffit a la notification. `complete` : il ne bougera plus, et peut
    fixer le contrat suivant. Une source ajoutee apres cette semaine ne la
    concerne pas.
    """
    keys = [(monday + timedelta(days=offset)).isoformat() for offset in range(7)]
    steam: dict = {}
    lol_minutes = lol_games = lol_wins = 0
    for key in keys:
        day = state["days"].get(key)
        if day is None:
            continue
        for app, minutes in day["steam"].items():
            steam[app] = steam.get(app, 0) + minutes
        lol_minutes += day["lol_minutes"]
        lol_games += day["lol_games"]
        lol_wins += day["lol_wins"]

    followed = []
    for source in _sources(settings):
        begun = state[source].get("tracked_from") or state[source].get("since")
        if begun is not None and begun <= keys[-1]:
            followed.append(source)

    names = state[STEAM].get("names") or {}
    games = sorted(
        ({"name": names.get(app, app), "minutes": minutes} for app, minutes in steam.items()),
        key=lambda game: -game["minutes"],
    )
    steam_minutes = sum(steam.values())
    return {
        "monday": keys[0],
        "minutes": steam_minutes + lol_minutes,
        "complete": bool(followed) and all(_is_final(settings, state, s, monday) for s in followed),
        "measured": bool(followed) and all(_is_measured(state, s, monday) for s in followed),
        "steam_minutes": steam_minutes,
        "lol_minutes": lol_minutes,
        "lol_games": lol_games,
        "lol_wins": lol_wins,
        "games": games,
    }


def report(settings: GamingConfig, agent_token: str, today: Optional[date] = None) -> dict:
    # Sans verrou : save_state remplace le fichier d'un coup, et un releve peut
    # durer plusieurs minutes.
    state = load_state(Path(settings.state_path))
    day = today or datetime.now(ZoneInfo(settings.timezone)).date()
    monday = _monday(day)
    return {
        "sources": _sources(settings),
        "updated_at": state.get("updated_at"),
        "errors": {**(state.get("errors") or {}), **_runtime_errors},
        "notify_token": notify_token(agent_token),
        "weeks": [
            week_summary(settings, state, monday - timedelta(days=7 * back))
            for back in range(_WEEKS_REPORTED)
        ],
    }


def week(settings: GamingConfig, monday: date) -> dict:
    summary = week_summary(settings, load_state(Path(settings.state_path)), monday)
    return {"minutes": summary["minutes"], "measured": summary["measured"]}


def poll_once(settings: GamingConfig, path: Path, fetch: Fetch = fetch_json) -> None:
    try:
        state = load_state(path)
    except GamingStateError as error:
        # Une panne de lecture se retentera. Un fichier abime ne se reparera
        # pas : il est mis de cote plutot qu'ecrase.
        if not error.corrupt:
            raise
        _set_aside(path)
        log.error("Etat du temps de jeu illisible, mis de cote")
        state = empty_state()
    poll(settings, state, datetime.now(ZoneInfo(settings.timezone)), fetch)
    save_state(path, state)


def _run(settings: GamingConfig) -> None:
    path = Path(settings.state_path)
    while True:
        try:
            poll_once(settings, path)
            _runtime_errors.pop("storage", None)
        except Exception as error:  # noqa: BLE001
            # Le releve est un plus : il ne doit jamais faire tomber l'agent.
            # Seul le type est journalise, le message pourrait citer une cle.
            _runtime_errors["storage"] = "unavailable"
            log.error("Releve du temps de jeu interrompu : %s", type(error).__name__)
        time.sleep(settings.poll_minutes * 60)


def start(settings: GamingConfig) -> None:
    if settings.enabled:
        threading.Thread(target=_run, args=(settings,), name="gaming", daemon=True).start()
