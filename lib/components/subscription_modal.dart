import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';

class SubscriptionModal extends StatefulWidget {
  final Subscription? subscription;

  const SubscriptionModal({super.key, this.subscription});

  @override
  State<SubscriptionModal> createState() => _SubscriptionModalState();
}

class _SubscriptionModalState extends State<SubscriptionModal> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _subscriptionTypeController = TextEditingController();

  late Subscription _subscription;

  bool get isEditing => widget.subscription != null;

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      _subscription = widget.subscription!;
      _nameController.text = _subscription.name;
      _priceController.text = _subscription.price.toString();
      _subscriptionTypeController.text = _subscription.subscriptionType.name;
    } else {
      _subscription = Subscription();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _subscriptionTypeController.dispose();
    super.dispose();
  }

  _pickIcon() async {
    // IconData? value = await FlutterIconPicker.showIconPicker(context,
    //     iconSize: 50, iconPackModes: [], customIconPack: customIcons);

    // setState(() {
    //   _subscription.iconCode = value!.codePoint;
    // });
  }

  _saveSubscription() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    _subscription.name = _nameController.text;
    _subscription.price = double.parse(_priceController.text);
    _subscription.subscriptionType = SubscriptionFrequency.values
        .firstWhere((element) => element.name == _subscriptionTypeController.text);

    var box = Hive.box<Subscription>('subscriptions');
    await box.put(_subscription.id, _subscription);
  }

  @override
  Widget build(BuildContext context) {
    IconData? bufferIcon = IconData(_subscription.iconCode, fontFamily: 'MaterialIcons');

    return Wrap(children: [
      Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              (widget.subscription?.id != null)
                  ? AppLocalizations.of(context)!.edit_subscription
                  : AppLocalizations.of(context)!.add_subscription,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                IconButton(onPressed: _pickIcon, icon: Icon(bufferIcon)),
                const SizedBox(width: 16.0),
                Expanded(
                  child: TextFormField(
                    controller: _nameController,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.of(context)!.please_enter_a_name;
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: AppLocalizations.of(context)!.name),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.of(context)!.please_enter_a_price;
                      } else if (double.parse(value) < 0) {
                        return AppLocalizations.of(context)!.please_enter_a_valid_price;
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                        suffixText: "€",
                        border: const OutlineInputBorder(),
                        labelText: AppLocalizations.of(context)!.price),
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    //FIXME: DropdownButtonFormField is deprecated
                    decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: AppLocalizations.of(context)!.frequency),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.of(context)!.please_select_a_frequency;
                      } else {
                        return null;
                      }
                    },
                    isExpanded: true,
                    onChanged: (value) => {
                      setState(() {
                        _subscriptionTypeController.text = value!;
                      })
                    },
                    value: _subscription.subscriptionType.name,
                    items: SubscriptionFrequency.values.map<DropdownMenuItem<String>>((e) {
                      return DropdownMenuItem<String>(
                          value: e.name,
                          child: Text(SubscriptionFrequency.getLocaleAdjective(context, e)));
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    )),
                ElevatedButton(
                    onPressed: _saveSubscription,
                    child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text((isEditing)
                            ? AppLocalizations.of(context)!.save
                            : AppLocalizations.of(context)!.add))),
              ],
            ),
          ]),
        ),
      )
    ]);
  }
}
