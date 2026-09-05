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
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException

from izerak_agent import metrics, storage
from izerak_agent.config import AgentConfig, load
from izerak_agent.systemd import ServiceAction, apply, status

VERSION = "1.0.0"

# Limitation de debit des actions : une boucle cote application ne doit pas
# pouvoir mettre les services en cycle demarrage/arret.
_ACTION_WINDOW_SECONDS = 60
_ACTION_MAX_PER_WINDOW = 10
_recent_actions: deque[float] = deque()

app = FastAPI(title="iZerak agent", version=VERSION, docs_url=None, redoc_url=None)

_config: AgentConfig | None = None


def config() -> AgentConfig:
    global _config
    if _config is None:
        _config = load()
    return _config


def require_token(
    authorization: Annotated[str | None, Header()] = None,
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
    return {
        "services": [status(entry.name, entry.unit).to_dict() for entry in settings.services]
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
    unit = settings.unit_for(name)
    if unit is None:
        raise HTTPException(status_code=404, detail="Service inconnu")

    _enforce_rate_limit()

    try:
        apply(unit, action)
    except RuntimeError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    return status(name, unit).to_dict()


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
