import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/models/payback_dao.dart' show paybackSubscriptions;
import 'package:i_zerak_app/models/subscription_dao.dart' show Subscription, SubscriptionFrequency;
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/fuel_label.dart';
import 'package:i_zerak_app/pages/settings/widgets/settings_ui.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// La categorie « Trajet et velo » : distance, consommation et carburant,
/// puis les abonnements que le velo rembourse.
///
/// La cagnotte d'un trajet en voiture ne se regle pas ici : elle se decide a
/// chaque trajet, en repondant a « le velo etait-il possible ? ».
///
/// Rien de ce qui change ici ne touche aux journees deja enregistrees : leur
/// montant et leur cagnotte ont ete figes le jour meme.
class CommuteSection extends StatefulWidget {
  CommuteSection({
    super.key,
    ICommute? store,
    CommutePriceService? prices,
    ISubscriptions? subscriptions,
  })  : store = store ?? getIt<ICommute>(),
        prices = prices ?? getIt<CommutePriceService>(),
        subscriptions = subscriptions ??
            (getIt.isRegistered<ISubscriptions>() ? getIt<ISubscriptions>() : null);

  final ICommute store;
  final CommutePriceService prices;

  /// Sans elles, le choix des abonnements rembourses n'apparait pas.
  final ISubscriptions? subscriptions;

  @override
  State<CommuteSection> createState() => _CommuteSectionState();
}

class _CommuteSectionState extends State<CommuteSection> {
  final _formKey = GlobalKey<FormState>();
  final _distance = TextEditingController();
  final _consumption = TextEditingController();

  CommuteSettings _settings = const CommuteSettings();
  List<Subscription> _subscriptions = const [];

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
    final subscriptions = await widget.subscriptions?.getAll() ?? const <Subscription>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _subscriptions = paybackSubscriptions(subscriptions);
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
    // Relu avant d'ecrire : les abonnements coches entre-temps sont deja
    // enregistres, et ne doivent pas etre ecrases par la copie de l'ecran.
    final stored = await widget.store.readSettings();
    final next = stored.copyWith(
      distanceKm: parseDecimal(_distance.text),
      consumption: parseDecimal(_consumption.text),
      fuel: _settings.fuel,
    );
    await widget.store.saveSettings(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = next;
      _saving = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.settings_saved)));
  }

  /// Coche ou decoche un abonnement. Enregistre tout de suite, sans toucher
  /// aux champs du trajet en cours de saisie.
  Future<void> _togglePayback(String id, bool kept) async {
    final stored = await widget.store.readSettings();
    final excluded = {...stored.paybackExcluded};
    kept ? excluded.remove(id) : excluded.add(id);
    await widget.store.saveSettings(stored.copyWith(paybackExcluded: excluded));
    if (mounted) {
      setState(() => _settings = _settings.copyWith(paybackExcluded: excluded));
    }
  }

  String? _positive(String? value) {
    final number = parseDecimal(value ?? '');
    return number == null || number <= 0 ? AppLocalizations.of(context)!.commute_invalid_number : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const SettingsLoading();
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSubtitle(l10n.commute_section_trip, first: true),
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
          SettingsSubtitle(l10n.commute_section_price),
          _priceRules(context, l10n),
          const SizedBox(height: 16),
          _tripValue(context, l10n),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.save),
          ),
          if (_subscriptions.isNotEmpty) ..._payback(context, l10n),
        ],
      ),
    );
  }

  /// Les abonnements que le velo rembourse, coches par defaut.
  List<Widget> _payback(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final format = CommuteFormat(context);
    return [
      SettingsSubtitle(l10n.payback_choose),
      Text(
        l10n.payback_choose_hint,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      for (final subscription in _subscriptions)
        if (subscription.id case final String id)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: !_settings.paybackExcluded.contains(id),
            title: Text(subscription.name),
            subtitle: Text(l10n.payback_per_month(
                format.euros(roundCents(subscription.amountIn(SubscriptionFrequency.monthly))))),
            onChanged: (kept) => _togglePayback(id, kept ?? false),
          ),
    ];
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
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
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
