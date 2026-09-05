import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';

/// `TypeAdapter` Hive ecrits a la main.
///
/// Ils remplacent le code qu'aurait produit `hive_generator`. Ecrits ainsi,
/// le projet compile sans passer par `build_runner`, et les identifiants de
/// type restent visibles au meme endroit.
///
/// Contrepartie a connaitre : **tout champ ajoute a un modele doit etre
/// repercute ici a la main**. Les regles Hive restent les memes qu'avec le
/// generateur :
///   - ne jamais reutiliser ni renumeroter un `HiveField` existant ;
///   - un champ supprime laisse son numero definitivement brule ;
///   - un champ absent d'un enregistrement ancien est relu a `null`, d'ou les
///     valeurs de repli ci-dessous.
///
/// Identifiants de type deja pris : 0 `Subscription`, 1 `SubscriptionFrequency`.

class SubscriptionTypeAdapter extends TypeAdapter<Subscription> {
  @override
  final int typeId = 0;

  @override
  Subscription read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return Subscription(
      id: fields[0] as String?,
      name: fields[1] as String? ?? '',
      price: (fields[2] as num?)?.toDouble() ?? 0.0,
      isActive: fields[3] as bool? ?? true,
      subscriptionType: fields[4] as SubscriptionFrequency? ?? SubscriptionFrequency.weekly,
      iconCode: fields[5] as int? ?? Subscription.defaultIconCode,
    );
  }

  @override
  void write(BinaryWriter writer, Subscription obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.isActive)
      ..writeByte(4)
      ..write(obj.subscriptionType)
      ..writeByte(5)
      ..write(obj.iconCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionTypeAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}

class SubscriptionFrequencyTypeAdapter extends TypeAdapter<SubscriptionFrequency> {
  @override
  final int typeId = 1;

  @override
  SubscriptionFrequency read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SubscriptionFrequency.weekly;
      case 1:
        return SubscriptionFrequency.monthly;
      case 2:
        return SubscriptionFrequency.yearly;
      default:
        return SubscriptionFrequency.weekly;
    }
  }

  @override
  void write(BinaryWriter writer, SubscriptionFrequency obj) {
    switch (obj) {
      case SubscriptionFrequency.weekly:
        writer.writeByte(0);
        break;
      case SubscriptionFrequency.monthly:
        writer.writeByte(1);
        break;
      case SubscriptionFrequency.yearly:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionFrequencyTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
