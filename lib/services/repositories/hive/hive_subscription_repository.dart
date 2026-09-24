import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

/// Depot Hive des abonnements.
///
/// Nomme `Hive<X>Repository` et non `<X>Adapter` : le suffixe `Adapter` est
/// reserve aux `TypeAdapter` Hive (cf. `type_adapters.dart`), sans quoi les deux
/// classes entrent en collision de nom.
///
/// Deux boites : les abonnements eux-memes, typees par leur `TypeAdapter`, et
/// une boite de chaines pour ce qui les entoure. Les categories ajoutees a la
/// main y sont rangees en JSON, sans nouveau `TypeAdapter` : un identifiant de
/// type Hive se brule a vie, et une liste de categories n'en vaut pas un.
class HiveSubscriptionRepository implements ISubscriptions {
  final Box<Subscription> _box;
  final Box<String> _prefs;
  final Random _random;

  HiveSubscriptionRepository(this._box, this._prefs, {Random? random})
      : _random = random ?? Random();

  static const String _categoriesKey = 'categories';

  @override
  Future<List<Subscription>> getAll() async => _box.values.toList(growable: false);

  @override
  Future<void> updateSubscription(Subscription subscription) async {
    // Un abonnement fraichement cree n'a pas encore d'identifiant. Sans cette
    // attribution, `put(null, ...)` est rejete par Hive et l'ajout echoue.
    subscription.id ??= _newId();
    await _box.put(subscription.id, subscription);
    // Meme raison que pour la configuration : une boite Hive sert ses valeurs
    // depuis un cache en memoire, et une ecriture qui n'atteint pas le disque
    // resterait invisible jusqu'au prochain demarrage.
    await _box.flush();
  }

  @override
  Future<void> delete(String id) async {
    await _box.delete(id);
    await _box.flush();
  }

  @override
  Future<List<SubscriptionCategory>> getCategories() async => [
        ...SubscriptionCategory.builtIn,
        ..._customCategories(),
      ];

  @override
  Future<void> saveCategory(SubscriptionCategory category) async {
    if (category.id.isEmpty || category.isBuiltIn) {
      return;
    }
    final custom = [
      for (final existing in _customCategories())
        if (existing.id != category.id) existing,
      category,
    ];
    await _prefs.put(_categoriesKey, json.encode([for (final c in custom) c.toJson()]));
    await _prefs.flush();
  }

  /// Une entree illisible est ignoree plutot que de faire echouer la lecture
  /// entiere : une categorie abimee ne doit pas vider l'onglet a l'ecran.
  List<SubscriptionCategory> _customCategories() {
    final raw = _prefs.get(_categoriesKey);
    if (raw == null) {
      return const [];
    }
    Object? decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) {
      return const [];
    }
    return [
      for (final item in decoded)
        if (item is Map<String, Object?>) SubscriptionCategory.fromJson(item),
    ].where((category) => category.id.isNotEmpty && !category.isBuiltIn).toList();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_random.nextInt(1 << 32).toRadixString(36)}';
}
