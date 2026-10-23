// Potřebuje nativní sqlcipher a Argon2id — na builderu se vynechává (--exclude-tags ffi).
@Tags(['ffi'])
// Argon2id (64 MiB) ~2 s na pokus, test jich dělá přes deset.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/storage/secure_storage.dart';

/// Opětovné ověření PINu v odemčené appce (fráze, záloha, smazání účtu):
/// stejná brzda jako zámek, nátlakový PIN ani nátlaková relace nic neodemknou.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late SecureStorageService storage;

  setUpAll(() async => SepotCrypto.init());

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sepot_verify_pin');
    storage = SecureStorageService(dbPath: '${tmp.path}/app.db');
    await storage.unlockWithoutPin();
    await storage.enablePin('111111');
    await storage.enableDecoyPin('222222');
  });

  tearDown(() {
    storage.lock();
    tmp.deleteSync(recursive: true);
  });

  test('skutečný PIN projde, nátlakový ne', () async {
    expect(await storage.verifyPin('111111'), isTrue);
    expect(await storage.verifyPin('222222'), isFalse);
  });

  test('v nátlakové relaci neprojde ani skutečný PIN', () async {
    storage.lock();
    await storage.unlockWithPin('222222');
    expect(storage.isDecoyMode, isTrue);
    expect(await storage.verifyPin('111111'), isFalse);
    expect(await storage.loadSeedPhrase(), isNull);
  });

  test('po pěti chybách zámek, hádání se nedá obejít', () async {
    for (var i = 0; i < 5; i++) {
      expect(await storage.verifyPin('99999$i'), isFalse);
    }
    expect(await storage.pinLockRemaining(), isNotNull);
    expect(() => storage.verifyPin('111111'),
        throwsA(isA<PinLockedException>()),
        reason: 'ani správný PIN během zámku');
  });

  test('správný PIN vynuluje počítadlo chyb', () async {
    for (var i = 0; i < 4; i++) {
      await storage.verifyPin('99999$i');
    }
    expect(await storage.verifyPin('111111'), isTrue);
    expect(await storage.verifyPin('999990'), isFalse);
    expect(await storage.pinLockRemaining(), isNull);
  });
}
