"""Agent HTTP de supervision du Raspberry Pi.

Expose l'etat materiel, l'etat du disque externe de la bibliotheque, et le
pilotage d'un ensemble ferme de services systemd.

Deliberement absent : tout endpoint d'extinction ou de redemarrage de la
machine. Il n'a pas ete demande, et son absence reduit d'autant ce qu'une
compromission de l'appareil mobile permettrait de faire.
"""

from __future__ import annotations

import hmac
import time
from collections import deque
from datetime import date, timedelta
from typing import Annotated, Optional

from fastapi import Depends, FastAPI, Header, HTTPException

from izerak_agent import gaming, metrics, storage
from izerak_agent.config import AgentConfig, ServiceEntry, load
from izerak_agent.systemd import ServiceAction, apply, status

VERSION = "1.0.0"

# Limitation de debit des actions : une boucle cote application ne doit pas
# pouvoir mettre les services en cycle demarrage/arret.
_ACTION_WINDOW_SECONDS = 60
_ACTION_MAX_PER_WINDOW = 10
_recent_actions: deque[float] = deque()

app = FastAPI(title="iZerak agent", version=VERSION, docs_url=None, redoc_url=None)

# Ce fichier evite volontairement la syntaxe « X | None » (PEP 604) au profit de
# « Optional[X] ».
#
# Ailleurs dans le paquet, « from __future__ import annotations » rend les
# annotations paresseuses : elles restent des chaines et ne sont jamais
# evaluees. FastAPI, lui, les resout a l'execution pour construire ses
# dependances et ses modeles. Sur Python 3.9 — la version de Raspberry Pi OS
# Bullseye — cette evaluation echoue :
#
#   TypeError: Unable to evaluate type annotation 'Annotated[str | None, ...]'
#
# Toute nouvelle signature exposee a FastAPI doit donc s'en tenir a Optional et
# Union.
_config: Optional[AgentConfig] = None


def config() -> AgentConfig:
    global _config
    if _config is None:
        _config = load()
    return _config


def require_token(
    authorization: Annotated[Optional[str], Header()] = None,
    settings: AgentConfig = Depends(config),
) -> None:
    """Verifie le jeton porteur.

    La comparaison passe par ``hmac.compare_digest`` : une comparaison de
    chaines ordinaire s'interrompt au premier octet different et divulgue, par
    son temps d'execution, la longueur du prefixe correct.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Jeton absent")
    presented = authorization.removeprefix("Bearer ").strip()
    if not hmac.compare_digest(presented, settings.token):
        raise HTTPException(status_code=401, detail="Jeton invalide")


Authenticated = Annotated[None, Depends(require_token)]


@app.get("/api/v1/health")
def health(_: Authenticated) -> dict:
    return {"version": VERSION, "timestamp": int(time.time())}


@app.get("/api/v1/system")
def system(_: Authenticated) -> dict:
    return metrics.collect().to_dict()


@app.get("/api/v1/storage")
def storage_status(_: Authenticated, settings: AgentConfig = Depends(config)) -> dict:
    volumes = [
        storage.probe(entry.path, entry.label, entry.quota_bytes).to_dict()
        for entry in settings.storage
    ]
    return {"volumes": volumes}


@app.get("/api/v1/services")
def services(_: Authenticated, settings: AgentConfig = Depends(config)) -> dict:
    return {"services": [_describe(entry) for entry in settings.services]}


@app.get("/api/v1/gaming")
def gaming_report(_: Authenticated, settings: AgentConfig = Depends(config)) -> dict:
    try:
        return gaming.report(settings.gaming, settings.token)
    except gaming.GamingStateError as error:
        # Pas de rapport vide : l'application garderait « 0 h » pour vrai.
        raise HTTPException(status_code=503, detail="Releves illisibles") from error


@app.get("/api/v1/gaming/week")
def gaming_week(
    monday: str,
    authorization: Annotated[Optional[str], Header()] = None,
    settings: AgentConfig = Depends(config),
) -> dict:
    """Le total d'une semaine, pour la notification du dimanche.

    Seule route ouverte au jeton derive : il ne doit rien permettre d'autre.
    """
    presented = (authorization or "").removeprefix("Bearer ").strip()
    # En octets : compare_digest leve sur une chaine non ASCII.
    if not hmac.compare_digest(presented.encode(), gaming.notify_token(settings.token).encode()):
        raise HTTPException(status_code=401, detail="Jeton invalide")
    try:
        day = date.fromisoformat(monday)
    except ValueError as error:
        raise HTTPException(status_code=422, detail="Date invalide") from error
    # La semaine et son lundi suivant doivent rester dans le calendrier.
    if day.weekday() != 0 or day > date.max - timedelta(days=14):
        raise HTTPException(status_code=422, detail="Un lundi est attendu")
    try:
        return gaming.week(settings.gaming, day)
    except gaming.GamingStateError as error:
        raise HTTPException(status_code=503, detail="Releves illisibles") from error


def _describe(entry: ServiceEntry) -> dict:
    return {
        **status(entry.name, entry.unit).to_dict(),
        "web": entry.web(),
        "actions": list(entry.actions),
    }


@app.post("/api/v1/services/{name}/{action}")
def service_action(
    name: str,
    action: ServiceAction,
    _: Authenticated,
    settings: AgentConfig = Depends(config),
) -> dict:
    # Le nom recu ne sert que de cle de recherche : il n'atteint jamais
    # systemctl s'il ne figure pas dans la liste blanche.
    entry = settings.entry_for(name)
    if entry is None:
        raise HTTPException(status_code=404, detail="Service inconnu")
    if action.value not in entry.actions:
        raise HTTPException(status_code=403, detail="Action non permise pour ce service")

    _enforce_rate_limit()

    try:
        apply(entry.unit, action)
    except RuntimeError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    return _describe(entry)


def _enforce_rate_limit() -> None:
    now = time.monotonic()
    while _recent_actions and now - _recent_actions[0] > _ACTION_WINDOW_SECONDS:
        _recent_actions.popleft()
    if len(_recent_actions) >= _ACTION_MAX_PER_WINDOW:
        raise HTTPException(status_code=429, detail="Trop d'actions, patientez")
    _recent_actions.append(now)


def main() -> None:
    import uvicorn

    settings = config()
    gaming.start(settings.gaming)
    uvicorn.run(
        app,
        host=settings.bind_host,
        port=settings.bind_port,
        ssl_certfile=settings.tls_certificate,
        ssl_keyfile=settings.tls_private_key,
        log_level="info",
    )


if __name__ == "__main__":
    main()
