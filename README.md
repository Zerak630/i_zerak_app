# iZerak

Application Flutter personnelle qui pilote un serveur auto-hébergé depuis le téléphone :
téléchargements qBittorrent, supervision d'un Raspberry Pi, suivi d'abonnements et prix des
carburants. Trois onglets aident aussi au quotidien : le **Vélo**, dont l'essence économisée
rembourse les abonnements et rentabilise les gros achats, le **Temps libre** pour décrocher des
réseaux sociaux, et le **Sport** à la maison.

## Architecture

Il n'y a **aucun back-end intermédiaire**. L'application parle directement à chaque service :

```
                        ┌──────────────────────────── Raspberry Pi ────────┐
                        │                                                  │
  ┌─────────┐  HTTPS    │  ┌──────────────┐   :8080                        │
  │         │───────────┼─▶│  qBittorrent │  WebUI, session SID            │
  │ iZerak  │  cert.    │  └──────────────┘                                │
  │ Android │  épinglé  │  ┌──────────────┐   :8081                        │
  │         │───────────┼─▶│ izerak-agent │  /proc, systemctl, disque,     │
  └────┬────┘  + jeton  │  └──────┬───────┘  temps de jeu                  │
       │                └─────────┼────────────────────────────────────────┘
       │                          │  HTTPS, toutes les heures
       │                          ├──────▶ API Steam   cumul par jeu
       │                          └──────▶ API Riot    parties de LoL
       │  HTTPS publics
       ├───────────────▶ TMDB               recherche de titres, identifiant IMDb
       ├───────────────▶ data.economie.gouv.fr   prix des carburants
       └───────────────▶ CDN Steam, Data Dragon  icônes des jeux, portraits des champions
```

Une couche intermédiaire n'apporterait rien : il n'y a ni utilisateurs multiples, ni logique métier
à centraliser, ni données à partager entre appareils. L'agent Python occupe déjà le rôle serveur, et
il tient dans une trentaine de mégaoctets de mémoire là où une JVM en demanderait dix fois plus pour
lire `/proc` et appeler `systemctl`.

Les abonnements vivent uniquement dans Hive, sur l'appareil. Le temps de jeu fait exception : c'est
l'agent qui interroge Steam et Riot, parce qu'il faut une machine toujours allumée pour relever, et
parce que les clés d'API n'ont ainsi jamais à quitter le Pi.

## Mise en route

```bash
flutter pub get
flutter gen-l10n
flutter run
```

`flutter gen-l10n` est nécessaire après toute modification de `lib/l10n/*.arb` : les fichiers
`app_localizations*.dart` en sont générés. Le fichier de référence est l'anglais ; toute clé ajoutée
doit l'être dans les deux langues.

```bash
flutter analyze   # doit rester sans avertissement
flutter test      # 546 tests
```

Les versions release se construisent **sans élagage des icônes** :

```bash
flutter build apk --release --no-tree-shake-icons
flutter build windows --release --no-tree-shake-icons
```

Avec Flutter 3.47, l'élagage retire de la police Material des glyphes pourtant utilisés
(`phone_android`, `hourglass_bottom`, `settings_outlined`…) : ils s'affichent comme une case vide.
La police complète ajoute environ 1,5 Mo.

## Objectifs : ce que le vélo rembourse

Il n'y a plus de cagnotte où l'on puise pour acheter. L'onglet **Objectifs** confronte l'essence
réellement économisée à vélo à ce qu'on paie déjà :

- **les abonnements du mois**, remboursés du moins cher au plus cher, au coût mensuel (un annuel de
  120 € compte pour 10 € par mois). On peut en exclure (le loyer, une assurance) ; l'historique
  montre les mois précédents ;
- **les paliers**, les gros achats que les économies rentabilisent sur la durée : le vélo, un
  téléphone… Un palier compte depuis le premier trajet, ou depuis sa date d'achat.

C'est le même argent vu sous deux angles : valider un palier ne retire rien. Le calcul est dans
`lib/models/payback_dao.dart` et `GoalBook` (`lib/models/commute_dao.dart`).

## Temps libre (Android)

L'onglet **Temps libre** aide à décrocher des réseaux sociaux. Il lit les statistiques d'utilisation
d'Android (autorisation « Accès aux données d'utilisation », accordée à la main dans les réglages du
téléphone), mesure une moyenne de départ sur les jours que le téléphone a gardés, puis fixe un quota
qui baisse chaque semaine (−10 % par défaut, plancher de 20 min).

Il compte **du temps, pas de l'argent** : les minutes reprises sur la moyenne de départ, et le temps
passé au-dessus du quota. Une notification dresse le bilan chaque soir (21 h 30 par défaut).

Tout reste sur l'appareil : les journées sont figées dans Hive à minuit, et rien n'est envoyé nulle
part. Le bilan du soir est calculé côté natif, application fermée (`DailyReport.kt`), avec la même
formule que `ScreenTimeSettings.quotaFor` et `ScreenTimeDay.regainedMinutes` : toute modification
du calcul doit être faite des deux côtés.

