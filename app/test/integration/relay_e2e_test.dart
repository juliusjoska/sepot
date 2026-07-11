@Tags(['relay'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart' show IdentityKeyPair, ProtocolAddress;
import 'package:sepot/core/crypto/attachment_cipher.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/network/relay_client.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/persistent_stores.dart';
import 'package:sepot/models/attachment.dart';

/// E2E přes REÁLNÝ lokální relay (S3+S6): produkční cesta bez UI.
/// Spuštění: relay musí běžet (SEPOT_RELAY, default http://127.0.0.1:8470).
///   flutter test test/integration --tags relay
void main() {
  final relayUrl =
      Platform.environment['SEPOT_RELAY'] ?? 'http://127.0.0.1:8470';

  SepotStores dbStores(CryptoDb db, IdentityKeyPair identity, int regId) =>
      SepotStores(
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

  late Directory tmp;

  setUpAll(() async {
    await SepotCrypto.init();
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('sepot_e2e'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('offline fronta → doručení → restart příjemce → ratchet pokračuje',
      () async {
    final dek = RelayClient.randomBytes(32);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // ── Alice (in-memory stores stačí — restart testujeme u Boba) ──
    final aliceKeys = SepotCrypto.generateIdentityKeys();
    final alice = SepotCrypto.fromPrivateKey(
      privateKey: aliceKeys.privateKey,
      accountId: 'unbound',
      registrationId: 1001,
    );
    final aliceRelay = RelayClient(baseUrl: relayUrl, crypto: alice);
    final aliceDa = RelayClient.randomBytes(32);
    await aliceRelay.register(
      bundle: await alice.generatePreKeyBundle(
        preKeyId: 1,
        signedPreKeyId: 1,
        kyberPreKeyId: 1,
        timestampMs: nowMs,
      ),
      oneTimePreKeys: await alice.generateOneTimePreKeys(startId: 2, count: 3),
      deliveryAddress: aliceDa,
    );

    // ── Bob (persistent stores — bude restartovat) ──
    final bobKeys = SepotCrypto.generateIdentityKeys();
    final bobDbPath = '${tmp.path}/bob.db';
    var bobDb = CryptoDb.open(path: bobDbPath, dek: dek);
    var bob = SepotCrypto.fromPrivateKey(
      privateKey: bobKeys.privateKey,
      accountId: 'unbound',
      registrationId: 1002,
      storesFactory: (id) => dbStores(bobDb, id, 1002),
    );
    var bobRelay = RelayClient(baseUrl: relayUrl, crypto: bob);
    final bobDa = RelayClient.randomBytes(32);
    final bobReg = await bobRelay.register(
      bundle: await bob.generatePreKeyBundle(
        preKeyId: 1,
        signedPreKeyId: 1,
        kyberPreKeyId: 1,
        timestampMs: nowMs,
      ),
      oneTimePreKeys: await bob.generateOneTimePreKeys(startId: 2, count: 3),
      deliveryAddress: bobDa,
    );

    // ── Alice: bundle Boba + OVĚŘENÍ identity klíče (anti-MITM) ──
    final bundle = await aliceRelay.fetchBundle(bobDa);
    expect(bundle.identityKey, bobKeys.publicKey,
        reason: 'Bundle z relaye musí nést Bobův skutečný identity klíč');

    final bobAddr = ProtocolAddress(name: bobReg.accountId, deviceId: 1);
    await alice.processRemoteBundle(bobAddr, bundle);
    final (cert, trustRoot) = await aliceRelay.fetchSenderCertificate();

    // ── Zpráva 1: Bob OFFLINE → fronta ──
    final sealed1 = await alice.sealedEncrypt(
      recipient: bobAddr,
      plaintext: utf8.encode('první — do fronty'),
      senderCertificate: cert,
    );
    aliceRelay.start();
    await aliceRelay.stateStream
        .firstWhere((s) => s == RelayConnectionState.connected)
        .timeout(const Duration(seconds: 5));
    final r1 = await aliceRelay.sendEnvelope(
      dstAddress: bobDa,
      payload: sealed1,
    );
    expect(r1.status.name, 'STATUS_STORED_OFFLINE');

    // ── Bob se připojí, dostane z fronty, dešifruje, ACKne ──
    final delivered1F = bobRelay.deliveries.first;
    bobRelay.start();
    final delivered1 =
        await delivered1F.timeout(const Duration(seconds: 5));
    final opened1 = await bob.sealedDecrypt(
      ciphertext: Uint8List.fromList(delivered1.payload),
      trustRoot: trustRoot,
      timestampMs: nowMs,
    );
    expect(utf8.decode(opened1.plaintext), 'první — do fronty');
    expect(opened1.senderName, alice.address.name(),
        reason: 'odesílatele zná jen příjemce (sealed sender)');
    expect(opened1.senderIdentityKey, aliceKeys.publicKey,
        reason: 'identity klíč odesílatele ověřen certifikátem');
    bobRelay.ack(delivered1.msgUuid);

    // Bob odpoví (uzavře ratchet oběma směry) — Alice je online
    final (bobCert, _) = await bobRelay.fetchSenderCertificate();
    final aliceDeliverF = aliceRelay.deliveries.first;
    final sealedReply = await bob.sealedEncrypt(
      recipient: ProtocolAddress(name: alice.address.name(), deviceId: 1),
      plaintext: utf8.encode('odpověď'),
      senderCertificate: bobCert,
    );
    await bobRelay.sendEnvelope(dstAddress: aliceDa, payload: sealedReply);
    final aliceGot =
        await aliceDeliverF.timeout(const Duration(seconds: 5));
    final aliceOpened = await alice.sealedDecrypt(
      ciphertext: Uint8List.fromList(aliceGot.payload),
      trustRoot: trustRoot,
      timestampMs: nowMs,
    );
    expect(utf8.decode(aliceOpened.plaintext), 'odpověď');
    aliceRelay.ack(aliceGot.msgUuid);

    // ── RESTART BOBA: zavřít vše, nové instance ze stejného DB souboru ──
    await bobRelay.dispose();
    bobDb.close();

    bobDb = CryptoDb.open(path: bobDbPath, dek: dek);
    bob = SepotCrypto.fromPrivateKey(
      privateKey: bobKeys.privateKey,
      accountId: bobReg.accountId,
      registrationId: 1002,
      storesFactory: (id) => dbStores(bobDb, id, 1002),
    );
    bobRelay = RelayClient(baseUrl: relayUrl, crypto: bob);
    bobRelay.restoreSession(
      accountId: bobReg.accountId,
      deviceUuid: bobReg.deviceUuid,
    );

    // ── Zpráva 2: ratchet MUSÍ pokračovat ze stavu na disku ──
    final delivered2F = bobRelay.deliveries.first;
    bobRelay.start();
    await bobRelay.stateStream
        .firstWhere((s) => s == RelayConnectionState.connected)
        .timeout(const Duration(seconds: 5));

    final sealed2 = await alice.sealedEncrypt(
      recipient: bobAddr,
      plaintext: utf8.encode('po restartu Boba'),
      senderCertificate: cert,
    );
    final r2 = await aliceRelay.sendEnvelope(
      dstAddress: bobDa,
      payload: sealed2,
    );
    expect(r2.status.name, 'STATUS_DELIVERED_ONLINE');

    final delivered2 =
        await delivered2F.timeout(const Duration(seconds: 5));
    final opened2 = await bob.sealedDecrypt(
      ciphertext: Uint8List.fromList(delivered2.payload),
      trustRoot: trustRoot,
      timestampMs: nowMs,
    );
    expect(utf8.decode(opened2.plaintext), 'po restartu Boba');
    bobRelay.ack(delivered2.msgUuid);

    await aliceRelay.dispose();
    await bobRelay.dispose();
    bobDb.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('příloha: šifrovaný blob přes relay + meta E2E zprávou (§4.6)',
      () async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    Future<(SepotCrypto, RelayClient, Uint8List, RelayRegistration)> spawn(
        int regId) async {
      final keys = SepotCrypto.generateIdentityKeys();
      final crypto = SepotCrypto.fromPrivateKey(
        privateKey: keys.privateKey,
        accountId: 'unbound',
        registrationId: regId,
      );
      final relay = RelayClient(baseUrl: relayUrl, crypto: crypto);
      final da = RelayClient.randomBytes(32);
      final reg = await relay.register(
        bundle: await crypto.generatePreKeyBundle(
          preKeyId: 1,
          signedPreKeyId: 1,
          kyberPreKeyId: 1,
          timestampMs: nowMs,
        ),
        oneTimePreKeys: await crypto.generateOneTimePreKeys(startId: 2, count: 3),
        deliveryAddress: da,
      );
      return (crypto, relay, da, reg);
    }

    final (alice, aliceRelay, _, _) = await spawn(2001);
    final (bob, bobRelay, bobDa, bobReg) = await spawn(2002);

    // ── Alice: „fotka" → per-file šifra → upload blobu na relay ──
    final original = Uint8List.fromList(
        List.generate(200 * 1024, (i) => (i * 31 + 7) & 0xFF));
    final encrypted = await AttachmentCipher.encrypt(original);
    final blobId = await aliceRelay.uploadAttachment(encrypted.blob);
    expect(blobId, matches(RegExp(r'^[0-9a-f]{32}$')));

    // ── meta jde E2E zprávou (relay ji nikdy nevidí) ──
    final meta = AttachmentMeta(
      blobId: blobId,
      keyB64: base64Encode(encrypted.key),
      nonceB64: base64Encode(encrypted.nonce),
      digestB64: base64Encode(encrypted.digest),
      size: encrypted.plaintextSize,
      mime: 'image/jpeg',
      width: 640,
      height: 480,
    );
    final content = jsonEncode({
      'v': 1,
      't': 'att',
      'id': 'test-att-1',
      'att': meta.toWire(),
    });

    final bundle = await aliceRelay.fetchBundle(bobDa);
    final bobAddr = ProtocolAddress(name: bobReg.accountId, deviceId: 1);
    await alice.processRemoteBundle(bobAddr, bundle);
    final (cert, trustRoot) = await aliceRelay.fetchSenderCertificate();

    aliceRelay.start();
    await aliceRelay.stateStream
        .firstWhere((s) => s == RelayConnectionState.connected)
        .timeout(const Duration(seconds: 5));
    final deliveredF = bobRelay.deliveries.first;
    bobRelay.start();

    final sealed = await alice.sealedEncrypt(
      recipient: bobAddr,
      plaintext: utf8.encode(content),
      senderCertificate: cert,
    );
    await aliceRelay.sendEnvelope(dstAddress: bobDa, payload: sealed);

    // ── Bob: dešifruje zprávu → stáhne blob (bez auth) → digest → data ──
    final delivered = await deliveredF.timeout(const Duration(seconds: 5));
    final opened = await bob.sealedDecrypt(
      ciphertext: Uint8List.fromList(delivered.payload),
      trustRoot: trustRoot,
      timestampMs: nowMs,
    );
    final received =
        jsonDecode(utf8.decode(opened.plaintext)) as Map<String, dynamic>;
    expect(received['t'], 'att');
    final gotMeta =
        AttachmentMeta.fromWire(received['att'] as Map<String, dynamic>);
    expect(gotMeta.blobId, blobId);

    final blob = await bobRelay.downloadAttachment(gotMeta.blobId);
    final plaintext = await AttachmentCipher.decrypt(
      blob: blob,
      key: gotMeta.key,
      nonce: gotMeta.nonce,
      expectedDigest: gotMeta.digest,
    );
    expect(plaintext, equals(original));
    bobRelay.ack(delivered.msgUuid);

    // ── negativní: neexistující blob = 404 ──
    await expectLater(
      bobRelay.downloadAttachment('00112233445566778899aabbccddeeff'),
      throwsA(isA<RelayException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );

    await aliceRelay.dispose();
    await bobRelay.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('smazání účtu: DELETE /v1/identity → bundle 404, druhé smazání 401',
      () async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final keys = SepotCrypto.generateIdentityKeys();
    final crypto = SepotCrypto.fromPrivateKey(
      privateKey: keys.privateKey,
      accountId: 'unbound',
      registrationId: 1003,
    );
    final relay = RelayClient(baseUrl: relayUrl, crypto: crypto);
    final da = RelayClient.randomBytes(32);
    await relay.register(
      bundle: await crypto.generatePreKeyBundle(
        preKeyId: 1,
        signedPreKeyId: 1,
        kyberPreKeyId: 1,
        timestampMs: nowMs,
      ),
      oneTimePreKeys: await crypto.generateOneTimePreKeys(startId: 2, count: 3),
      deliveryAddress: da,
    );

    // účet existuje — bundle jde stáhnout
    await relay.fetchBundle(da);

    await relay.deleteIdentity();

    // po smazání je adresa neznámá
    await expectLater(
      relay.fetchBundle(da),
      throwsA(isA<RelayException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );

    // druhé smazání: zařízení už neexistuje → 401 (idempotence auth vrstvy)
    await expectLater(
      relay.deleteIdentity(),
      throwsA(isA<RelayException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );

    await relay.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
