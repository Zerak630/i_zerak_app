import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// The conventional newborn programmer greeting
  ///
  /// In en, this message translates to:
  /// **'Hello World!'**
  String get helloWorld;

  /// No description provided for @subscription_title.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscription_title;

  /// No description provided for @per_week.
  ///
  /// In en, this message translates to:
  /// **'per week'**
  String get per_week;

  /// No description provided for @per_month.
  ///
  /// In en, this message translates to:
  /// **'per month'**
  String get per_month;

  /// No description provided for @per_year.
  ///
  /// In en, this message translates to:
  /// **'per year'**
  String get per_year;

  /// No description provided for @per_week_adjective.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get per_week_adjective;

  /// No description provided for @per_month_adjective.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get per_month_adjective;

  /// No description provided for @per_year_adjective.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get per_year_adjective;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @edit_subscription.
  ///
  /// In en, this message translates to:
  /// **'Edit a subscription'**
  String get edit_subscription;

  /// No description provided for @add_subscription.
  ///
  /// In en, this message translates to:
  /// **'Add a new subscription'**
  String get add_subscription;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @frequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequency;

  /// No description provided for @name_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Netflix'**
  String get name_placeholder;

  /// No description provided for @price_placeholder.
  ///
  /// In en, this message translates to:
  /// **'9.99'**
  String get price_placeholder;

  /// No description provided for @please_enter_a_name.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get please_enter_a_name;

  /// No description provided for @please_enter_a_price.
  ///
  /// In en, this message translates to:
  /// **'Please enter a price'**
  String get please_enter_a_price;

  /// No description provided for @please_enter_a_valid_price.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid price'**
  String get please_enter_a_valid_price;

  /// No description provided for @please_select_a_frequency.
  ///
  /// In en, this message translates to:
  /// **'Please select a frequency'**
  String get please_select_a_frequency;

  /// No description provided for @bb_gas_stations.
  ///
  /// In en, this message translates to:
  /// **'Gas Stations'**
  String get bb_gas_stations;

  /// No description provided for @bb_subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get bb_subscriptions;

  /// No description provided for @gas_title.
  ///
  /// In en, this message translates to:
  /// **'Gas stations'**
  String get gas_title;

  /// No description provided for @gas_add_station.
  ///
  /// In en, this message translates to:
  /// **'Add a station'**
  String get gas_add_station;

  /// No description provided for @gas_search_field.
  ///
  /// In en, this message translates to:
  /// **'City or postcode'**
  String get gas_search_field;

  /// No description provided for @gas_search_hint.
  ///
  /// In en, this message translates to:
  /// **'For example: Angers, or 49100'**
  String get gas_search_hint;

  /// No description provided for @gas_no_result.
  ///
  /// In en, this message translates to:
  /// **'No station found'**
  String get gas_no_result;

  /// No description provided for @gas_no_station.
  ///
  /// In en, this message translates to:
  /// **'No station followed yet'**
  String get gas_no_station;

  /// No description provided for @gas_no_station_hint.
  ///
  /// In en, this message translates to:
  /// **'Add one with the + button'**
  String get gas_no_station_hint;

  /// No description provided for @gas_already_saved.
  ///
  /// In en, this message translates to:
  /// **'Already followed'**
  String get gas_already_saved;

  /// No description provided for @gas_price_unknown.
  ///
  /// In en, this message translates to:
  /// **'Price unknown'**
  String get gas_price_unknown;

  /// No description provided for @gas_prices_shown.
  ///
  /// In en, this message translates to:
  /// **'Prices shown: {fuel}'**
  String gas_prices_shown(String fuel);

  /// No description provided for @gas_navigate.
  ///
  /// In en, this message translates to:
  /// **'Directions'**
  String get gas_navigate;

  /// No description provided for @gas_maps_unavailable.
  ///
  /// In en, this message translates to:
  /// **'No navigation app found'**
  String get gas_maps_unavailable;

  /// No description provided for @gas_rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get gas_rename;

  /// No description provided for @gas_station_name.
  ///
  /// In en, this message translates to:
  /// **'Station name'**
  String get gas_station_name;

  /// No description provided for @gas_rename_hint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to restore the address'**
  String get gas_rename_hint;

  /// No description provided for @fuel_gazole.
  ///
  /// In en, this message translates to:
  /// **'Diesel'**
  String get fuel_gazole;

  /// No description provided for @fuel_sp95.
  ///
  /// In en, this message translates to:
  /// **'SP95'**
  String get fuel_sp95;

  /// No description provided for @fuel_sp98.
  ///
  /// In en, this message translates to:
  /// **'SP98'**
  String get fuel_sp98;

  /// No description provided for @fuel_e10.
  ///
  /// In en, this message translates to:
  /// **'E10'**
  String get fuel_e10;

  /// No description provided for @fuel_e85.
  ///
  /// In en, this message translates to:
  /// **'E85'**
  String get fuel_e85;

  /// No description provided for @fuel_gplc.
  ///
  /// In en, this message translates to:
  /// **'LPG'**
  String get fuel_gplc;

  /// No description provided for @gas_unreachable.
  ///
  /// In en, this message translates to:
  /// **'Fuel price service unreachable'**
  String get gas_unreachable;

  /// No description provided for @no_subscription.
  ///
  /// In en, this message translates to:
  /// **'No subscription yet'**
  String get no_subscription;

  /// No description provided for @loading_error.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String loading_error(String error);

  /// No description provided for @delete_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? This cannot be undone.'**
  String delete_confirm(String name);

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @logo_code.
  ///
  /// In en, this message translates to:
  /// **'Icon code'**
  String get logo_code;

  /// No description provided for @please_enter_a_logo_code.
  ///
  /// In en, this message translates to:
  /// **'Please enter an icon code'**
  String get please_enter_a_logo_code;

  /// No description provided for @please_enter_a_valid_integer.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid integer'**
  String get please_enter_a_valid_integer;

  /// No description provided for @settings_title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// No description provided for @pi_section.
  ///
  /// In en, this message translates to:
  /// **'Raspberry Pi'**
  String get pi_section;

  /// No description provided for @pi_section_hint.
  ///
  /// In en, this message translates to:
  /// **'Address and certificate shared by every service hosted on the Pi.'**
  String get pi_section_hint;

  /// No description provided for @qbittorrent_section.
  ///
  /// In en, this message translates to:
  /// **'qBittorrent'**
  String get qbittorrent_section;

  /// No description provided for @qbittorrent_section_hint.
  ///
  /// In en, this message translates to:
  /// **'Download client, reached on its web interface.'**
  String get qbittorrent_section_hint;

  /// No description provided for @agent_section_hint.
  ///
  /// In en, this message translates to:
  /// **'Python agent installed on the Pi: hardware, disk and service status.'**
  String get agent_section_hint;

  /// No description provided for @emby_section.
  ///
  /// In en, this message translates to:
  /// **'Emby'**
  String get emby_section;

  /// No description provided for @emby_section_hint.
  ///
  /// In en, this message translates to:
  /// **'Library root holding Films, Series and Autres, where qBittorrent drops downloads.'**
  String get emby_section_hint;

  /// No description provided for @tmdb_section.
  ///
  /// In en, this message translates to:
  /// **'TMDB'**
  String get tmdb_section;

  /// No description provided for @tmdb_section_hint.
  ///
  /// In en, this message translates to:
  /// **'Optional: fills in the folder name and its tmdbid tag from a title.'**
  String get tmdb_section_hint;

  /// No description provided for @server_host.
  ///
  /// In en, this message translates to:
  /// **'Raspberry Pi address'**
  String get server_host;

  /// No description provided for @server_port.
  ///
  /// In en, this message translates to:
  /// **'Web interface port'**
  String get server_port;

  /// No description provided for @agent_port.
  ///
  /// In en, this message translates to:
  /// **'Agent port'**
  String get agent_port;

  /// No description provided for @certificate_pinned.
  ///
  /// In en, this message translates to:
  /// **'Trusted certificate'**
  String get certificate_pinned;

  /// No description provided for @certificate_none.
  ///
  /// In en, this message translates to:
  /// **'No certificate trusted yet. One will be offered on the first connection test.'**
  String get certificate_none;

  /// No description provided for @certificate_forget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get certificate_forget;

  /// No description provided for @test_agent.
  ///
  /// In en, this message translates to:
  /// **'Test the agent'**
  String get test_agent;

  /// No description provided for @agent_ok.
  ///
  /// In en, this message translates to:
  /// **'Agent reachable — version {version}'**
  String agent_ok(String version);

  /// No description provided for @settings_saved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settings_saved;

  /// No description provided for @settings_save_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String settings_save_failed(String error);

  /// No description provided for @use_https.
  ///
  /// In en, this message translates to:
  /// **'Use HTTPS'**
  String get use_https;

  /// No description provided for @use_https_on_hint.
  ///
  /// In en, this message translates to:
  /// **'The self-signed certificate is pinned on first connection.'**
  String get use_https_on_hint;

  /// No description provided for @use_https_off_hint.
  ///
  /// In en, this message translates to:
  /// **'Traffic and password travel unencrypted.'**
  String get use_https_off_hint;

  /// No description provided for @warning_raw_ip_certificate.
  ///
  /// In en, this message translates to:
  /// **'With a raw IP address, the certificate must carry that address in its subjectAltName extension.'**
  String get warning_raw_ip_certificate;

  /// No description provided for @warning_cleartext_blocked.
  ///
  /// In en, this message translates to:
  /// **'Android blocks cleartext HTTP in release builds. Only HTTPS will work on device.'**
  String get warning_cleartext_blocked;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @poll_interval.
  ///
  /// In en, this message translates to:
  /// **'Refresh interval'**
  String get poll_interval;

  /// No description provided for @poll_interval_manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get poll_interval_manual;

  /// No description provided for @test_connection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get test_connection;

  /// No description provided for @agent_section.
  ///
  /// In en, this message translates to:
  /// **'iZerak API'**
  String get agent_section;

  /// No description provided for @agent_token.
  ///
  /// In en, this message translates to:
  /// **'Agent token'**
  String get agent_token;

  /// No description provided for @agent_token_hint.
  ///
  /// In en, this message translates to:
  /// **'Generated by install.sh on the Pi.'**
  String get agent_token_hint;

  /// No description provided for @default_save_path.
  ///
  /// In en, this message translates to:
  /// **'Emby library root'**
  String get default_save_path;

  /// No description provided for @tmdb_token.
  ///
  /// In en, this message translates to:
  /// **'TMDB token'**
  String get tmdb_token;

  /// No description provided for @tmdb_token_hint.
  ///
  /// In en, this message translates to:
  /// **'Free personal API key from themoviedb.org.'**
  String get tmdb_token_hint;

  /// No description provided for @tmdb_attribution.
  ///
  /// In en, this message translates to:
  /// **'This product uses the TMDB API but is not endorsed or certified by TMDB.'**
  String get tmdb_attribution;

  /// No description provided for @please_enter_a_host.
  ///
  /// In en, this message translates to:
  /// **'Please enter a host'**
  String get please_enter_a_host;

  /// No description provided for @please_enter_a_valid_port.
  ///
  /// In en, this message translates to:
  /// **'Port must be between 1 and 65535'**
  String get please_enter_a_valid_port;

  /// No description provided for @certificate_title.
  ///
  /// In en, this message translates to:
  /// **'Unknown certificate'**
  String get certificate_title;

  /// No description provided for @certificate_explanation.
  ///
  /// In en, this message translates to:
  /// **'Compare this fingerprint with the one reported by openssl on the server before trusting it.'**
  String get certificate_explanation;

  /// No description provided for @certificate_trust.
  ///
  /// In en, this message translates to:
  /// **'Trust'**
  String get certificate_trust;

  /// No description provided for @error_not_configured.
  ///
  /// In en, this message translates to:
  /// **'Server not configured'**
  String get error_not_configured;

  /// No description provided for @error_invalid_credentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials'**
  String get error_invalid_credentials;

  /// No description provided for @error_ip_banned.
  ///
  /// In en, this message translates to:
  /// **'Address temporarily banned after too many failed logins. Wait, then retry.'**
  String get error_ip_banned;

  /// No description provided for @error_certificate.
  ///
  /// In en, this message translates to:
  /// **'The server certificate was refused. It may have changed.'**
  String get error_certificate;

  /// No description provided for @error_unreachable.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable'**
  String get error_unreachable;

  /// No description provided for @error_timeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out'**
  String get error_timeout;

  /// No description provided for @connection_ok.
  ///
  /// In en, this message translates to:
  /// **'Connected — qBittorrent {version}'**
  String connection_ok(String version);

  /// No description provided for @bb_torrents.
  ///
  /// In en, this message translates to:
  /// **'Torrents'**
  String get bb_torrents;

  /// No description provided for @torrents_title.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get torrents_title;

  /// No description provided for @no_torrents.
  ///
  /// In en, this message translates to:
  /// **'No torrent'**
  String get no_torrents;

  /// No description provided for @not_configured_message.
  ///
  /// In en, this message translates to:
  /// **'Set the server address and credentials to control qBittorrent from here.'**
  String get not_configured_message;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @last_updated.
  ///
  /// In en, this message translates to:
  /// **'Updated at {time}'**
  String last_updated(String time);

  /// No description provided for @add_magnet.
  ///
  /// In en, this message translates to:
  /// **'Add a download'**
  String get add_magnet;

  /// No description provided for @magnet_link.
  ///
  /// In en, this message translates to:
  /// **'Magnet link'**
  String get magnet_link;

  /// No description provided for @please_enter_a_magnet.
  ///
  /// In en, this message translates to:
  /// **'Please enter a magnet link'**
  String get please_enter_a_magnet;

  /// No description provided for @please_enter_a_valid_magnet.
  ///
  /// In en, this message translates to:
  /// **'Expected a magnet: link or a .torrent URL'**
  String get please_enter_a_valid_magnet;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @delete_torrent.
  ///
  /// In en, this message translates to:
  /// **'Delete torrent'**
  String get delete_torrent;

  /// No description provided for @delete_files_too.
  ///
  /// In en, this message translates to:
  /// **'Also delete downloaded files'**
  String get delete_files_too;

  /// No description provided for @torrent_added_in.
  ///
  /// In en, this message translates to:
  /// **'Added to {destination}'**
  String torrent_added_in(String destination);

  /// No description provided for @download_speed.
  ///
  /// In en, this message translates to:
  /// **'Download speed'**
  String get download_speed;

  /// No description provided for @upload_speed.
  ///
  /// In en, this message translates to:
  /// **'Upload speed'**
  String get upload_speed;

  /// No description provided for @status_connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get status_connected;

  /// No description provided for @status_firewalled.
  ///
  /// In en, this message translates to:
  /// **'Firewalled'**
  String get status_firewalled;

  /// No description provided for @status_disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get status_disconnected;

  /// No description provided for @search_title.
  ///
  /// In en, this message translates to:
  /// **'Search the title'**
  String get search_title;

  /// No description provided for @search_title_hint.
  ///
  /// In en, this message translates to:
  /// **'Names the folder so Emby identifies the media.'**
  String get search_title_hint;

  /// No description provided for @destination_hint.
  ///
  /// In en, this message translates to:
  /// **'Sets the qBittorrent category and the library folder.'**
  String get destination_hint;

  /// No description provided for @destination_movies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get destination_movies;

  /// No description provided for @destination_series.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get destination_series;

  /// No description provided for @destination_other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get destination_other;

  /// No description provided for @emby_folder.
  ///
  /// In en, this message translates to:
  /// **'Destination folder'**
  String get emby_folder;

  /// No description provided for @emby_folder_hint.
  ///
  /// In en, this message translates to:
  /// **'Emby matches on the Title (Year) [tmdbid=123456] form.'**
  String get emby_folder_hint;

  /// No description provided for @tmdb_not_configured.
  ///
  /// In en, this message translates to:
  /// **'No TMDB token: fill the folder name manually.'**
  String get tmdb_not_configured;

  /// No description provided for @tmdb_auth_error.
  ///
  /// In en, this message translates to:
  /// **'TMDB refused the token'**
  String get tmdb_auth_error;

  /// No description provided for @tmdb_unreachable.
  ///
  /// In en, this message translates to:
  /// **'TMDB unreachable'**
  String get tmdb_unreachable;

  /// No description provided for @state_downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get state_downloading;

  /// No description provided for @state_fetching_metadata.
  ///
  /// In en, this message translates to:
  /// **'Fetching metadata'**
  String get state_fetching_metadata;

  /// No description provided for @state_uploading.
  ///
  /// In en, this message translates to:
  /// **'Seeding'**
  String get state_uploading;

  /// No description provided for @state_paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get state_paused;

  /// No description provided for @state_queued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get state_queued;

  /// No description provided for @state_stalled.
  ///
  /// In en, this message translates to:
  /// **'Stalled'**
  String get state_stalled;

  /// No description provided for @state_checking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get state_checking;

  /// No description provided for @state_moving.
  ///
  /// In en, this message translates to:
  /// **'Moving'**
  String get state_moving;

  /// No description provided for @state_allocating.
  ///
  /// In en, this message translates to:
  /// **'Allocating'**
  String get state_allocating;

  /// No description provided for @state_error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get state_error;

  /// No description provided for @state_missing_files.
  ///
  /// In en, this message translates to:
  /// **'Missing files'**
  String get state_missing_files;

  /// No description provided for @state_unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get state_unknown;

  /// No description provided for @bb_system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get bb_system;

  /// No description provided for @system_title.
  ///
  /// In en, this message translates to:
  /// **'Raspberry Pi'**
  String get system_title;

  /// No description provided for @agent_not_configured_message.
  ///
  /// In en, this message translates to:
  /// **'Install the agent on the Pi, then paste its token in the settings.'**
  String get agent_not_configured_message;

  /// No description provided for @uptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get uptime;

  /// No description provided for @load_average.
  ///
  /// In en, this message translates to:
  /// **'Load average'**
  String get load_average;

  /// No description provided for @cpu_temp.
  ///
  /// In en, this message translates to:
  /// **'CPU temperature'**
  String get cpu_temp;

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @storage_disconnected.
  ///
  /// In en, this message translates to:
  /// **'External disk disconnected — downloads would fill the SD card.'**
  String get storage_disconnected;

  /// No description provided for @storage_readonly.
  ///
  /// In en, this message translates to:
  /// **'Mounted read-only: the disk is failing.'**
  String get storage_readonly;

  /// No description provided for @undervoltage_now.
  ///
  /// In en, this message translates to:
  /// **'Undervoltage detected right now. Check the power supply.'**
  String get undervoltage_now;

  /// No description provided for @undervoltage_occurred.
  ///
  /// In en, this message translates to:
  /// **'Undervoltage occurred since boot. It explains unexplained failures.'**
  String get undervoltage_occurred;

  /// No description provided for @throttling_occurred.
  ///
  /// In en, this message translates to:
  /// **'Thermal throttling occurred since boot.'**
  String get throttling_occurred;

  /// No description provided for @service_start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get service_start;

  /// No description provided for @service_stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get service_stop;

  /// No description provided for @service_restart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get service_restart;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @service_active.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get service_active;

  /// No description provided for @service_inactive.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get service_inactive;

  /// No description provided for @service_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get service_failed;

  /// No description provided for @service_activating.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get service_activating;

  /// No description provided for @service_deactivating.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get service_deactivating;

  /// No description provided for @error_agent_token.
  ///
  /// In en, this message translates to:
  /// **'The agent refused the token'**
  String get error_agent_token;

  /// No description provided for @error_agent_unreachable.
  ///
  /// In en, this message translates to:
  /// **'Agent unreachable'**
  String get error_agent_unreachable;

  /// No description provided for @storage_blocked_add.
  ///
  /// In en, this message translates to:
  /// **'Disk unavailable or quota reached: adding is disabled.'**
  String get storage_blocked_add;

  /// No description provided for @storage_missing.
  ///
  /// In en, this message translates to:
  /// **'Path {path} does not exist'**
  String storage_missing(String path);

  /// No description provided for @storage_quota.
  ///
  /// In en, this message translates to:
  /// **'{used} used of {quota} allowed'**
  String storage_quota(String used, String quota);

  /// No description provided for @storage_capacity.
  ///
  /// In en, this message translates to:
  /// **'{free} free of {total} on the disk'**
  String storage_capacity(String free, String total);

  /// No description provided for @confirm_service_action.
  ///
  /// In en, this message translates to:
  /// **'This will interrupt {name}. Continue?'**
  String confirm_service_action(String name);

  /// No description provided for @storage_permission_denied.
  ///
  /// In en, this message translates to:
  /// **'The agent cannot read this volume: check its permissions.'**
  String get storage_permission_denied;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