## Sport

L'onglet **Sport** compte du temps, jamais d'argent. On y décrit ses sports (cinq livrés, d'autres
s'ajoutent ; chacun se renomme, change d'icône, et se supprime tant qu'aucune séance ni aucun
créneau ne l'utilise), un **programme de la semaine** (yoga le lundi, renforcement le jeudi…), et on saisit à
la main chaque séance : un créneau du programme se dit « fait », avec sa durée — le jour prévu ou
décalé à un autre jour de la semaine, qui reçoit alors le temps —, ou « pas fait » ; une
séance en plus s'ajoute en trois choix. Les semaines passées se remplissent après coup, et les
créneaux oubliés de la semaine précédente sont rappelés.

L'onglet montre la semaine jour par jour, les semaines tenues d'affilée (tout le programme, ou au
moins une séance sans programme) et le temps passé sur chaque sport. Les données vivent dans la
boîte Hive `sport`, une entrée par séance, synchronisée comme les trajets.

## Temps de jeu : le contrat de sport

L'agent du Pi relève le temps passé sur **Steam** et sur **League of Legends** (configuration :
voir [le README de l'agent](server/izerak-agent/README.md#temps-de-jeu-steam-et-league-of-legends)).
L'application lit ses relevés (`GET /api/v1/gaming`, dix semaines) et en garde une copie locale :
le Pi n'est pas toujours joignable, depuis l'extérieur notamment.

Le jeu d'une semaine fixe le **sport de la suivante**, dans une carte de l'onglet **Objectifs** :
par défaut, 1 h de sport pour 3 h de jeu, arrondi aux 5 minutes supérieures et plafonné à 6 h. Une
journée à vélo compte 1 h. La cible ne bouge plus une fois la semaine commencée, et les règles
modifiées ne valent qu'à partir de la semaine suivante : un contrat garde celles de sa semaine.

Une panne ne se lit **jamais comme 0 h de jeu**. Une semaine n'est définitive (`complete`), et ne
fixe donc un contrat, qu'une fois le lundi suivant franchi sans trou dans les relevés ; sinon la
carte le dit au lieu d'afficher une cible fausse.

Le calcul est dans `lib/models/game_dao.dart` (`GameContractLedger`), et repris côté natif par
`RecapReport.kt` pour la notification du dimanche : toute modification de `targetFor` doit être
faite des deux côtés. Application fermée, le natif n'a pas accès au stockage sécurisé : il joint
l'agent avec un **jeton dérivé** (`notify_token`), qui n'ouvre que la route `/api/v1/gaming/week`
et ne donne aucun pouvoir sur les services.

### L'écran Temps de jeu

Il s'ouvre depuis la carte du contrat (icône de statistiques) et depuis la carte Jeu du bilan
(`lib/pages/gaming/game_stats_page.dart`). Trois onglets, sur la semaine choisie (chevrons, ou un
appui sur une barre) :

- **Tout** : le total, l'écart avec la semaine d'avant, la part Steam/LoL, dix semaines en barres
  (la semaine en cours en contour : provisoire) et, ouvert depuis Objectifs, le contrat de la
  semaine ;
- **Steam** : chaque jeu avec son icône et sa part, le temps jour par jour (un tiret pour un jour
  sans relevé, jamais 0) et le cumul de chaque jeu depuis toujours ;
- **LoL** : parties, victoires, temps et durée moyenne ; la liste des parties avec le portrait du
  champion, la file (classé, ARAM…) qui sert aussi de filtre, et le KDA ; le rang en classé solo
  et les LP de la semaine.

Les icônes et portraits sont chargés par le téléphone directement sur les CDN publics de Steam et
de Data Dragon. L'application n'accepte une image que de ces deux hôtes, en HTTPS ; sinon, ou en
attendant le chargement, elle affiche l'initiale. Les parties relevées avant que l'agent garde le
détail sont comptées, mais sans ligne : l'écran le dit.

## Bilan de la semaine et du mois

Le **bilan** met côte à côte, sans les additionner, l'essence économisée à vélo (et, au mois, les
abonnements remboursés), le temps repris aux réseaux, le temps de sport et le temps de jeu, avec la période
précédente pour comparer. Il s'ouvre depuis l'accueil (carte « Bilan de la semaine ») et depuis
l'onglet Sport.

Une notification le résume chaque dimanche soir et le dernier jour du mois (19 h 30 par défaut,
réglable dans le bilan). Comme les widgets, le natif ne lit pas Hive : `RecapService` lui transmet
les textes déjà rédigés chaque fois que l'application passe en arrière-plan, et `RecapReport.kt`
notifie celui dont la période se termine ce jour-là. Le bilan reprend donc ce qui a été saisi
jusqu'à la dernière ouverture d'iZerak.

## Widgets de l'écran d'accueil (Android)

- **Vélo / Voiture ?** : « À vélo » enregistre la journée sans ouvrir l'application ; « Voiture »
  l'ouvre sur la question « Est-ce que tu aurais pu prendre le vélo à la place ? ». Une fois la
  journée saisie, le widget affiche le montant et la case où il est parti : essence économisée,
  dépenses obligatoires ou économies loupées — ou simplement « En télétravail ».
- **Temps libre** : le temps passé aujourd'hui sur les réseaux, face au quota, avec le temps
  repris ou le temps de trop du jour, et la série. Il se mesure seul, côté natif (`ScreenTimeToday`), toutes
  les 30 minutes, à chaque appui et chaque fois qu'iZerak passe en arrière-plan.
- **Objectif** : les abonnements du mois que le vélo rembourse, puis les paliers en cours. Un appui
  passe au suivant, l'icône en haut à droite ouvre l'application.

Les widgets ne lisent pas Hive. L'application leur transmet un instantané chaque fois qu'elle passe
en arrière-plan (`HomeWidgetsService`) ; en retour, un appui sur « À vélo » ne fait que noter la
date, et l'application enregistre la journée à son lancement suivant, au prix du carburant de ce
jour-là. Le montant affiché par le widget entre-temps est une estimation (« ≈ »).

## Côté serveur

L'agent de supervision s'installe séparément : voir **[server/izerak-agent/README.md](server/izerak-agent/README.md)**.

### Certificat

qBittorrent et l'agent partagent **le même certificat auto-signé** sur deux ports, de sorte que
l'application n'ait qu'une seule empreinte à approuver.

```bash
# Remplacez le nom d'hôte et l'adresse par ceux de votre serveur.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout qbt.key -out qbt.crt \
  -subj "/CN=nas.lan" \
  -addext "subjectAltName=DNS:nas.lan,IP:192.168.1.10"
```

L'extension `subjectAltName` est **obligatoire** : les clients modernes ignorent le champ CN. Si vous
joignez la machine par son adresse IP, cette adresse doit y figurer.

### Première connexion

C'est le seul geste manuel de l'installation, et il remplace une autorité de certification.

1. Sur le serveur, relevez l'empreinte :
   ```bash
   openssl x509 -in qbt.crt -noout -fingerprint -sha256
   ```
2. Dans l'application : **Réglages → Tester la connexion**.
3. L'application refuse le certificat inconnu et affiche son empreinte. **Comparez-la à celle
   ci-dessus**, puis approuvez.

L'empreinte est alors épinglée. Toute connexion ultérieure présentant un certificat différent sera
refusée avec un message explicite — ce qui se produira légitimement le jour où vous régénérerez le
certificat : il faudra alors le réapprouver.

Le contexte TLS est créé **sans racines de confiance**, de sorte que la vérification par empreinte
s'applique systématiquement, y compris si le serveur présentait un jour un certificat signé par une
autorité reconnue.

## Secrets

Trois secrets sont attendus dans les Réglages. Aucun n'est versionné : tous vivent dans le Keystore
Android via `flutter_secure_storage`.

| Secret | Origine |
|---|---|
| Mot de passe qBittorrent | votre WebUI |
| Jeton de l'agent | affiché une seule fois par `install.sh` sur le Pi |
| Jeton TMDB | clé personnelle gratuite sur themoviedb.org |

Le jeton TMDB est facultatif : sans lui, le nom du dossier de destination se saisit à la main.

Les clés Steam et Riot ne sont **pas** dans l'application : elles vivent dans
`/etc/izerak-agent/config.yaml` sur le Pi, et l'agent ne transmet que des durées.

L'API IMDb officielle n'est pas utilisée — elle n'a aucun accès public et n'est distribuée qu'aux
entreprises via AWS Data Exchange. TMDB fournit l'identifiant IMDb via `/external_ids`, ce qui suffit
à nommer les dossiers. Sa licence impose l'attribution affichée dans les Réglages.

## Nommage pour Emby

À l'ajout d'un magnet, le dossier de destination prend la forme reconnue par Emby et Jellyfin :

```
Titre du film (2024) [imdbid-tt1234567]
```

C'est ce qui force la correspondance sur les titres ambigus, les remakes et les traductions.

## Points d'attention pour la maintenance

- **Les `TypeAdapter` Hive sont écrits à la main** dans
  `lib/services/repositories/hive/type_adapters.dart`, `hive_generator` étant incompatible avec le
  SDK courant. Tout champ ajouté à un modèle doit y être répercuté, en respectant les règles Hive :
  ne jamais renuméroter ni réutiliser un `HiveField`.
- **Le rafraîchissement s'arrête sur erreur d'authentification.** C'est délibéré : qBittorrent
  bannit l'adresse au bout de cinq échecs, et un rafraîchissement toutes les trois secondes y
  parviendrait en une demi-minute.
- **Android bloque le HTTP en clair.** `network_security_config.xml` l'interdit pour toute
  l'application ; désactiver HTTPS dans les Réglages rendra l'application inopérante en build
  release.
- **`android:allowBackup="false"` est requis** par `flutter_secure_storage` : une restauration
  rapporterait les données chiffrées sans la clé du Keystore, qui n'est pas sauvegardable.
