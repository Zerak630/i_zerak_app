import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/fuel_label.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// Reglages du trajet domicile-travail : distance, consommation et carburant.
///
/// La cagnotte d'un trajet en voiture ne se regle plus ici : elle se decide a
/// chaque trajet, en repondant a « le velo etait-il possible ? ».
///
/// Rien de ce qui change ici ne touche aux journees deja enregistrees : leur
/// montant et leur cagnotte ont ete figes le jour meme.
class CommuteSettingsPage extends StatefulWidget {
  CommuteSettingsPage({super.key, ICommute? store, CommutePriceService? prices})
      : store = store ?? getIt<ICommute>(),
        prices = prices ?? getIt<CommutePriceService>();

  final ICommute store;
  final CommutePriceService prices;

  @override
  State<CommuteSettingsPage> createState() => _CommuteSettingsPageState();
}

class _CommuteSettingsPageState extends State<CommuteSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _distance = TextEditingController();
  final _consumption = TextEditingController();

  CommuteSettings _settings = const CommuteSettings();

  ResolvedPrice? _price;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _distance.addListener(_preview);
    _consumption.addListener(_preview);
    _load();
  }

  @override
  void dispose() {
    _distance.dispose();
    _consumption.dispose();
    super.dispose();
  }

  void _preview() => setState(() {});

  Future<void> _load() async {
    final settings = await widget.store.readSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _distance.text = settings.distanceKm == null ? '' : _plain(settings.distanceKm!);
      _consumption.text = _plain(settings.consumption);
      _loading = false;
    });
    await _resolvePrice();
  }

  /// Sans separateur de milliers : la valeur repart telle quelle dans le champ.
  String _plain(double value) {
    final text = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return Localizations.localeOf(context).languageCode == 'fr' ? text.replaceAll('.', ',') : text;
  }

  Future<void> _resolvePrice() async {
    final price = await widget.prices.resolve(_settings.fuel);
    if (mounted) {
      setState(() => _price = price);
    }
  }

  Future<void> _selectFuel(FuelType fuel) async {
    setState(() {
      _settings = _settings.copyWith(fuel: fuel);
      _price = null;
    });
    await _resolvePrice();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    await widget.store.saveSettings(_settings.copyWith(
      distanceKm: parseDecimal(_distance.text),
      consumption: parseDecimal(_consumption.text),
    ));
    if (mounted) {
      Navigator.pop(context);
    }
  }

  String? _positive(String? value) {
    final number = parseDecimal(value ?? '');
    return number == null || number <= 0 ? AppLocalizations.of(context)!.commute_invalid_number : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.commute_settings_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _SectionTitle(l10n.commute_section_trip),
                  TextFormField(
                    controller: _distance,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.commute_distance,
                      helperText: l10n.commute_distance_help,
                      suffixText: 'km',
                      border: const OutlineInputBorder(),
                    ),
                    validator: _positive,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _consumption,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.commute_consumption,
                      helperText: l10n.commute_consumption_help,
                      suffixText: 'L/100 km',
                      border: const OutlineInputBorder(),
                    ),
                    validator: _positive,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<FuelType>(
                    initialValue: _settings.fuel,
                    decoration: InputDecoration(
                      labelText: l10n.commute_fuel,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final fuel in FuelType.values)
                        DropdownMenuItem(value: fuel, child: Text(fuelLabel(l10n, fuel))),
                    ],
                    onChanged: (fuel) {
                      if (fuel != null) {
                        _selectFuel(fuel);
                      }
                    },
                  ),
                  _SectionTitle(l10n.commute_section_price),
                  _priceRules(context, l10n),
                  const SizedBox(height: 24),
                  _tripValue(context, l10n),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.save),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _priceRules(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final small = theme.textTheme.bodySmall;

    Widget rule(String label, String value) => Padding(
          padding: const EdgeInsets.only(left: 32, top: 8),
          child: Row(children: [
            Expanded(child: Text(label, style: small?.copyWith(color: scheme.onSurfaceVariant))),
            Text(value, style: small),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.local_gas_station, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.commute_price_rule, style: theme.textTheme.bodyMedium)),
        ]),
        rule(l10n.commute_price_unreachable_rule, l10n.commute_price_unreachable_value),
        rule(l10n.commute_price_never_rule, format.perLitre(kFallbackFuelPrice)),
      ]),
    );
  }

  Widget _tripValue(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final distance = parseDecimal(_distance.text);
    final consumption = parseDecimal(_consumption.text);
    final price = _price;
    if (distance == null || consumption == null || distance <= 0 || price == null) {
      return const SizedBox.shrink();
    }
    final value = CommuteSettings(distanceKm: distance, consumption: consumption)
        .tripValue(price.pricePerLitre);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.commute_trip_value_today,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
        const SizedBox(height: 4),
        Text(format.euros(value),
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
        const SizedBox(height: 4),
        Text(
          l10n.commute_trip_formula(
            format.number(distance),
            format.number(consumption),
            format.perLitre(price.pricePerLitre),
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          letterSpacing: 0.9,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
