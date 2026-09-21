import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/timeline_import.dart';

/// Hors du fil de l'interface : l'export pese facilement plusieurs dizaines de
/// mega-octets, et le decoder sur place figerait l'ecran une seconde ou deux.
List<TimelineBikeDay> _parseBytes(Uint8List bytes) =>
    parseTimelineBikeDays(utf8.decode(bytes, allowMalformed: true));

/// Choisit un export de la Chronologie et en extrait les journees a velo.
///
/// Renvoie `null` si l'utilisateur renonce ; leve `TimelineFormatException`
/// si le fichier n'est pas un export reconnu.
Future<List<TimelineBikeDay>?> pickTimelineBikeDays() async {
  // Aucun filtre de type : le selecteur Android ne connait pas toujours le
  // type MIME du JSON, et griserait alors le fichier. Le contenu est de toute
  // facon verifie a la lecture.
  final file = await openFile();
  if (file == null) {
    return null;
  }
  return compute(_parseBytes, await file.readAsBytes());
}

/// Apercu de l'import : quels jours reprendre, avant d'ecrire quoi que ce soit.
///
/// Les trajets domicile-travail reconnus par Google sont coches d'office ; les
/// autres sorties a velo en semaine sont proposees decochees, pour rattraper
/// un jour ou Google n'a pas reconnu le lieu de travail. Les week-ends sont
/// ecartes, et un jour deja enregistre n'est jamais remplace.
class CommuteImportPage extends StatefulWidget {
  const CommuteImportPage({
    super.key,
    required this.found,
    required this.store,
    required this.prices,
    required this.clock,
  });

  final List<TimelineBikeDay> found;
  final ICommute store;
  final CommutePriceService prices;
  final DateTime Function() clock;

  @override
  State<CommuteImportPage> createState() => _CommuteImportPageState();
}

class _CommuteImportPageState extends State<CommuteImportPage> {
  CommuteSettings _settings = const CommuteSettings();
  Set<DateTime> _recorded = const {};
  ResolvedPrice? _price;
  final Set<DateTime> _selected = {};
  bool _loading = true;
  bool _importing = false;

  late final DateTime _today = dateOnly(widget.clock());

  List<TimelineBikeDay> get _commutes => [
        for (final day in widget.found)
          if (day.commute && !day.date.isAfter(_today)) day,
      ];

  List<TimelineBikeDay> get _others => [
        for (final day in widget.found)
          if (!day.commute && day.date.weekday <= DateTime.friday && !day.date.isAfter(_today)) day,
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.store.readSettings();
    final days = await widget.store.getDays();
    // Le prix d'aujourd'hui pour tous les jours importes : l'API ne publie pas
    // les prix passes, et l'application n'en a pas encore releve.
    final price = await widget.prices.resolve(settings.fuel);
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _recorded = {for (final day in days) day.date};
      _price = price;
      _selected.addAll([
        for (final day in _commutes)
          if (!_recorded.contains(day.date)) day.date,
      ]);
      _loading = false;
    });
  }

  Future<void> _import() async {
    final price = _price;
    if (price == null || _selected.isEmpty) {
      return;
    }
    setState(() => _importing = true);
    for (final date in _selected) {
      // Deuxieme garde : un jour enregistre entre-temps n'est pas ecrase.
      if (_recorded.contains(date)) {
        continue;
      }
      await widget.store.saveDay(CommuteDay.bike(date, _settings, price, imported: true));
    }
    if (mounted) {
      Navigator.pop(context, _selected.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.commute_import_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final trip = _price == null ? 0.0 : _settings.tripValue(_price!.pricePerLitre);
    final canImport = _settings.isConfigured && _selected.isNotEmpty && !_importing;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.commute_import_title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(l10n.commute_import_privacy,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
          if (!_settings.isConfigured) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(l10n.commute_import_needs_setup,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
            ),
          ],
          _section(context, l10n.commute_import_commutes, l10n.commute_import_commutes_hint, _commutes),
          if (_others.isNotEmpty)
            _section(context, l10n.commute_import_others, l10n.commute_import_others_hint, _others),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_settings.isConfigured && _selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.commute_import_value(
                    format.euros(roundCents(trip * _selected.length)),
                    format.euros(trip),
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            FilledButton(
              onPressed: canImport ? _import : null,
              child: Text(l10n.commute_import_action(_selected.length)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    String hint,
    List<TimelineBikeDay> days,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 20),
      Text('$title · ${days.length}', style: theme.textTheme.titleSmall),
      Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
      const SizedBox(height: 4),
      for (final day in days)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _recorded.contains(day.date) ? false : _selected.contains(day.date),
          onChanged: _recorded.contains(day.date)
              ? null
              : (checked) => setState(() {
                    if (checked ?? false) {
                      _selected.add(day.date);
                    } else {
                      _selected.remove(day.date);
                    }
                  }),
          title: Text(format.shortDayWithYear(day.date)),
          subtitle: Text(_recorded.contains(day.date)
              ? l10n.commute_import_already
              : l10n.commute_import_detail(
                  format.number(day.km),
                  day.commute && day.legs == 2
                      ? l10n.commute_import_round_trip
                      : l10n.commute_import_legs(day.legs),
                )),
        ),
    ]);
  }
}
