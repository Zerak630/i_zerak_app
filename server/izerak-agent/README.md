# Agent de supervision iZerak

Petit service HTTP a installer sur le Raspberry Pi. Il expose l'etat materiel de
la machine, l'etat du disque externe de la bibliotheque Emby, et le pilotage
d'un ensemble ferme de services systemd. L'application mobile ne parle qu'a lui :
elle n'ouvre jamais de session SSH et ne touche jamais a systemd directement.

## Installation

```bash
sudo ./install.sh
```

Le script cree un compte systeme sans shell, installe le code dans
`/opt/izerak-agent`, depose la regle sudo, active l'unite systemd et **genere un
jeton qu'il affiche une seule fois**. Reportez-le dans les reglages de
l'application, section « Agent Raspberry Pi ».

Le script est idempotent : le relancer met le code a jour sans regenerer le
jeton ni ecraser `/etc/izerak-agent/config.yaml`.

## Certificat

L'agent presente le **meme certificat que la WebUI qBittorrent**, sur un port
different. L'application n'a ainsi qu'une seule empreinte a epingler pour les
deux services.

```bash
# Remplacez le nom d'hote et l'adresse par ceux de votre serveur.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /etc/izerak-agent/qbt.key -out /etc/izerak-agent/qbt.crt \
  -subj "/CN=nas.lan" \
  -addext "subjectAltName=DNS:nas.lan,IP:192.168.1.10"

# Empreinte a comparer dans l'application, une seule fois :
openssl x509 -in /etc/izerak-agent/qbt.crt -noout -fingerprint -sha256
```

L'extension `subjectAltName` est **obligatoire** : les clients modernes ignorent
le champ CN. Si vous joignez la machine par son adresse IP, cette adresse doit
figurer dans le SAN.

## Configuration

`/etc/izerak-agent/config.yaml`, en `chmod 640` puisqu'il porte le jeton. Voir
`config.example.yaml` pour le detail des champs.

Deux points meritent attention :

- **`services`** est une liste blanche stricte. Un nom absent de cette liste
  n'est jamais transmis a `systemctl` : la requete ressort en 404 sans qu'aucun
  processus ne soit lance. Ajouter un service impose d'ajouter aussi les trois
  lignes correspondantes dans `izerak-agent.sudoers`.
- **`quota_bytes`** est un plafond que vous vous imposez, distinct de la
  capacite reelle du disque. C'est lui que l'application affiche, et c'est son
  depassement qui bloque l'ajout de nouveaux telechargements.

## API

Toutes les routes exigent l'en-tete `Authorization: Bearer <jeton>`.

| Methode | Route | Reponse |
|---|---|---|
| GET | `/api/v1/health` | version de l'agent, horodatage |
| GET | `/api/v1/system` | uptime, charge, temperature, memoire, bridage |
| GET | `/api/v1/storage` | etat des volumes surveilles |
| GET | `/api/v1/services` | etat des services autorises |
| POST | `/api/v1/services/{nom}/{start\|stop\|restart}` | etat apres action |

```bash
curl -sk -H "Authorization: Bearer $TOKEN" https://localhost:8081/api/v1/storage | jq
```

### Etat du disque

`mounted` vaut `false` avec un `reason` explicite dans trois situations
distinctes :

| `reason` | Signification |
|---|---|
| `missing` | le chemin n'existe pas |
| `not_mounted` | le chemin existe mais rien n'y est monte — **le cas du disque debranche** |
| `same_device_as_root` | le chemin pointe vers le systeme de fichiers racine |

Cette distinction est le cœur du module. Quand un disque USB est debranche, son
point de montage subsiste sous la forme d'un repertoire vide sur la carte SD :
un simple test d'existence repondrait « present », et qBittorrent ecrirait sur
la carte SD jusqu'a la saturer.

Un volume monte peut par ailleurs etre `readonly` : c'est ainsi que le noyau
remonte un disque USB defaillant. Le disque est bien present, mais plus
inscriptible.

## Securite

- Jeton porteur compare en temps constant (`hmac.compare_digest`).
- Liste blanche d'unites ; le nom recu ne sert que de cle de recherche.
- Aucun shell : `subprocess.run` recoit une liste d'arguments, ce qui rend toute
  injection sans effet.
- L'action est validee par un enum : seuls `start`, `stop` et `restart` existent.
- **Aucun endpoint d'extinction ou de redemarrage de la machine.** Son absence
  limite ce qu'une compromission de l'appareil mobile permettrait de faire.
- Elevation limitee a neuf commandes exactes dans `/etc/sudoers.d/izerak-agent`.
- Limitation a dix actions par minute, pour qu'un bug de boucle cote application
  ne mette pas les services en cycle demarrage/arret.
- Unite systemd durcie. `NoNewPrivileges` est volontairement absent : il
  empecherait l'elevation par sudo dont l'agent a besoin.

N'exposez jamais ce port depuis Internet.

## Tests

```bash
python -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/python -m pytest
```

Les tests ne touchent pas au systeme reel : les points de montage sont simules
dans un repertoire temporaire et les appels a `systemctl` sont interceptes.

## Depannage

```bash
systemctl status izerak-agent
journalctl -u izerak-agent -f
```

| Symptome | Piste |
|---|---|
| L'agent ne demarre pas | jeton de moins de 32 caracteres dans `config.yaml` |
| 401 depuis l'application | jeton recopie partiellement |
| 502 sur une action | regle sudoers absente pour ce couple action/unite |
| Certificat refuse | empreinte epinglee obsolete apres regeneration du certificat ; a reapprouver dans les reglages |
