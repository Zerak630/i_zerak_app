// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get helloWorld => 'Hello World!';

  @override
  String get subscription_title => 'Subscriptions';

  @override
  String get per_week => 'per week';

  @override
  String get per_month => 'per month';

  @override
  String get per_year => 'per year';

  @override
  String get per_week_adjective => 'Weekly';

  @override
  String get per_month_adjective => 'Monthly';

  @override
  String get per_year_adjective => 'Yearly';

  @override
  String get enable => 'Enable';

  @override
  String get disable => 'Disable';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get cancel => 'Cancel';

  @override
  String get edit_subscription => 'Edit a subscription';

  @override
  String get add_subscription => 'Add a new subscription';

  @override
  String get name => 'Name';

  @override
  String get price => 'Price';

  @override
  String get frequency => 'Frequency';

  @override
  String get name_placeholder => 'Netflix';

  @override
  String get price_placeholder => '9.99';

  @override
  String get please_enter_a_name => 'Please enter a name';

  @override
  String get please_enter_a_price => 'Please enter a price';

  @override
  String get please_enter_a_valid_price => 'Please enter a valid price';

  @override
  String get please_select_a_frequency => 'Please select a frequency';

  @override
  String get bb_gas_stations => 'Gas Stations';

  @override
  String get bb_subscriptions => 'Subscriptions';

  @override
  String get gas_title => 'Gas stations';

  @override
  String get gas_add_station => 'Add a station';

  @override
  String get gas_search_field => 'City or postcode';

  @override
  String get gas_search_hint => 'For example: Angers, or 49100';

  @override
  String get gas_no_result => 'No station found';

  @override
  String get gas_no_station => 'No station followed yet';

  @override
  String get gas_no_station_hint => 'Add one with the + button';

  @override
  String get gas_already_saved => 'Already followed';

  @override
  String get gas_price_unknown => 'Price unknown';

  @override
  String gas_prices_shown(String fuel) {
    return 'Prices shown: $fuel';
  }

  @override
  String get fuel_gazole => 'Diesel';

  @override
  String get fuel_sp95 => 'SP95';

  @override
  String get fuel_sp98 => 'SP98';

  @override
  String get fuel_e10 => 'E10';

  @override
  String get fuel_e85 => 'E85';

  @override
  String get fuel_gplc => 'LPG';

  @override
  String get gas_unreachable => 'Fuel price service unreachable';

  @override
  String get no_subscription => 'No subscription yet';

  @override
  String loading_error(String error) {
    return 'Error: $error';
  }

  @override
  String delete_confirm(String name) {
    return 'Delete $name? This cannot be undone.';
  }

  @override
  String get active => 'Active';

  @override
  String get inactive => 'Inactive';

  @override
  String get logo_code => 'Icon code';

  @override
  String get please_enter_a_logo_code => 'Please enter an icon code';

  @override
  String get please_enter_a_valid_integer => 'Please enter a valid integer';

  @override
  String get settings_title => 'Settings';

  @override
  String get pi_section => 'Raspberry Pi';

  @override
  String get pi_section_hint =>
      'Address and certificate shared by every service hosted on the Pi.';

  @override
  String get qbittorrent_section => 'qBittorrent';

  @override
  String get qbittorrent_section_hint =>
      'Download client, reached on its web interface.';

  @override
  String get agent_section_hint =>
      'Python agent installed on the Pi: hardware, disk and service status.';

  @override
  String get emby_section => 'Emby';

  @override
  String get emby_section_hint =>
      'Library root holding Films, Series and Autres, where qBittorrent drops downloads.';

  @override
  String get tmdb_section => 'TMDB';

  @override
  String get tmdb_section_hint =>
      'Optional: fills in the folder name and its tmdbid tag from a title.';

  @override
  String get server_host => 'Raspberry Pi address';

  @override
  String get server_port => 'Web interface port';

  @override
  String get agent_port => 'Agent port';

  @override
  String get certificate_pinned => 'Trusted certificate';

  @override
  String get certificate_none =>
      'No certificate trusted yet. One will be offered on the first connection test.';

  @override
  String get certificate_forget => 'Forget';

  @override
  String get test_agent => 'Test the agent';

  @override
  String agent_ok(String version) {
    return 'Agent reachable — version $version';
  }

  @override
  String get settings_saved => 'Settings saved';

  @override
  String settings_save_failed(String error) {
    return 'Could not save: $error';
  }

  @override
  String get use_https => 'Use HTTPS';

  @override
  String get use_https_on_hint =>
      'The self-signed certificate is pinned on first connection.';

  @override
  String get use_https_off_hint => 'Traffic and password travel unencrypted.';

  @override
  String get warning_raw_ip_certificate =>
      'With a raw IP address, the certificate must carry that address in its subjectAltName extension.';

  @override
  String get warning_cleartext_blocked =>
      'Android blocks cleartext HTTP in release builds. Only HTTPS will work on device.';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get poll_interval => 'Refresh interval';

  @override
  String get poll_interval_manual => 'Manual';

  @override
  String get test_connection => 'Test connection';

  @override
  String get agent_section => 'iZerak API';

  @override
  String get agent_token => 'Agent token';

  @override
  String get agent_token_hint => 'Generated by install.sh on the Pi.';

  @override
  String get default_save_path => 'Emby library root';

  @override
  String get tmdb_token => 'TMDB token';

  @override
  String get tmdb_token_hint => 'Free personal API key from themoviedb.org.';

  @override
  String get tmdb_attribution =>
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';

  @override
  String get please_enter_a_host => 'Please enter a host';

  @override
  String get please_enter_a_valid_port => 'Port must be between 1 and 65535';

  @override
  String get certificate_title => 'Unknown certificate';

  @override
  String get certificate_explanation =>
      'Compare this fingerprint with the one reported by openssl on the server before trusting it.';

  @override
  String get certificate_trust => 'Trust';

  @override
  String get error_not_configured => 'Server not configured';

  @override
  String get error_invalid_credentials => 'Invalid credentials';

  @override
  String get error_ip_banned =>
      'Address temporarily banned after too many failed logins. Wait, then retry.';

  @override
  String get error_certificate =>
      'The server certificate was refused. It may have changed.';

  @override
  String get error_unreachable => 'Server unreachable';

  @override
  String get error_timeout => 'Request timed out';

  @override
  String connection_ok(String version) {
    return 'Connected — qBittorrent $version';
  }

  @override
  String get bb_torrents => 'Torrents';

  @override
  String get torrents_title => 'Downloads';

  @override
  String get no_torrents => 'No torrent';

  @override
  String get not_configured_message =>
      'Set the server address and credentials to control qBittorrent from here.';

  @override
  String get configure => 'Configure';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String last_updated(String time) {
    return 'Updated at $time';
  }

  @override
  String get add_magnet => 'Add a download';

  @override
  String get magnet_link => 'Magnet link';

  @override
  String get please_enter_a_magnet => 'Please enter a magnet link';

  @override
  String get please_enter_a_valid_magnet =>
      'Expected a magnet: link or a .torrent URL';

  @override
  String get paste => 'Paste';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get delete_torrent => 'Delete torrent';

  @override
  String get delete_files_too => 'Also delete downloaded files';

  @override
  String torrent_added_in(String destination) {
    return 'Added to $destination';
  }

  @override
  String get download_speed => 'Download speed';

  @override
  String get upload_speed => 'Upload speed';

  @override
  String get status_connected => 'Connected';

  @override
  String get status_firewalled => 'Firewalled';

  @override
  String get status_disconnected => 'Disconnected';

  @override
  String get search_title => 'Search the title';

  @override
  String get search_title_hint =>
      'Names the folder so Emby identifies the media.';

  @override
  String get destination_hint =>
      'Sets the qBittorrent category and the library folder.';

  @override
  String get destination_movies => 'Movies';

  @override
  String get destination_series => 'Series';

  @override
  String get destination_other => 'Other';

  @override
  String get emby_folder => 'Destination folder';

  @override
  String get emby_folder_hint =>
      'Emby matches on the Title (Year) [tmdbid=123456] form.';

  @override
  String get tmdb_not_configured =>
      'No TMDB token: fill the folder name manually.';

  @override
  String get tmdb_auth_error => 'TMDB refused the token';

  @override
  String get tmdb_unreachable => 'TMDB unreachable';

  @override
  String get state_downloading => 'Downloading';

  @override
  String get state_fetching_metadata => 'Fetching metadata';

  @override
  String get state_uploading => 'Seeding';

  @override
  String get state_paused => 'Paused';

  @override
  String get state_queued => 'Queued';

  @override
  String get state_stalled => 'Stalled';

  @override
  String get state_checking => 'Checking';

  @override
  String get state_moving => 'Moving';

  @override
  String get state_allocating => 'Allocating';

  @override
  String get state_error => 'Error';

  @override
  String get state_missing_files => 'Missing files';

  @override
  String get state_unknown => 'Unknown';

  @override
  String get bb_system => 'System';

  @override
  String get system_title => 'Raspberry Pi';

  @override
  String get agent_not_configured_message =>
      'Install the agent on the Pi, then paste its token in the settings.';

  @override
  String get uptime => 'Uptime';

  @override
  String get load_average => 'Load average';

  @override
  String get cpu_temp => 'CPU temperature';

  @override
  String get memory => 'Memory';

  @override
  String get storage_disconnected =>
      'External disk disconnected — downloads would fill the SD card.';

  @override
  String get storage_readonly => 'Mounted read-only: the disk is failing.';

  @override
  String get undervoltage_now =>
      'Undervoltage detected right now. Check the power supply.';

  @override
  String get undervoltage_occurred =>
      'Undervoltage occurred since boot. It explains unexplained failures.';

  @override
  String get throttling_occurred => 'Thermal throttling occurred since boot.';

  @override
  String get service_start => 'Start';

  @override
  String get service_stop => 'Stop';

  @override
  String get service_restart => 'Restart';

  @override
  String get confirm => 'Confirm';

  @override
  String get service_active => 'Running';

  @override
  String get service_inactive => 'Stopped';

  @override
  String get service_failed => 'Failed';

  @override
  String get service_activating => 'Starting';

  @override
  String get service_deactivating => 'Stopping';

  @override
  String get error_agent_token => 'The agent refused the token';

  @override
  String get error_agent_unreachable => 'Agent unreachable';

  @override
  String get storage_blocked_add =>
      'Disk unavailable or quota reached: adding is disabled.';

  @override
  String storage_missing(String path) {
    return 'Path $path does not exist';
  }

  @override
  String storage_quota(String used, String quota) {
    return '$used used of $quota allowed';
  }

  @override
  String storage_capacity(String free, String total) {
    return '$free free of $total on the disk';
  }

  @override
  String confirm_service_action(String name) {
    return 'This will interrupt $name. Continue?';
  }

  @override
  String get storage_permission_denied =>
      'The agent cannot read this volume: check its permissions.';
}
