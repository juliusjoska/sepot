import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/persistent_stores.dart';
import 'package:sqlite3/sqlite3.dart';

/// S3: krypto stavy musí přežít restart procesu — ratchet pokračuje
/// z disku, jinak by každý restart appky rozbil všechny konverzace.
void main() {
  late Directory tmp;
  final rng = Random.secure();

  Uint8List randomDek() =>
      Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));

  SepotStores dbStores(CryptoDb db, IdentityKeyPair identity, int regId) {
    return SepotStores(
      session: DbSessionStore(db),
      identity: DbIdentityKeyStore(
        db,
        identityKeyPair: identity,
        registrationId: regId,
      ),
      preKey: DbPreKeyStore(db),
      signedPreKey: DbSignedPreKeyStore(db),
      kyberPreKey: DbKyberPreKeyStore(db),
    );
  }

  setUpAll(() async {
    await SepotCrypto.init();
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sepot_s3_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('DB soubor na disku není plaintext SQLite (SQLCipher aktivní)', () {
    final path = '${tmp.path}/crypto.db';
    final db = CryptoDb.open(path: path, dek: randomDek());
    db.kvPut('test', Uint8List.fromList([1, 2, 3]));
    db.close();

    final header = File(path).openSync().readSync(16);
    expect(
      String.fromCharCodes(header),
      isNot(startsWith('SQLite format 3')),
      reason: 'Plaintext hlavička = DB se NEšifruje!',
    );
  });

  test('špatný DEK → výjimka, žádný tichý přístup', () {
    final path = '${tmp.path}/crypto.db';
    CryptoDb.open(path: path, dek: randomDek()).close();
    expect(
      () => CryptoDb.open(path: path, dek: randomDek()),
      throwsA(isA<SqliteException>()),
    );
  });

  test('ratchet přežije restart: handshake → restart Boba → konverzace jede',
      () async {
    final path = '${tmp.path}/bob.db';
    final dek = randomDek();
    final bobKeys = SepotCrypto.generateIdentityKeys();

    final aliceAddr = ProtocolAddress(name: 'alice', deviceId: 1);
    final bobAddr = ProtocolAddress(name: 'bob', deviceId: 1);

    // --- Bob, první běh "aplikace" ---
    final bobDb1 = CryptoDb.open(path: path, dek: dek);
    final bob1 = SepotCrypto.fromPrivateKey(
      privateKey: bobKeys.privateKey,
      accountId: 'bob',
      registrationId: 2,
      storesFactory: (identity) => dbStores(bobDb1, identity, 2),
    );
    final bobBundle = await bob1.generatePreKeyBundle(
      preKeyId: 1,
      signedPreKeyId: 1,
      kyberPreKeyId: 1,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    // --- Alice (in-memory, druhá strana) ---
    final alice = SepotCrypto.generate(accountId: 'alice', registrationId: 1);

    // X3DH + obousměrný handshake
    await alice.processRemoteBundle(bobAddr, bobBundle);
    final msg1 = await alice.encryptTo(bobAddr, 'ahoj Bobe'.codeUnits);
    final plain1 = await bob1.decryptFrom(aliceAddr, msg1);
    expect(String.fromCharCodes(plain1), 'ahoj Bobe');

    final msg2 = await bob1.encryptTo(aliceAddr, 'ahoj Alice'.codeUnits);
    final plain2 = await alice.decryptFrom(bobAddr, msg2);
    expect(String.fromCharCodes(plain2), 'ahoj Alice');

    // OTP prekey se po použití maže (forward secrecy první zprávy)
    expect(await DbPreKeyStore(bobDb1).getAllPreKeyIds(), isEmpty);

    // --- „Zabití aplikace" ---
    bobDb1.close();

    // --- Bob, druhý běh: NIC v paměti, vše z disku ---
    final bobDb2 = CryptoDb.open(path: path, dek: dek);
    final bob2 = SepotCrypto.fromPrivateKey(
      privateKey: bobKeys.privateKey,
      accountId: 'bob',
      registrationId: 2,
      storesFactory: (identity) => dbStores(bobDb2, identity, 2),
    );

    // Ratchet pokračuje oběma směry
    final msg3 = await alice.encryptTo(bobAddr, 'po restartu'.codeUnits);
    final plain3 = await bob2.decryptFrom(aliceAddr, msg3);
    expect(String.fromCharCodes(plain3), 'po restartu');

    final msg4 = await bob2.encryptTo(aliceAddr, 'jedu dál'.codeUnits);
    final plain4 = await alice.decryptFrom(bobAddr, msg4);
    expect(String.fromCharCodes(plain4), 'jedu dál');

    bobDb2.close();
  });

  test('TOFU: změna identity protistrany se detekuje (saveIdentity=true)',
      () async {
    final db = CryptoDb.open(path: '${tmp.path}/tofu.db', dek: randomDek());
    final keys = SepotCrypto.generateIdentityKeys();
    final identity = IdentityKeyPair.fromKeys(
      privateKey: PrivateKey.deserialize(bytes: keys.privateKey.toList()),
      publicKey: PrivateKey.deserialize(bytes: keys.privateKey.toList())
          .getPublicKey(),
    );
    final store = DbIdentityKeyStore(
      db,
      identityKeyPair: identity,
      registrationId: 7,
    );

    final addr = ProtocolAddress(name: 'mallory', deviceId: 1);
    final firstKey = PrivateKey.generate().getPublicKey();
    final secondKey = PrivateKey.generate().getPublicKey();

    // první kontakt: nová identita, TOFU věří
    expect(await store.saveIdentity(addr, firstKey), isTrue);
    expect(
      await store.isTrustedIdentity(addr, firstKey, Direction.sending),
      isTrue,
    );
    // stejný klíč znovu: beze změny
    expect(await store.saveIdentity(addr, firstKey), isFalse);
    // JINÝ klíč: nedůvěryhodný, dokud ho saveIdentity nepřepíše
    expect(
      await store.isTrustedIdentity(addr, secondKey, Direction.sending),
      isFalse,
    );
    db.close();
  });
}
