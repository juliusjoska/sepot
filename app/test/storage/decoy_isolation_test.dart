// Argon2id (64 MiB) ×6 pod zátěží celé sady: víc než výchozích 30 s.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/dek_wrap.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/identity.dart';

/// Nátlaková (decoy) relace musí být izolovaná od skutečného účtu:
/// jiná identita, žádná fráze, „smazat" nesáhne na skutečná data,
/// a zámek režim resetuje. Keystore je nahrazený mockem, DB jde do temp.
/// Potřebuje nativní libsignal (LocalIdentity) a sqlcipher.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late SecureStorageService storage;

  setUpAll(() async => SepotCrypto.init());

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sepot_decoy');
    storage = SecureStorageService(dbPath: '${tmp.path}/app.db');
    await storage.unlockWithoutPin();
    await storage.saveIdentity(await LocalIdentity.create('Alice'));
    await storage.saveSeedPhrase(List.filled(24, 'abandon'));
    await storage.enablePin('111111');
    await storage.enableDecoyPin('222222');
    storage.lock();
  });

  tearDown(() {
    storage.lock();
    tmp.deleteSync(recursive: true);
  });

  test('decoy PIN otevře izolovanou relaci', () async {
    await storage.unlockWithPin('222222');
    expect(storage.isDecoyMode, isTrue);
    expect(await storage.loadSeedPhrase(), isNull);
    final shown = await storage.loadIdentity();
    expect(shown, isNotNull);

    storage.lock();
    expect(storage.isDecoyMode, isFalse);
    await storage.unlockWithPin('111111');
    expect(storage.isDecoyMode, isFalse);
    final real = await storage.loadIdentity();
    expect(real!.id, isNot(shown!.id), reason: 'decoy ukazuje jinou identitu');
    expect(await storage.loadSeedPhrase(), hasLength(24));
  });

  test('smazání v decoy relaci nechá skutečná data', () async {
    await storage.unlockWithPin('222222');
    await storage.deleteAll();
    expect(File('${tmp.path}/app.db').existsSync(), isTrue);
    expect(await storage.hasIdentity(), isTrue);
    expect(await storage.hasPin(), isTrue);
    await storage.unlockWithPin('111111');
    expect(storage.isDecoyMode, isFalse);
  });

  test('změny keystore jsou v decoy relaci zakázané', () async {
    await storage.unlockWithPin('222222');
    expect(() => storage.enableBiometrics(), throwsStateError);
    expect(() => storage.disablePin(), throwsStateError);
    expect(
        () => storage.changePin(oldPin: '222222', newPin: '333333'),
        throwsStateError);
  });

  test('po pěti špatných PINech se zámek na čas zavře', () async {
    for (var i = 0; i < 5; i++) {
      await expectLater(storage.unlockWithPin('000000'),
          throwsA(isA<WrongPinException>()));
    }
    expect(await storage.pinLockRemaining(), isNotNull);
    await expectLater(storage.unlockWithPin('111111'),
        throwsA(isA<PinLockedException>()));
  });
}
