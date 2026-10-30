import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/services/sync/storage_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('izerak/storage');
  const access = StorageAccess(channel: channel);
  late List<String> calls;

  void answer(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return handler(call);
    });
  }

  setUp(() => calls = []);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('sur Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('la permission est requise et se lit par le canal', () async {
      answer((_) => true);

      expect(access.isRequired, isTrue);
      expect(await access.isGranted(), isTrue);
      expect(calls, ['isGranted']);
    });

    test('un refus est rapporte tel quel', () async {
      answer((_) => false);

      expect(await access.isGranted(), isFalse);
    });

    test('un canal en erreur compte pour un refus', () async {
      answer((_) => throw PlatformException(code: 'boom'));

      expect(await access.isGranted(), isFalse);
    });

    test('un canal absent compte pour un refus, sans lever', () async {
      // Aucun gestionnaire : MissingPluginException.
      expect(await access.isGranted(), isFalse);
      await access.request();
    });

    test('la demande passe par le canal', () async {
      answer((_) => null);

      await access.request();

      expect(calls, ['request']);
    });
  });

  group('sur Windows', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);

    test('rien a demander, et le canal reste muet', () async {
      answer((_) => false);

      expect(access.isRequired, isFalse);
      expect(await access.isGranted(), isTrue);
      await access.request();
      expect(calls, isEmpty);
    });
  });
}
