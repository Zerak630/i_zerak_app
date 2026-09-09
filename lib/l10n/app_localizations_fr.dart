// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get helloWorld => 'Bonjour le monde!';

  @override
  String get subscription_title => 'Abonnements';

  @override
  String get per_week => 'par semaine';

  @override
  String get per_month => 'par mois';

  @override
  String get per_year => 'par an';

  @override
  String get per_week_adjective => 'Hebdomadaire';

  @override
  String get per_month_adjective => 'Mensuel';

  @override
  String get per_year_adjective => 'Annuel';

  @override
  String get enable => 'Activer';

  @override
  String get disable => 'Désactiver';

  @override
  String get edit => 'Modifier';

  @override
  String get delete => 'Supprimer';

  @override
  String get save => 'Enregistrer';

  @override
  String get add => 'Ajouter';

  @override
  String get cancel => 'Annuler';

  @override
  String get edit_subscription => 'Modifier un abonnement';

  @override
  String get add_subscription => 'Ajouter un nouvel abonnement';

  @override
  String get name => 'Nom';

  @override
  String get price => 'Prix';

  @override
  String get frequency => 'Fréquence';

  @override
  String get name_placeholder => 'Netflix';

  @override
  String get price_placeholder => '9.99';

  @override
  String get please_enter_a_name => 'Veuillez entrer un nom';

  @override
  String get please_enter_a_price => 'Veuillez entrer un prix';

  @override
  String get please_enter_a_valid_price => 'Veuillez entrer un prix valide';

  @override
  String get please_select_a_frequency => 'Veuillez choisir une fréquence';

  @override
  String get bb_gas_stations => 'Stations';

  @override
  String get bb_subscriptions => 'Abonnements';

  @override
  String get gas_title => 'Stations essences';

  @override
  String get gas_add_station => 'Ajouter une station';

  @override
  String get gas_search_field => 'Ville ou code postal';

  @override
  String get gas_search_hint => 'Exemple : Angers, ou 49100';

  @override
  String get gas_no_result => 'Aucune station trouvée';

  @override
  String get gas_no_station => 'Aucune station suivie';

  @override
  String get gas_no_station_hint => 'Ajoutez-en une avec le bouton +';

  @override
  String get gas_already_saved => 'Déjà suivie';

  @override
  String get gas_price_unknown => 'Prix inconnu';

  @override
  String gas_prices_shown(String fuel) {
    return 'Prix affichés : $fuel';
  }

  @override
  String get gas_navigate => 'Y aller';

  @override
  String get gas_maps_unavailable => 'Aucune application d’itinéraire trouvée';

  @override
  String get gas_rename => 'Renommer';

  @override
  String get gas_station_name => 'Nom de la station';

  @override
  String get gas_rename_hint => 'Laisser vide pour revenir à l’adresse';

  @override
  String get fuel_gazole => 'Gazole';

  @override
  String get fuel_sp95 => 'SP95';

  @override
  String get fuel_sp98 => 'SP98';

  @override
  String get fuel_e10 => 'E10';

  @override
  String get fuel_e85 => 'E85';

  @override
  String get fuel_gplc => 'GPLc';

  @override
  String get gas_unreachable => 'Données carburants injoignables';

  @override
  String get no_subscription => 'Aucun abonnement';

  @override
  String loading_error(String error) {
    return 'Erreur : $error';
  }

  @override
  String delete_confirm(String name) {
    return 'Supprimer $name à titre définitif ?';
  }

  @override
  String get active => 'Actif';

  @override
  String get inactive => 'Inactif';

  @override
  String get logo_code => 'Code de l’icône';

  @override
  String get please_enter_a_logo_code => 'Veuillez entrer un code d’icône';

  @override
  String get please_enter_a_valid_integer => 'Veuillez entrer un entier valide';

  @override
  String get settings_title => 'Réglages';

  @override
  String get pi_section => 'Raspberry Pi';

  @override
  String get pi_section_hint =>
      'Adresse et certificat communs à tous les services hébergés sur le Pi.';

  @override
  String get qbittorrent_section => 'qBittorrent';

  @override
  String get qbittorrent_section_hint =>
      'Client de téléchargement, joint sur son interface web.';

  @override
  String get agent_section_hint =>
      'Agent Python installé sur le Pi : état du matériel, du disque et des services.';

  @override
  String get emby_section => 'Emby';

  @override
  String get emby_section_hint =>
      'Racine contenant Films, Series et Autres, où qBittorrent dépose les téléchargements.';

  @override
  String get tmdb_section => 'TMDB';

  @override
  String get tmdb_section_hint =>
      'Facultatif : complète le nom du dossier et son tag tmdbid à partir d’un titre.';

  @override
  String get server_host => 'Adresse du Raspberry Pi';

  @override
  String get server_port => 'Port de l’interface web';

  @override
  String get agent_port => 'Port de l’agent';

  @override
  String get certificate_pinned => 'Certificat approuvé';

  @override
  String get certificate_none =>
      'Aucun certificat approuvé. Il sera présenté au premier test de connexion.';

  @override
  String get certificate_forget => 'Oublier';

  @override
  String get test_agent => 'Tester l’agent';

  @override
  String agent_ok(String version) {
    return 'Agent joignable — version $version';
  }

  @override
  String get settings_saved => 'Réglages enregistrés';

  @override
  String settings_save_failed(String error) {
    return 'Enregistrement impossible : $error';
  }

  @override
  String get use_https => 'Utiliser HTTPS';

  @override
  String get use_https_on_hint =>
      'Le certificat auto-signé est épinglé à la première connexion.';

  @override
  String get use_https_off_hint =>
      'Le trafic et le mot de passe circulent en clair.';

  @override
  String get warning_raw_ip_certificate =>
      'Avec une adresse IP, le certificat doit porter cette adresse dans son extension subjectAltName.';

  @override
  String get warning_cleartext_blocked =>
      'Android bloque le HTTP en clair en build release. Seul HTTPS fonctionnera sur l’appareil.';

  @override
  String get username => 'Identifiant';

  @override
  String get password => 'Mot de passe';

  @override
  String get poll_interval => 'Intervalle de rafraîchissement';

  @override
  String get poll_interval_manual => 'Manuel';

  @override
  String get test_connection => 'Tester la connexion';

  @override
  String get agent_section => 'API iZerak';

  @override
  String get agent_token => 'Jeton de l’agent';

  @override
  String get agent_token_hint => 'Généré par install.sh sur le Pi.';

  @override
  String get default_save_path => 'Racine de la bibliothèque Emby';

  @override
  String get tmdb_token => 'Jeton TMDB';

  @override
  String get tmdb_token_hint =>
      'Clé d’API personnelle gratuite sur themoviedb.org.';

  @override
  String get tmdb_attribution =>
      'Ce produit utilise l’API TMDB mais n’est ni approuvé ni certifié par TMDB.';

  @override
  String get please_enter_a_host => 'Veuillez entrer un hôte';

  @override
  String get please_enter_a_valid_port => 'Le port doit être entre 1 et 65535';

  @override
  String get certificate_title => 'Certificat inconnu';

  @override
  String get certificate_explanation =>
      'Comparez cette empreinte avec celle indiquée par openssl sur le serveur avant de l’approuver.';

  @override
  String get certificate_trust => 'Approuver';

  @override
  String get error_not_configured => 'Serveur non configuré';

  @override
  String get error_invalid_credentials => 'Identifiants invalides';

  @override
  String get error_ip_banned =>
      'Adresse temporairement bannie après trop d’échecs de connexion. Patientez avant de réessayer.';

  @override
  String get error_certificate =>
      'Le certificat du serveur a été refusé. Il a peut-être changé.';

  @override
  String get error_unreachable => 'Serveur injoignable';

  @override
  String get error_timeout => 'Délai dépassé';

  @override
  String connection_ok(String version) {
    return 'Connecté — qBittorrent $version';
  }

  @override
  String get bb_torrents => 'Torrents';

  @override
  String get torrents_title => 'Téléchargements';

  @override
  String get no_torrents => 'Aucun torrent';

  @override
  String get not_configured_message =>
      'Renseignez l’adresse du serveur et vos identifiants pour piloter qBittorrent depuis l’application.';

  @override
  String get configure => 'Configurer';

  @override
  String get retry => 'Réessayer';

  @override
  String get refresh => 'Rafraîchir';

  @override
  String last_updated(String time) {
    return 'Mis à jour à $time';
  }

  @override
  String get add_magnet => 'Ajouter un téléchargement';

  @override
  String get magnet_link => 'Lien magnet';

  @override
  String get please_enter_a_magnet => 'Veuillez entrer un lien magnet';

  @override
  String get please_enter_a_valid_magnet =>
      'Un lien magnet: ou une URL .torrent est attendu';

  @override
  String get paste => 'Coller';

  @override
  String get pause => 'Mettre en pause';

  @override
  String get resume => 'Reprendre';

  @override
  String get delete_torrent => 'Supprimer le torrent';

  @override
  String get delete_files_too => 'Supprimer aussi les fichiers téléchargés';

  @override
  String torrent_added_in(String destination) {
    return 'Ajouté dans $destination';
  }

  @override
  String get download_speed => 'Vitesse de réception';

  @override
  String get upload_speed => 'Vitesse d’envoi';

  @override
  String get status_connected => 'Connecté';

  @override
  String get status_firewalled => 'Derrière un pare-feu';

  @override
  String get status_disconnected => 'Déconnecté';

  @override
  String get search_title => 'Rechercher le titre';

  @override
  String get search_title_hint =>
      'Nomme le dossier pour qu’Emby identifie le média.';

  @override
  String get destination_hint =>
      'Détermine la catégorie qBittorrent et le dossier de la bibliothèque.';

  @override
  String get destination_movies => 'Films';

  @override
  String get destination_series => 'Séries';

  @override
  String get destination_other => 'Autres';

  @override
  String get emby_folder => 'Dossier de destination';

  @override
  String get emby_folder_hint =>
      'Emby reconnaît la forme Titre (Année) [tmdbid=123456].';

  @override
  String get tmdb_not_configured =>
      'Aucun jeton TMDB : renseignez le nom du dossier à la main.';

  @override
  String get tmdb_auth_error => 'TMDB a refusé le jeton';

  @override
  String get tmdb_unreachable => 'TMDB injoignable';

  @override
  String get state_downloading => 'Téléchargement';

  @override
  String get state_fetching_metadata => 'Récupération des métadonnées';

  @override
  String get state_uploading => 'Partage';

  @override
  String get state_paused => 'En pause';

  @override
  String get state_queued => 'En file d’attente';

  @override
  String get state_stalled => 'En attente de sources';

  @override
  String get state_checking => 'Vérification';

  @override
  String get state_moving => 'Déplacement';

  @override
  String get state_allocating => 'Allocation';

  @override
  String get state_error => 'Erreur';

  @override
  String get state_missing_files => 'Fichiers manquants';

  @override
  String get state_unknown => 'Inconnu';

  @override
  String get bb_system => 'Système';

  @override
  String get system_title => 'Raspberry Pi';

  @override
  String get agent_not_configured_message =>
      'Installez l’agent sur le Pi, puis collez son jeton dans les réglages.';

  @override
  String get uptime => 'Durée de fonctionnement';

  @override
  String get load_average => 'Charge moyenne';

  @override
  String get cpu_temp => 'Température CPU';

  @override
  String get memory => 'Mémoire';

  @override
  String get storage_disconnected =>
      'Disque externe débranché — les téléchargements rempliraient la carte SD.';

  @override
  String get storage_readonly =>
      'Monté en lecture seule : le disque est défaillant.';

  @override
  String get undervoltage_now =>
      'Sous-tension détectée en ce moment. Vérifiez l’alimentation.';

  @override
  String get undervoltage_occurred =>
      'Sous-tension survenue depuis le démarrage. Cela explique bien des pannes inexpliquées.';

  @override
  String get throttling_occurred =>
      'Bridage thermique survenu depuis le démarrage.';

  @override
  String get service_start => 'Démarrer';

  @override
  String get service_stop => 'Arrêter';

  @override
  String get service_restart => 'Redémarrer';

  @override
  String get confirm => 'Confirmer';

  @override
  String get service_active => 'En fonctionnement';

  @override
  String get service_inactive => 'Arrêté';

  @override
  String get service_failed => 'En échec';

  @override
  String get service_activating => 'Démarrage';

  @override
  String get service_deactivating => 'Arrêt';

  @override
  String get error_agent_token => 'L’agent a refusé le jeton';

  @override
  String get error_agent_unreachable => 'Agent injoignable';

  @override
  String get storage_blocked_add =>
      'Disque indisponible ou quota atteint : l’ajout est désactivé.';

  @override
  String storage_missing(String path) {
    return 'Le chemin $path n’existe pas';
  }

  @override
  String storage_quota(String used, String quota) {
    return '$used utilisés sur $quota autorisés';
  }

  @override
  String storage_capacity(String free, String total) {
    return '$free libres sur $total au total';
  }

  @override
  String confirm_service_action(String name) {
    return 'Cette action interrompra $name. Continuer ?';
  }

  @override
  String get storage_permission_denied =>
      'L’agent ne peut pas lire ce volume : vérifiez ses permissions.';
}
