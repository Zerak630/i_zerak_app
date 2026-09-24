import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/icon_picker_sheet.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

enum SubscriptionSheetResult { saved, deleted }

/// La feuille qui cree, modifie et supprime un abonnement.
///
/// Une seule, la ou coexistaient une modale de creation et un ecran de detail
/// qui ne demandaient pas les memes champs : les deux validations divergeaient,
/// et seule la seconde permettait de suspendre un abonnement.
Future<SubscriptionSheetResult?> showSubscriptionSheet(
  BuildContext context, {
  Subscription? subscription,
  required ISubscriptions store,
  required List<SubscriptionCategory> categories,
  DateTime Function()? clock,
}) =>
    showModalBottomSheet<SubscriptionSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SubscriptionSheet(
        subscription: subscription,
        store: store,
        categories: categories,
        clock: clock ?? DateTime.now,
      ),
    );

class _SubscriptionSheet extends StatefulWidget {
  const _SubscriptionSheet({
    required this.subscription,
    required this.store,
    required this.categories,
    required this.clock,
  });

  final Subscription? subscription;
  final ISubscriptions store;
  final List<SubscriptionCategory> categories;
  final DateTime Function() clock;

  @override
  State<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<_SubscriptionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;

  late List<SubscriptionCategory> _categories = [...widget.categories];
  late SubscriptionFrequency _frequency;
  late String? _categoryId;
  late DateTime? _nextPayment;
  late String? _iconId;
  late bool _isActive;
  bool _saving = false;

  bool get _isEditing => widget.subscription?.id != null;

  @override
  void initState() {
    super.initState();
    final subscription = widget.subscription;
    _name = TextEditingController(text: subscription?.name ?? '');
    // Un prix a zero ne s'affiche pas : le champ d'un nouvel abonnement doit
    // etre vide, sans quoi il faut effacer « 0.0 » avant de saisir.
    _price = TextEditingController(
      text: subscription == null || subscription.price == 0
          ? ''
          : subscription.price.toStringAsFixed(2),
    );
    _frequency = subscription?.subscriptionType ?? SubscriptionFrequency.monthly;
    _categoryId = subscription?.categoryId;
    _nextPayment = subscription?.nextPayment;
    _iconId = subscription?.iconId;
    _isActive = subscription?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Color get _tint => subscriptionColor(context, _categoryId, _categories);

  Future<void> _pickIcon() async {
    final chosen = await showIconPicker(context, selected: _iconId, tint: _tint);
    if (chosen != null && mounted) {
      setState(() => _iconId = chosen);
    }
  }

  Future<void> _pickDate() async {
    final today = dateOnly(widget.clock());
    final chosen = await showDatePicker(
      context: context,
      initialDate: _nextPayment ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (chosen != null && mounted) {
      setState(() => _nextPayment = dateOnly(chosen));
    }
  }

  Future<void> _addCategory() async {
    final created = await showAddCategoryDialog(context);
    if (created == null) {
      return;
    }
    await widget.store.saveCategory(created);
    if (mounted) {
      setState(() {
        _categories = [..._categories, created];
        _categoryId = created.id;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) {
      return;
    }
    setState(() => _saving = true);
    final subscription = widget.subscription ?? Subscription();
    subscription
      ..name = _name.text.trim()
      ..price = parseAmount(_price.text) ?? subscription.price
      ..subscriptionType = _frequency
      ..categoryId = _categoryId
      ..nextPayment = _nextPayment
      ..iconId = _iconId
      ..isActive = _isActive;
    await widget.store.updateSubscription(subscription);
    if (mounted) {
      Navigator.pop(context, SubscriptionSheetResult.saved);
    }
  }

  Future<void> _delete() async {
    final id = widget.subscription?.id;
    if (id == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.delete_confirm(_name.text.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.store.delete(id);
    if (mounted) {
      Navigator.pop(context, SubscriptionSheetResult.deleted);
    }
  }

  /// « puis chaque mardi », pour que la date saisie se lise comme une regle et
  /// non comme un evenement isole.
  String? _repeatHint(AppLocalizations l10n, SubscriptionFormat format) {
    final date = _nextPayment;
    if (date == null) {
      return null;
    }
    return switch (_frequency) {
      SubscriptionFrequency.weekly => l10n.sub_repeat_week(format.weekday(date)),
      SubscriptionFrequency.monthly => l10n.sub_repeat_month(date.day),
      SubscriptionFrequency.yearly => l10n.sub_repeat_year(format.shortDay(date)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final date = _nextPayment;

    return SubscriptionSheet(children: [
      Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                _isEditing ? l10n.edit_subscription : l10n.add_subscription,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (_isEditing)
              IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                color: scheme.error,
                tooltip: l10n.delete,
              ),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Tooltip(
              message: l10n.sub_change_icon,
              child: InkWell(
                onTap: _pickIcon,
                borderRadius: BorderRadius.circular(16),
                child: Stack(clipBehavior: Clip.none, children: [
                  SubscriptionAvatar(iconId: _iconId, color: _tint, size: 56),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                      ),
                      child: Icon(Icons.edit, size: 11, color: scheme.onPrimaryContainer),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _name,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.name,
                  hintText: l10n.name_placeholder,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? l10n.please_enter_a_name : null,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.price,
                  hintText: l10n.price_placeholder,
                  suffixText: '€',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.please_enter_a_price;
                  }
                  final amount = parseAmount(value);
                  // Un prix nul ou negatif ne serait compte nulle part : mieux
                  // vaut le refuser que de laisser une ligne muette au total.
                  if (amount == null || amount <= 0) {
                    return l10n.please_enter_a_valid_price;
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<SubscriptionFrequency>(
                initialValue: _frequency,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.frequency,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final frequency in SubscriptionFrequency.values)
                    DropdownMenuItem(
                      value: frequency,
                      child: Text(frequencyLabel(l10n, frequency)),
                    ),
                ],
                onChanged: (value) => setState(() => _frequency = value ?? _frequency),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.sub_next_payment,
                helperText: _repeatHint(l10n, format),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.event_outlined),
                suffixIcon: date == null
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => _nextPayment = null),
                        icon: const Icon(Icons.close),
                        tooltip: l10n.sub_clear_date,
                      ),
              ),
              child: Text(
                date == null ? l10n.sub_no_date : format.fullDate(date),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: date == null ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(l10n.sub_category, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final category in _categories)
              FilterChip(
                selected: category.id == _categoryId,
                onSelected: (selected) =>
                    setState(() => _categoryId = selected ? category.id : null),
                avatar: CircleAvatar(
                  radius: 5,
                  backgroundColor: categoryColor(context, category.color),
                ),
                label: Text(categoryLabel(l10n, category)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(l10n.sub_new_category),
              onPressed: _addCategory,
            ),
          ]),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
            title: Text(_isActive ? l10n.active : l10n.inactive),
            subtitle: Text(_isActive ? l10n.sub_active_hint : l10n.sub_inactive_hint),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_isEditing ? l10n.save : l10n.add),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}
