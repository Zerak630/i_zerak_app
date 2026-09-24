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
  String get gas_navigate => 'Directions';

  @override
  String get gas_maps_unavailable => 'No navigation app found';

  @override
  String get gas_rename => 'Rename';

  @override
  String get gas_station_name => 'Station name';

  @override
  String get gas_rename_hint => 'Leave empty to restore the address';

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
  String get service_open => 'Open';

  @override
  String service_open_failed(String name) {
    return 'Could not open $name';
  }

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

  @override
  String get bb_commute => 'Bike';

  @override
  String get commute_pot => 'Bike savings';

  @override
  String commute_bike_trips(int count, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bike trips since $date',
      one: '1 bike trip since $date',
    );
    return '$_temp0';
  }

  @override
  String get commute_no_bike_trip => 'No bike trip yet';

  @override
  String commute_saved_and_spent(String total, String spent) {
    return '$total saved · $spent spent';
  }

  @override
  String get commute_last_14_days => 'Last 14 days';

  @override
  String commute_today(String date) {
    return 'Today · $date';
  }

  @override
  String get commute_today_short => 'today';

  @override
  String get commute_nothing_today => 'nothing recorded';

  @override
  String get commute_by_bike => 'By bike';

  @override
  String commute_by_bike_gain(String amount) {
    return '+ $amount saved';
  }

  @override
  String get commute_by_car => 'By car';

  @override
  String get commute_recorded_bike => 'Bike, today';

  @override
  String commute_recorded_car(String reason) {
    return 'Car, today · $reason';
  }

  @override
  String commute_recorded_detail(String amount, String date) {
    return '$amount · $date';
  }

  @override
  String get commute_undo => 'Undo';

  @override
  String get ok => 'OK';

  @override
  String commute_snack_bike(String amount) {
    return 'Bike recorded — $amount saved';
  }

  @override
  String commute_snack_car(String reason) {
    return 'Car recorded · $reason';
  }

  @override
  String get commute_essential => 'Essential costs';

  @override
  String get commute_missed => 'Missed savings';

  @override
  String commute_days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
      zero: 'no day',
    );
    return '$_temp0';
  }

  @override
  String commute_price_live(String fuel, String price) {
    return 'Cheapest $fuel · $price/L';
  }

  @override
  String commute_price_last_known(String price) {
    return 'Last known price · $price/L';
  }

  @override
  String commute_price_last_known_detail(String date) {
    return 'Stations unreachable — seen on $date';
  }

  @override
  String commute_price_fallback(String price) {
    return 'Default price · $price/L';
  }

  @override
  String get commute_price_fallback_detail => 'No price seen yet';

  @override
  String get commute_recent => 'Recent days';

  @override
  String get commute_see_all => 'See all';

  @override
  String get commute_setup_title => 'Set up your commute';

  @override
  String get commute_setup_hint =>
      'Enter the round-trip distance: every bike trip will then feed the savings.';

  @override
  String get commute_setup_action => 'Set up';

  @override
  String get commute_settings_title => 'Commute';

  @override
  String get commute_settings_entry_hint =>
      'Distance, fuel use and reasons for taking the car';

  @override
  String get commute_section_trip => 'The trip';

  @override
  String get commute_distance => 'Round-trip distance';

  @override
  String get commute_distance_help => 'Door to door, there and back.';

  @override
  String get commute_consumption => 'Average fuel use';

  @override
  String get commute_consumption_help => 'That of the car the bike replaces.';

  @override
  String get commute_fuel => 'Fuel';

  @override
  String get commute_invalid_number => 'Invalid number';

  @override
  String get commute_section_price => 'Price used';

  @override
  String get commute_price_rule =>
      'The cheapest among your followed stations, read on the day of the trip and then kept as is.';

  @override
  String get commute_price_unreachable_rule => 'Stations unreachable';

  @override
  String get commute_price_unreachable_value => 'last price seen';

  @override
  String get commute_price_never_rule => 'No price ever seen';

  @override
  String get commute_section_reasons => 'Reasons for taking the car';

  @override
  String get commute_bucket_essential => 'Essential cost';

  @override
  String get commute_bucket_missed => 'Missed saving';

  @override
  String get commute_add_reason => 'Add a reason';

  @override
  String get commute_reason_name => 'Reason';

  @override
  String get commute_rename_reason => 'Rename reason';

  @override
  String get commute_rename_reason_hint =>
      'Leave empty to restore the original name';

  @override
  String commute_reason_uses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Used on $count days',
      one: 'Used on 1 day',
    );
    return '$_temp0';
  }

  @override
  String get commute_reason_actions => 'Reason actions';

  @override
  String get commute_reason_in_use => 'Delete (already used)';

  @override
  String get commute_trip_value_today => 'One trip is worth today';

  @override
  String commute_trip_formula(
      String distance, String consumption, String price) {
    return '$distance km × $consumption L/100 km × $price/L';
  }

  @override
  String get reason_sport => 'Evening sport';

  @override
  String get reason_shopping => 'Shopping';

  @override
  String get reason_lazy => 'Couldn\'t be bothered';

  @override
  String get commute_why_car => 'Why the car?';

  @override
  String commute_why_car_detail(String date, String amount) {
    return '$date — this trip is worth $amount';
  }

  @override
  String get commute_bucket_essential_hint => 'The car was needed';

  @override
  String get commute_bucket_missed_hint => 'The bike was possible';

  @override
  String get commute_chip_essential => 'Essential';

  @override
  String get commute_chip_missed => 'Missed';

  @override
  String get commute_history_title => 'History';

  @override
  String get commute_legend_bike => 'Bike';

  @override
  String get commute_legend_essential => 'Essential';

  @override
  String get commute_legend_missed => 'Missed';

  @override
  String get commute_history_hint => 'Tap a day to correct or clear it.';

  @override
  String get commute_clear_day => 'Clear this day';

  @override
  String get commute_import => 'Import from Google Maps';

  @override
  String get commute_import_title => 'Google Maps import';

  @override
  String get commute_import_reading => 'Reading the file…';

  @override
  String get commute_import_invalid =>
      'This file is not a Google Maps Timeline export.';

  @override
  String get commute_import_empty => 'No bike trip in this file.';

  @override
  String get commute_import_privacy =>
      'The file is read on the phone: nothing is sent.';

  @override
  String get commute_import_commutes => 'Home ↔ work';

  @override
  String get commute_import_commutes_hint =>
      'Recognised by Google Maps: ticked by default.';

  @override
  String get commute_import_others => 'Other weekday bike rides';

  @override
  String get commute_import_others_hint =>
      'Tick them if they really were commutes.';

  @override
  String get commute_import_round_trip => 'there and back';

  @override
  String commute_import_legs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
    );
    return '$_temp0';
  }

  @override
  String commute_import_detail(String km, String legs) {
    return '$km km · $legs';
  }

  @override
  String get commute_import_already => 'already recorded';

  @override
  String commute_import_action(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Import $count days',
      one: 'Import 1 day',
      zero: 'Nothing to import',
    );
    return '$_temp0';
  }

  @override
  String commute_import_value(String amount, String trip) {
    return '$amount at today\'s price ($trip per day)';
  }

  @override
  String commute_import_done(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days imported',
      one: '1 day imported',
    );
    return '$_temp0';
  }

  @override
  String get commute_import_needs_setup =>
      'Set the commute distance first: it values every imported day.';

  @override
  String get commute_validated_goals => 'Goals reached';

  @override
  String commute_validated_on(String amount, String date) {
    return '$amount · on $date';
  }

  @override
  String get goal_label_purchase => 'Goal';

  @override
  String get goal_label_milestone => 'Milestone';

  @override
  String get goal_reached => 'Reached';

  @override
  String goal_progress_purchase(String current, String target) {
    return '$current of $target';
  }

  @override
  String goal_progress_milestone(String current, String target) {
    return '$current saved of $target';
  }

  @override
  String goal_remaining(String amount, int trips) {
    String _temp0 = intl.Intl.pluralLogic(
      trips,
      locale: localeName,
      other: '$amount to go — about $trips bike trips',
      one: '$amount to go — about 1 bike trip',
    );
    return '$_temp0';
  }

  @override
  String goal_remaining_amount(String amount) {
    return '$amount to go';
  }

  @override
  String get goal_milestone_hint =>
      'Measured on total savings: nothing to spend';

  @override
  String goal_spend_validate(String amount) {
    return 'Spend $amount and validate';
  }

  @override
  String get goal_validate_milestone => 'Validate the milestone';

  @override
  String get goal_new => 'New goal';

  @override
  String get goal_kind_purchase => 'Purchase';

  @override
  String get goal_kind_purchase_hint => 'paid with the savings';

  @override
  String get goal_kind_milestone => 'Milestone';

  @override
  String get goal_kind_milestone_hint => 'reached, nothing spent';

  @override
  String get goal_name => 'Name';

  @override
  String get goal_amount => 'Amount';

  @override
  String get goal_icon => 'Icon';

  @override
  String goal_missing(String amount) {
    return '$amount to go';
  }

  @override
  String goal_missing_trips(int trips, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      trips,
      locale: localeName,
      other: 'About $trips bike trips, at today\'s trip value ($amount).',
      one: 'About 1 bike trip, at today\'s trip value ($amount).',
    );
    return '$_temp0';
  }

  @override
  String get goal_already_reached => 'Already reached with what you have saved';

  @override
  String get goal_create => 'Create goal';

  @override
  String goal_validate_title(String name) {
    return 'Validate “$name”?';
  }

  @override
  String goal_validate_purchase_detail(String amount) {
    return '$amount leave the savings. The goal moves to the goals reached.';
  }

  @override
  String get goal_validate_milestone_detail =>
      'Nothing is spent: the milestone moves to the goals reached.';

  @override
  String get goal_row_pot => 'Savings';

  @override
  String get goal_row_saved => 'Saved in total';

  @override
  String get goal_unchanged => 'unchanged';

  @override
  String goal_spend(String amount) {
    return 'Spend $amount';
  }

  @override
  String get goal_delete => 'Delete goal';

  @override
  String get goal_invalid_amount => 'Invalid amount';

  @override
  String get sub_unit_week => 'week';

  @override
  String get sub_unit_month => 'month';

  @override
  String get sub_unit_year => 'year';

  @override
  String get sub_cost_week => 'Weekly cost';

  @override
  String get sub_cost_month => 'Monthly cost';

  @override
  String get sub_cost_year => 'Yearly cost';

  @override
  String get category_home => 'Home';

  @override
  String get category_insurance => 'Insurance';

  @override
  String get category_sport => 'Sport';

  @override
  String get category_video => 'Video';

  @override
  String get category_telecom => 'Telecom';

  @override
  String get category_music => 'Music';

  @override
  String get category_software => 'Software';

  @override
  String get sub_category_none => 'Other';

  @override
  String get sub_category => 'Category';

  @override
  String get sub_new_category => 'New';

  @override
  String get sub_category_name => 'Category name';

  @override
  String get icon_group_home => 'Home and groceries';

  @override
  String get icon_group_leisure => 'Leisure';

  @override
  String get icon_group_fitness => 'Fitness';

  @override
  String get icon_group_services => 'Transport and services';

  @override
  String get sub_choose_icon => 'Choose an icon';

  @override
  String get sub_change_icon => 'Change the icon';

  @override
  String get sub_icon_color_hint =>
      'The tint comes from the category: changing it recolours the icon.';

  @override
  String get sub_next_payment => 'Next payment';

  @override
  String get sub_no_date => 'Not set';

  @override
  String get sub_clear_date => 'Clear the date';

  @override
  String sub_repeat_week(String weekday) {
    return 'then every $weekday';
  }

  @override
  String sub_repeat_month(int day) {
    return 'then on the $day of every month';
  }

  @override
  String sub_repeat_year(String date) {
    return 'then on $date every year';
  }

  @override
  String sub_every_weekday(String weekday) {
    return 'every $weekday';
  }

  @override
  String sub_on_date(String date) {
    return 'on $date';
  }

  @override
  String get sub_active_hint => 'Counted in the totals';

  @override
  String get sub_inactive_hint => 'Left out of the totals';

  @override
  String get sub_saved => 'Subscription saved';

  @override
  String get sub_deleted => 'Subscription deleted';

  @override
  String get sub_empty_hint => 'Add one with the + button';

  @override
  String sub_active_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active subscriptions',
      one: '1 active subscription',
      zero: 'No active subscription',
    );
    return '$_temp0';
  }

  @override
  String sub_suspended_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suspended',
      one: '1 suspended',
    );
    return '$_temp0';
  }

  @override
  String sub_heaviest(String name, String amount) {
    return 'Heaviest: $name, $amount a year.';
  }

  @override
  String get sub_expand_detail => 'Expand the category breakdown';

  @override
  String get sub_sorted_by_cost => 'By decreasing cost';

  @override
  String sub_filter_all(int count) {
    return 'All · $count';
  }

  @override
  String get sub_suspended_section => 'Suspended';

  @override
  String get sub_out_of_totals => 'out of the totals';

  @override
  String get sub_if_resumed => 'If everything resumed';

  @override
  String get sub_today => 'Today';

  @override
  String get sub_tomorrow => 'Tomorrow';

  @override
  String sub_more_this_month(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more before the end of the month',
      one: '1 more before the end of the month',
    );
    return '$_temp0';
  }

  @override
  String get sub_no_upcoming => 'No known due date';

  @override
  String get sub_no_upcoming_hint => 'Set a date to see payments coming';

  @override
  String get sub_payments_title => 'Payments';

  @override
  String get sub_previous_month => 'Previous month';

  @override
  String get sub_next_month => 'Next month';

  @override
  String get sub_already_paid => 'Already paid';

  @override
  String get sub_remaining => 'Left to pay';

  @override
  String sub_payments_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '1 payment',
      zero: 'no payment',
    );
    return '$_temp0';
  }

  @override
  String sub_month_vs_average(String month, String amount, String average) {
    return '$month: $amount, against an average of $average a month.';
  }

  @override
  String get sub_no_payment_this_month => 'No payment this month';
}
