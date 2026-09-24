import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
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
/// Identifiants de type deja pris : 0 `Subscription`, 1 `SubscriptionFrequency`,
/// 2 `ServerConfig`. Un identifiant libere ne doit jamais etre reattribue.
///
/// Numeros de champ brules : `ServerConfig` 6, qui portait `defaultCategory` ;
/// `Subscription` 5, qui portait `iconCode`, le point de code d'une icone
/// saisi a la main.

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
      subscriptionType: fields[4] as SubscriptionFrequency? ?? SubscriptionFrequency.monthly,
      // Le champ 5 portait `iconCode`. Les enregistrements anterieurs le
      // contiennent encore : il est lu dans la map, puis ignore.
      categoryId: fields[6] as String?,
      nextPayment: fields[7] as DateTime?,
      iconId: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Subscription obj) {
    writer
      // Doit valoir exactement le nombre de paires ecrites ci-dessous. Une
      // erreur ici ne leve aucune exception : elle corrompt a la relecture.
      ..writeByte(8)
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
      ..writeByte(6)
      ..write(obj.categoryId)
      ..writeByte(7)
      ..write(obj.nextPayment)
      ..writeByte(8)
      ..write(obj.iconId);
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

class ServerConfigTypeAdapter extends TypeAdapter<ServerConfig> {
  @override
  final int typeId = 2;

  @override
  ServerConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return ServerConfig(
      host: fields[0] as String? ?? '',
      port: fields[1] as int? ?? 8080,
      useHttps: fields[2] as bool? ?? true,
      username: fields[3] as String? ?? '',
      pollIntervalSeconds: fields[4] as int? ?? 3,
      defaultSavePath: fields[5] as String?,
      // Le champ 6 portait `defaultCategory`. Les enregistrements anterieurs le
      // contiennent encore : il est lu dans la map, puis ignore. Le numero est
      // brule, ne jamais le reattribuer.
      pinnedCertSha256: fields[7] as String?,
      agentPort: fields[8] as int? ?? 8081,
    );
  }

  @override
  void write(BinaryWriter writer, ServerConfig obj) {
    writer
      // Doit valoir exactement le nombre de paires ecrites ci-dessous. Une
      // erreur ici ne leve aucune exception : elle corrompt a la relecture.
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.host)
      ..writeByte(1)
      ..write(obj.port)
      ..writeByte(2)
      ..write(obj.useHttps)
      ..writeByte(3)
      ..write(obj.username)
      ..writeByte(4)
      ..write(obj.pollIntervalSeconds)
      ..writeByte(5)
      ..write(obj.defaultSavePath)
      ..writeByte(7)
      ..write(obj.pinnedCertSha256)
      ..writeByte(8)
      ..write(obj.agentPort);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerConfigTypeAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
