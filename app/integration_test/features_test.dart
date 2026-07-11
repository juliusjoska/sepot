// Integrační testy na REÁLNÉM Android runtime (skutečný keychain +
// SQLCipher, ne mocky). Ověřují běh funkcí, které nejde otestovat v čistém
// Dart VM. Spouštět na zařízení/emulátoru:
//   flutter test integration_test/features_test.dart -d emulator-5554
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sepot/core/backup/backup_service.dart';
import 'package:sepot/core/crypto/dek_wrap.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/message.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const keystore = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  setUpAll(() async {
    await SepotCrypto.init(); // libsignal (RustLib) — jinak LocalIdentity.create padá
  });

  setUp(() async {
    await keystore.deleteAll();
  });

  testWidgets('DECOY PIN: skutečný PIN → reálná data, decoy PIN → prázdná DB '
      '(oddělené šifrované databáze)', (tester) async {
    final dir = await getApplicationSupportDirectory();
    final s = SecureStorageService(dbPath: '${dir.path}/it_decoy_${DateTime.now().millisecondsSinceEpoch}.db');

    // Reálný prostor: odemkni + zapiš marker
    await s.unlockWithoutPin();
    await s.setSetting('marker', 'REAL');
    await s.enablePin('111111');
    await s.enableDecoyPin('222222');
    expect(await s.hasDecoyPin(), isTrue);

    // Odemčení decoy PINem → prázdná decoy DB
    s.lock();
    await s.unlockWithPin('222222');
    expect(s.isDecoyMode, isTrue, reason: 'decoy PIN má otevřít decoy DB');
    expect(await s.getSetting<String>('marker'), isNull,
        reason: 'decoy DB nesmí vidět reálná data');
    await s.setSetting('marker', 'DECOY');

    // Odemčení skutečným PINem → reálná data nedotčená
    s.lock();
    await s.unlockWithPin('111111');
    expect(s.isDecoyMode, isFalse);
    expect(await s.getSetting<String>('marker'), 'REAL',
        reason: 'reálná data přežila zápis v decoy módu');

    // Zpět decoy → jeho zápis přetrval odděleně
    s.lock();
    await s.unlockWithPin('222222');
    expect(await s.getSetting<String>('marker'), 'DECOY');

    // Špatný PIN (ani real ani decoy) → WrongPinException
    s.lock();
    await expectLater(
        s.unlockWithPin('999999'), throwsA(isA<WrongPinException>()));
  });

  testWidgets('DECOY PIN se musí lišit od skutečného', (tester) async {
    final dir = await getApplicationSupportDirectory();
    final s = SecureStorageService(dbPath: '${dir.path}/it_conf_${DateTime.now().millisecondsSinceEpoch}.db');
    await s.unlockWithoutPin();
    await s.enablePin('123456');
    await expectLater(
        s.enableDecoyPin('123456'), throwsA(isA<DecoyPinConflict>()));
  });

  testWidgets('ZMĚNA PINU po nastavení decoy: nový PIN odemkne reálná data, '
      'starý už ne, decoy zůstává funkční', (tester) async {
    final dir = await getApplicationSupportDirectory();
    final s = SecureStorageService(dbPath: '${dir.path}/it_chg_${DateTime.now().millisecondsSinceEpoch}.db');

    await s.unlockWithoutPin();
    await s.setSetting('marker', 'REAL');
    await s.enablePin('111222');
    await s.enableDecoyPin('999888');

    // Změna PINu (přesně pořadí z on-device testu: PIN → decoy → změna PINu)
    await s.changePin(oldPin: '111222', newPin: '333444');

    // Nový PIN odemkne reálná data
    s.lock();
    await s.unlockWithPin('333444');
    expect(s.isDecoyMode, isFalse);
    expect(await s.getSetting<String>('marker'), 'REAL');

    // Starý PIN už neplatí (a není to ani decoy)
    s.lock();
    await expectLater(
        s.unlockWithPin('111222'), throwsA(isA<WrongPinException>()));

    // Decoy PIN pořád otevírá prázdnou decoy DB
    s.lock();
    await s.unlockWithPin('999888');
    expect(s.isDecoyMode, isTrue);
    expect(await s.getSetting<String>('marker'), isNull);

    // Nový PIN se nesmí trefit do decoy
    s.lock();
    await s.unlockWithPin('333444');
    await expectLater(s.changePin(oldPin: '333444', newPin: '999888'),
        throwsA(isA<DecoyPinConflict>()));
  });

  testWidgets('AUTO-ZÁMEK: lock() za běhu zavře DB, unlock stejným PINem '
      'data vrátí (SQLCipher reopen)', (tester) async {
    final dir = await getApplicationSupportDirectory();
    final s = SecureStorageService(dbPath: '${dir.path}/it_lock_${DateTime.now().millisecondsSinceEpoch}.db');

    await s.unlockWithoutPin();
    await s.setSetting('marker', 'PRED-ZAMKEM');
    await s.enablePin('111222');

    // Simulace auto-zámku: zamkni za běhu (DB se zavře)
    s.lock();
    expect(s.isUnlocked, isFalse);

    // Odemčení TÝMŽ PINem musí projít a vrátit data
    await s.unlockWithPin('111222');
    expect(s.isUnlocked, isTrue);
    expect(await s.getSetting<String>('marker'), 'PRED-ZAMKEM',
        reason: 'auto-zámek nesmí poškodit wrapped DEK ani DB');

    // Opakovaný cyklus zámek → odemčení (stabilita)
    s.lock();
    await s.unlockWithPin('111222');
    expect(await s.getSetting<String>('marker'), 'PRED-ZAMKEM');
  });

  testWidgets('ZÁLOHA: export → import obnoví konverzaci (a cizí identita ji '
      'neotevře)', (tester) async {
    final dir = await getApplicationSupportDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // Zdroj: konverzace se zprávou
    final src = SecureStorageService(dbPath: '${dir.path}/it_bk_src_$ts.db');
    await src.unlockWithoutPin();
    final conv = Conversation(contactId: 'PEER1', messages: [
      Message.text(senderId: 'PEER1', recipientId: 'me', content: 'ahoj ze zálohy'),
    ]);
    await src.saveConversation(conv);

    final me = await LocalIdentity.create('Já');
    final bytes = await BackupService(src).export(me);
    expect(bytes.length, greaterThan(20));

    // Cíl: čerstvá DB, import STEJNOU identitou → konverzace zpět
    final dst = SecureStorageService(dbPath: '${dir.path}/it_bk_dst_$ts.db');
    await dst.unlockWithoutPin();
    expect((await dst.loadConversations()).length, 0);
    final n = await BackupService(dst).import(me, bytes);
    expect(n, 1);
    final restored = await dst.loadConversations();
    expect(restored.length, 1);
    expect(restored.first.messages.first.content, 'ahoj ze zálohy');

    // Cizí identita zálohu neotevře
    final other = await LocalIdentity.create('Nikdo');
    final dst2 = SecureStorageService(dbPath: '${dir.path}/it_bk_x_$ts.db');
    await dst2.unlockWithoutPin();
    await expectLater(
        BackupService(dst2).import(other, bytes), throwsA(isA<FormatException>()));
  });
}
