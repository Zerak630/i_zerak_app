import 'package:flutter/material.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/subscriptions_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SubscriptionDetailPage extends StatefulWidget {
  final Subscription subscription;

  const SubscriptionDetailPage({super.key, required this.subscription});

  @override
  _SubscriptionDetailPageState createState() => _SubscriptionDetailPageState();
}

class _SubscriptionDetailPageState extends State<SubscriptionDetailPage> {
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

  void _saveSubscription() {
    if (_formKey.currentState!.validate()) {
      // Update the subscription object
      widget.subscription.name = _nameController.text;
      widget.subscription.price = double.parse(_priceController.text);
      widget.subscription.iconCode = int.parse(_logoController.text);
      widget.subscription.subscriptionType =
          SubscriptionFrequency.values.firstWhere((e) => e.name == _subscriptionType);

      // Save the subscription using the service
      SubscriptionService().updateSubscription(widget.subscription);

      // Navigate back
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.edit_subscription),
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
                  labelText: 'Logo Code',
                  hintText: '123',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a logo code';
                  }
                  final logoCode = int.tryParse(value);
                  if (logoCode == null) {
                    return 'Please enter a valid integer';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8.0),
              DropdownButtonFormField<String>(
                value: _subscriptionType,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.frequency,
                ),
                items: SubscriptionFrequency.values.map((frequency) {
                  return DropdownMenuItem<String>(
                    value: frequency.name,
                    child: Text(frequency.name),
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
