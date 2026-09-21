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

  /// « 1 juin »
  String dayMonth(DateTime day) => DateFormat('d MMMM', _locale).format(day);

  /// « Septembre 2026 »
  String month(DateTime day) => _capitalize(DateFormat('MMMM y', _locale).format(day));

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

/// Libelle d'une raison : localise pour les trois raisons livrees, tel que
/// saisi pour les autres.
String reasonLabel(AppLocalizations l10n, {required String? id, String? label}) =>
    label ??
    switch (id) {
      CarReason.sport => l10n.reason_sport,
      CarReason.shopping => l10n.reason_shopping,
      CarReason.lazy => l10n.reason_lazy,
      _ => id ?? '',
    };

String carReasonLabel(AppLocalizations l10n, CarReason reason) =>
    reasonLabel(l10n, id: reason.id, label: reason.label);

/// Libelle d'une journee. Une raison encore presente dans les reglages donne
/// son nom actuel : la renommer renomme aussi l'historique. La copie gardee
/// dans la journee ne sert que si la raison a disparu.
String dayLabel(AppLocalizations l10n, CommuteDay day, List<CarReason> reasons) {
  if (day.isBike) {
    return l10n.commute_legend_bike;
  }
  for (final reason in reasons) {
    if (reason.id == day.reasonId) {
      return carReasonLabel(l10n, reason);
    }
  }
  return reasonLabel(l10n, id: day.reasonId, label: day.reasonLabel);
}

/// Une couleur par nature de journee, reprise partout : cagnotte velo en
/// primaire, couts indispensables en secondaire, economies loupees en
/// tertiaire.
Color bucketColor(ColorScheme scheme, CarBucket? bucket) =>
    bucket == CarBucket.missed ? scheme.tertiary : scheme.secondary;

Color dayColor(ColorScheme scheme, CommuteDay? day) {
  if (day == null) {
    return scheme.surfaceContainerHighest;
  }
  return day.isBike ? scheme.primary : bucketColor(scheme, day.bucket);
}

/// Fond d'une case de calendrier, et la couleur du texte qui va dessus.
({Color background, Color foreground}) dayContainerColors(ColorScheme scheme, CommuteDay day) {
  if (day.isBike) {
    return (background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer);
  }
  if (day.bucket == CarBucket.missed) {
    return (background: scheme.tertiaryContainer, foreground: scheme.onTertiaryContainer);
  }
  return (background: scheme.secondaryContainer, foreground: scheme.onSecondaryContainer);
}

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

/// Renommage d'une raison. Renvoie le nouveau nom, une chaine vide pour rendre
/// a une raison livree son nom d'origine, ou `null` si rien ne change.
Future<String?> showRenameReasonDialog(
  BuildContext context, {
  required String current,
  required bool builtIn,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _RenameReasonDialog(current: current, builtIn: builtIn),
    );

class _RenameReasonDialog extends StatefulWidget {
  const _RenameReasonDialog({required this.current, required this.builtIn});

  final String current;
  final bool builtIn;

  @override
  State<_RenameReasonDialog> createState() => _RenameReasonDialogState();
}

class _RenameReasonDialogState extends State<_RenameReasonDialog> {
  late final _controller = TextEditingController(text: widget.current)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.current.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    // Une raison ajoutee a la main n'a pas de nom d'origine ou revenir.
    if (name.isEmpty && !widget.builtIn) {
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.commute_rename_reason),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l10n.commute_reason_name,
          helperText: widget.builtIn ? l10n.commute_rename_reason_hint : null,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}

/// Ajout d'une raison de prendre la voiture : un nom et la cagnotte visee.
Future<CarReason?> showAddReasonDialog(BuildContext context) =>
    showDialog<CarReason>(context: context, builder: (_) => const _AddReasonDialog());

class _AddReasonDialog extends StatefulWidget {
  const _AddReasonDialog();

  @override
  State<_AddReasonDialog> createState() => _AddReasonDialogState();
}

class _AddReasonDialogState extends State<_AddReasonDialog> {
  // Possede par l'etat, et non cree dans la fonction qui ouvre le dialogue :
  // le liberer au retour de `showDialog` le ferait pendant l'animation de
  // fermeture, alors que le champ s'affiche encore.
  final _controller = TextEditingController();
  var _bucket = CarBucket.essential;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      CarReason(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        label: name,
        bucket: _bucket,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.commute_add_reason),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.commute_reason_name),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          SegmentedButton<CarBucket>(
            segments: [
              ButtonSegment(value: CarBucket.essential, label: Text(l10n.commute_chip_essential)),
              ButtonSegment(value: CarBucket.missed, label: Text(l10n.commute_chip_missed)),
            ],
            selected: {_bucket},
            onSelectionChanged: (selection) => setState(() => _bucket = selection.first),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: _submit, child: Text(l10n.add)),
      ],
    );
  }
}
