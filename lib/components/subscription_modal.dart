import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconpicker/flutter_iconpicker.dart';
import 'package:i_zerak_app/dao/subscription_dao.dart';

class SubscriptionModal extends StatefulWidget {
  final SubscriptionDao? subscription;
  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController subscriptionTypeController;

  SubscriptionModal({Key? key, this.subscription})
      : nameController = TextEditingController(text: subscription?.name),
        priceController = TextEditingController(text: subscription?.price.toString()),
        subscriptionTypeController =
            TextEditingController(text: subscription?.subscriptionType.name),
        super(key: key);

  @override
  State<SubscriptionModal> createState() => _SubscriptionModalState();
}

class _SubscriptionModalState extends State<SubscriptionModal> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();

  _pickIcon() async {
    IconData? value =
        await FlutterIconPicker.showIconPicker(context, iconPackModes: [IconPack.material]);

    setState(() {
      widget.subscription?.iconCode = value!.codePoint;
    });
  }

  _saveSubscription() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    var element = {
      "name": widget.nameController.text,
      "price": double.parse(widget.priceController.text),
      "isActive": widget.subscription?.isActive ?? SubscriptionDao.defaultIsActive,
      "subscriptionType": widget.subscriptionTypeController.value.text,
      "iconCode": widget.subscription?.iconCode
    };
    if (widget.subscription != null) {
      db
          .doc("/subscriptions/${widget.subscription?.id}")
          .update(element)
          .then((value) => Navigator.pop(context));
    } else {
      db.collection("/subscriptions").add(element).then((value) => Navigator.pop(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    IconData? bufferIcon = IconData(
        widget.subscription?.iconCode ?? SubscriptionDao.defaultIconCode,
        fontFamily: 'MaterialIcons');

    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Text(
                (widget.subscription?.id != null)
                    ? 'Edit the subscription'
                    : 'Add a new subscription',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 16.0),
          Row(
            children: [
              IconButton(onPressed: _pickIcon, icon: Icon(bufferIcon)),
              const SizedBox(width: 16.0),
              Expanded(
                child: TextFormField(
                  controller: widget.nameController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                  decoration:
                      const InputDecoration(border: OutlineInputBorder(), labelText: 'Name'),
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
                  controller: widget.priceController,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a price';
                    } else if (double.parse(value) < 0) {
                      return 'Please enter a positive price';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                      suffixText: "€", border: OutlineInputBorder(), labelText: 'Price'),
                ),
              ),
              const SizedBox(width: 16.0),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  //FIXME: DropdownButtonFormField is deprecated
                  //FIXME: initialValue is not set up
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select a subscription type';
                    } else {
                      return null;
                    }
                  },
                  isExpanded: true,
                  onChanged: (value) => {
                    setState(() {
                      widget.subscriptionTypeController.text = value!;
                    })
                  },
                  items: SubscriptionType.values.map<DropdownMenuItem<String>>((e) {
                    return DropdownMenuItem<String>(value: e.name, child: Text(e.name));
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
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("Cancel"),
                  )),
              ElevatedButton(
                  onPressed: _saveSubscription,
                  child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text((widget.subscription != null) ? 'Save' : 'Add'))),
            ],
          ),
        ]),
      ),
    );
  }
}
