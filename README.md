# iZerak

Application Flutter personnelle qui pilote un serveur auto-hébergé depuis le téléphone :
téléchargements qBittorrent, supervision d'un Raspberry Pi, suivi d'abonnements et prix des
carburants. Deux onglets aident aussi au quotidien : une cagnotte pour les trajets à vélo, et le
**Temps libre** pour décrocher des réseaux sociaux.

## Architecture

Il n'y a **aucun back-end intermédiaire**. L'application parle directement à chaque service :

```
                        ┌──────────────────────────── Raspberry Pi ────────┐
                        │                                                  │
  ┌─────────┐  HTTPS    │  ┌──────────────┐   :8080                        │
  │         │───────────┼─▶│  qBittorrent │  WebUI, session SID            │
  │ iZerak  │  cert.    │  └──────────────┘                                │
  │ Android │  épinglé  │  ┌──────────────┐   :8081                        │
  │         │───────────┼─▶│ izerak-agent │  /proc, systemctl, disque      │
  └────┬────┘  + jeton  │  └──────────────┘                                │
       │                └──────────────────────────────────────────────────┘
       │  HTTPS publics
       ├───────────────▶ TMDB               recherche de titres, identifiant IMDb
       └───────────────▶ data.economie.gouv.fr   prix des carburants
```

Une couche intermédiaire n'apporterait rien : il n'y a ni utilisateurs multiples, ni logique métier
à centraliser, ni données à partager entre appareils. L'agent Python occupe déjà le rôle serveur, et
il tient dans une trentaine de mégaoctets de mémoire là où une JVM en demanderait dix fois plus pour
lire `/proc` et appeler `systemctl`.

Les abonnements vivent uniquement dans Hive, sur l'appareil.

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
flutter test      # 441 tests
```

Les versions release se construisent **sans élagage des icônes** :

```bash
flutter build apk --release --no-tree-shake-icons
flutter build windows --release --no-tree-shake-icons
```

Avec Flutter 3.47, l'élagage retire de la police Material des glyphes pourtant utilisés
(`phone_android`, `hourglass_bottom`, `settings_outlined`…) : ils s'affichent comme une case vide.
La police complète ajoute environ 1,5 Mo.

## Temps libre (Android)

L'onglet **Temps libre** aide à décrocher des réseaux sociaux. Il lit les statistiques d'utilisation
d'Android (autorisation « Accès aux données d'utilisation », accordée à la main dans les réglages du
téléphone), mesure une moyenne de départ sur les jours que le téléphone a gardés, puis fixe un quota
qui baisse chaque semaine (−10 % par défaut, plancher de 20 min).

Chaque journée terminée sous le quota alimente une cagnotte (2 € par heure gagnée sur la moyenne de
départ, par défaut) qui finance les mêmes objectifs que la cagnotte vélo. Une journée au-dessus du
quota ne rapporte rien : ce que le quota aurait rapporté part dans la case « Économies loupées ». Une notification dresse le bilan chaque
soir (21 h 30 par défaut).

Tout reste sur l'appareil : les journées sont figées dans Hive à minuit, et rien n'est envoyé nulle
part. Le bilan du soir est calculé côté natif, application fermée (`DailyReport.kt`), avec la même
formule que `ScreenTimeSettings` (`quotaFor`, `earnedOn`, `missedOn`) : toute modification du calcul doit être faite des deux côtés.

## Widgets de l'écran d'accueil (Android)

- **Vélo / Voiture ?** : « À vélo » enregistre la journée sans ouvrir l'application ; « Voiture »
  l'ouvre sur la question de la raison. Une fois la journée saisie, le widget affiche le montant et
  la case où il est parti : cagnotte vélo, coûts indispensables ou économies loupées.
- **Temps libre** : le temps passé aujourd'hui sur les réseaux, face au quota, avec le gain ou
  l'économie loupée du jour et la série. Il se mesure seul, côté natif (`ScreenTimeToday`), toutes
  les 30 minutes, à chaque appui et chaque fois qu'iZerak passe en arrière-plan.
- **Objectif** : un objectif actif des cagnottes Vélo et Temps libre. Un appui passe au suivant,
  l'icône en haut à droite ouvre l'application.

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
