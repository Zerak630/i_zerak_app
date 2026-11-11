import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';

/// Formats de l'onglet Velo, dans la langue de l'application.
///
/// `intl` plutot que `toStringAsFixed` : la cagnotte s'affiche « 37,02 € » en
/// francais, et une virgule decimale oubliee se voit tout de suite sur un
/// montant mis en avant.
class CommuteFormat {
  CommuteFormat(BuildContext context) : _locale = Localizations.localeOf(context).toLanguageTag();

  final String _locale;

  String euros(double value) =>
      NumberFormat.currency(locale: _locale, symbol: '€', decimalDigits: 2).format(value);

  /// Trois decimales, comme l'onglet Carburants.
  String perLitre(double value) =>
      NumberFormat.currency(locale: _locale, symbol: '€', decimalDigits: 3).format(value);

  String number(double value) => NumberFormat('#,##0.##', _locale).format(value);

  String percent(double ratio) => NumberFormat.percentPattern(_locale).format(ratio);

  /// « vendredi 18 septembre »
  String longDay(DateTime day) => DateFormat('EEEE d MMMM', _locale).format(day);

  /// « ven. 18 sept. »
  String shortDay(DateTime day) => DateFormat('E d MMM', _locale).format(day);

  /// « ven. 18 sept. 2026 », pour une liste qui couvre plusieurs annees.
  String shortDayWithYear(DateTime day) => DateFormat('E d MMM y', _locale).format(day);

  /// « 1 juin »
  String dayMonth(DateTime day) => DateFormat('d MMMM', _locale).format(day);

  /// « Septembre 2026 »
  String month(DateTime day) => _capitalize(DateFormat('MMMM y', _locale).format(day));

  /// « septembre », pour une phrase qui le porte en son milieu.
  String monthName(DateTime day) => DateFormat('MMMM', _locale).format(day);

  /// « sept. », pour une regle de mois sous une grille serree.
  String shortMonth(DateTime day) => DateFormat('MMM', _locale).format(day);

  /// « Septembre », pour un titre.
  String monthTitle(DateTime day) => _capitalize(monthName(day));

  /// « mardi », a partir d'un `DateTime.weekday`.
  String weekdayName(int weekday) =>
      // Le 1er janvier 2024 est un lundi : `weekday` vaut alors 1.
      DateFormat('EEEE', _locale).format(DateTime(2024, 1, weekday));

  /// « mar. »
  String weekdayShort(int weekday) =>
      DateFormat('E', _locale).format(DateTime(2024, 1, weekday));

  /// Initiale du jour de la semaine, lundi en tete.
  List<String> weekdayInitials() => [
        for (var i = 0; i < 7; i++)
          // Le 1er janvier 2024 est un lundi.
          DateFormat('EEEEE', _locale).format(DateTime(2024, 1, 1 + i)).toUpperCase(),
      ];

  static String _capitalize(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}

/// Lit un nombre saisi au clavier, virgule ou point.
double? parseDecimal(String raw) =>
    double.tryParse(raw.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));

/// Libelle d'une cagnotte voiture, tel qu'il s'affiche a cote d'une journee.
String bucketLabel(AppLocalizations l10n, CarBucket? bucket) =>
    bucket == CarBucket.missed ? l10n.commute_bucket_missed : l10n.commute_bucket_essential;

/// Libelle d'une journee : le mode, et pour la voiture la cagnotte qu'elle a
/// alimentee — la seule chose qui compte, que le velo ait ete possible ou non.
String dayLabel(AppLocalizations l10n, CommuteDay day) => switch (day.mode) {
      CommuteMode.bike => l10n.commute_legend_bike,
      CommuteMode.remote => l10n.commute_remote,
      CommuteMode.car => bucketLabel(l10n, day.bucket),
    };

/// Une couleur par nature de journee, reprise partout : cagnotte velo en
/// primaire, depenses obligatoires en secondaire, economies loupees en
/// tertiaire, et teletravail dans une teinte a part, qui ne se confond avec
/// aucune des trois.
Color bucketColor(ColorScheme scheme, CarBucket? bucket) =>
    bucket == CarBucket.missed ? scheme.tertiary : scheme.secondary;

final Map<Brightness, ColorScheme> _remoteSchemes = {};

/// Palette du teletravail : un ambre, derive comme le theme de l'application
/// pour rester lisible en clair comme en sombre.
ColorScheme _remoteScheme(ColorScheme scheme) => _remoteSchemes.putIfAbsent(
      scheme.brightness,
      () => ColorScheme.fromSeed(seedColor: Colors.amber, brightness: scheme.brightness),
    );

Color remoteColor(ColorScheme scheme) => _remoteScheme(scheme).primary;

Color dayColor(ColorScheme scheme, CommuteDay? day) {
  if (day == null) {
    return scheme.surfaceContainerHighest;
  }
  return switch (day.mode) {
    CommuteMode.bike => scheme.primary,
    CommuteMode.remote => remoteColor(scheme),
    CommuteMode.car => bucketColor(scheme, day.bucket),
  };
}

/// Fond d'une case de calendrier, et la couleur du texte qui va dessus.
({Color background, Color foreground}) dayContainerColors(ColorScheme scheme, CommuteDay day) {
  if (day.isRemote) {
    final remote = _remoteScheme(scheme);
    return (background: remote.primaryContainer, foreground: remote.onPrimaryContainer);
  }
  if (day.isBike) {
    return (background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer);
  }
  if (day.bucket == CarBucket.missed) {
    return (background: scheme.tertiaryContainer, foreground: scheme.onTertiaryContainer);
  }
  return (background: scheme.secondaryContainer, foreground: scheme.onSecondaryContainer);
}

/// Fond des cases de teletravail, pour une legende.
Color remoteContainerColor(ColorScheme scheme) => _remoteScheme(scheme).primaryContainer;

IconData goalIconData(GoalIcon icon) => switch (icon) {
      GoalIcon.bike => Icons.pedal_bike,
      GoalIcon.helmet => Icons.sports_motorsports_outlined,
      GoalIcon.bag => Icons.shopping_bag_outlined,
      GoalIcon.gift => Icons.card_giftcard,
      GoalIcon.star => Icons.star_outline,
    };

/// Couleur d'un objectif : primaire pour un achat, tertiaire pour un palier,
/// qui se lit ainsi d'un coup d'oeil comme « rien a depenser ».
Color goalColor(ColorScheme scheme, GoalKind kind) =>
    kind == GoalKind.milestone ? scheme.tertiary : scheme.primary;

/// Nombre de trajets a velo qu'il faut encore, au prix du trajet donne.
int? tripsFor(double amount, double tripValue) =>
    tripValue <= 0 || amount <= 0 ? null : (amount / tripValue).ceil();

/// Poignee et marges communes aux feuilles du bas de l'onglet.
class CommuteSheet extends StatelessWidget {
  const CommuteSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        // Suit le clavier : la feuille de creation d'objectif a deux champs,
        // et un bouton masque sous le clavier passerait pour un blocage.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      );
}
