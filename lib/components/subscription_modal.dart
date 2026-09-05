import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

class SubscriptionModal extends StatefulWidget {
  final Subscription? subscription;

  const SubscriptionModal({super.key, this.subscription});

  @override
  State<SubscriptionModal> createState() => _SubscriptionModalState();
}

class _SubscriptionModalState extends State<SubscriptionModal> {
  final ISubscriptions _subscriptions = getIt<ISubscriptions>();

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  late Subscription _subscription;

  bool get isEditing => widget.subscription != null;

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      _subscription = widget.subscription!;
      _nameController.text = _subscription.name;
      _priceController.text = _subscription.price.toString();
    } else {
      _subscription = Subscription();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    // IconData? value = await FlutterIconPicker.showIconPicker(context,
    //     iconSize: 50, iconPackModes: [], customIconPack: customIcons);

    // setState(() {
    //   _subscription.iconCode = value!.codePoint;
    // });
  }

  Future<void> _saveSubscription() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Le clavier francais produit une virgule decimale, que double.parse rejette.
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (price == null) {
      return;
    }

    _subscription.name = _nameController.text;
    _subscription.price = price;
    // La frequence est ecrite directement par le menu deroulant : plus de
    // recherche par nom, donc plus de StateError possible ici.

    await _subscriptions.updateSubscription(_subscription);

    if (!mounted) {
      return;
    }
    // La modale restait ouverte apres l'enregistrement, sans aucun retour.
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    // Un IconData construit dynamiquement empeche le tree-shaking des polices
    // d'icones : `flutter build apk` echouait sans --no-tree-shake-icons. Le
    // selecteur d'icone etant de toute facon desactive (_pickIcon est vide),
    // on affiche l'icone constante deja utilisee par SubscriptionCard.
    const bufferIcon = Icons.subscriptions;

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
                IconButton(onPressed: _pickIcon, icon: const Icon(bufferIcon)),
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
                      }
                      // double.parse levait une FormatException depuis le
                      // validateur lui-meme, donc pendant le rendu, des qu'on
                      // saisissait une virgule au clavier francais.
                      final parsed = double.tryParse(value.replaceAll(',', '.'));
                      if (parsed == null || parsed < 0) {
                        return AppLocalizations.of(context)!.please_enter_a_valid_price;
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                        suffixText: '€',
                        border: const OutlineInputBorder(),
                        labelText: AppLocalizations.of(context)!.price),
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  flex: 1,
                  // Le champ ecrivait la selection dans un controller tandis que
                  // sa valeur affichee restait celle du modele, jamais mise a
                  // jour : le menu revenait visuellement sur la frequence
                  // initiale a chaque choix. Il pilote desormais le modele.
                  child: DropdownButtonFormField<SubscriptionFrequency>(
                    decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: AppLocalizations.of(context)!.frequency),
                    validator: (value) => value == null
                        ? AppLocalizations.of(context)!.please_select_a_frequency
                        : null,
                    isExpanded: true,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _subscription.subscriptionType = value);
                    },
                    initialValue: _subscription.subscriptionType,
                    items: SubscriptionFrequency.values
                        .map<DropdownMenuItem<SubscriptionFrequency>>((e) {
                      return DropdownMenuItem<SubscriptionFrequency>(
                          value: e,
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
