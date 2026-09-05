import 'package:flutter/material.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';

class SubscriptionDetailPage extends StatefulWidget {
  final Subscription subscription;

  const SubscriptionDetailPage({super.key, required this.subscription});

  @override
  State<SubscriptionDetailPage> createState() => _SubscriptionDetailPageState();
}

class _SubscriptionDetailPageState extends State<SubscriptionDetailPage> {
  final ISubscriptions _subscriptions = getIt<ISubscriptions>();
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _logoController;
  late String _subscriptionType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.subscription.name);
    _priceController = TextEditingController(text: widget.subscription.price.toString());
    _logoController = TextEditingController(text: widget.subscription.iconCode.toString());
    _subscriptionType = widget.subscription.subscriptionType.name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  Future<void> _saveSubscription() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    widget.subscription.name = _nameController.text;
    widget.subscription.price =
        double.tryParse(_priceController.text.replaceAll(',', '.')) ?? widget.subscription.price;
    widget.subscription.iconCode =
        int.tryParse(_logoController.text) ?? widget.subscription.iconCode;
    widget.subscription.subscriptionType = SubscriptionFrequency.values.firstWhere(
      (e) => e.name == _subscriptionType,
      orElse: () => widget.subscription.subscriptionType,
    );

    // Passait par SubscriptionService.updateSubscription, dont le corps etait
    // vide : l'ecran se fermait sans que rien ne soit enregistre.
    await _subscriptions.updateSubscription(widget.subscription);

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _deleteSubscription() async {
    final id = widget.subscription.id;
    if (id == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.delete),
        content: Text(AppLocalizations.of(context)!.delete_confirm(widget.subscription.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)!.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await _subscriptions.delete(id);

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.edit_subscription),
        actions: [
          IconButton(
            onPressed: widget.subscription.id == null ? null : _deleteSubscription,
            icon: const Icon(Icons.delete_outline),
            tooltip: AppLocalizations.of(context)!.delete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.name,
                  hintText: AppLocalizations.of(context)!.name_placeholder,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.please_enter_a_name;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8.0),
              TextFormField(
                controller: _priceController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.price,
                  hintText: AppLocalizations.of(context)!.price_placeholder,
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.please_enter_a_price;
                  }
                  final price = double.tryParse(value);
                  if (price == null || price <= 0) {
                    return AppLocalizations.of(context)!.please_enter_a_valid_price;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8.0),
              TextFormField(
                controller: _logoController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.logo_code,
                  hintText: '983915',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.please_enter_a_logo_code;
                  }
                  final logoCode = int.tryParse(value);
                  if (logoCode == null) {
                    return AppLocalizations.of(context)!.please_enter_a_valid_integer;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8.0),
              DropdownButtonFormField<String>(
                initialValue: _subscriptionType,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.frequency,
                ),
                items: SubscriptionFrequency.values.map((frequency) {
                  return DropdownMenuItem<String>(
                    value: frequency.name,
                    // Affichait la valeur brute de l'enum (« monthly »), non
                    // traduite, alors que la modale utilisait deja le libelle
                    // localise.
                    child: Text(SubscriptionFrequency.getLocaleAdjective(context, frequency)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _subscriptionType = value!;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.please_select_a_frequency;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8.0),
              // isActive etait lu par le calcul des totaux mais aucun ecran ne
              // permettait de le modifier.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.subscription.isActive
                    ? AppLocalizations.of(context)!.active
                    : AppLocalizations.of(context)!.inactive),
                value: widget.subscription.isActive,
                onChanged: (value) => setState(() => widget.subscription.isActive = value),
              ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: _saveSubscription,
                child: Text(AppLocalizations.of(context)!.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
