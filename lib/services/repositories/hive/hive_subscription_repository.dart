import 'dart:math';

import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

/// Depot Hive des abonnements.
///
/// Nomme `Hive<X>Repository` et non `<X>Adapter` : le suffixe `Adapter` est
/// reserve aux `TypeAdapter` Hive (cf. `type_adapters.dart`), sans quoi les deux
/// classes entrent en collision de nom.
class HiveSubscriptionRepository implements ISubscriptions {
  final Box<Subscription> _box;
  final Random _random;

  HiveSubscriptionRepository(this._box, {Random? random}) : _random = random ?? Random();

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

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_random.nextInt(1 << 32).toRadixString(36)}';
}
