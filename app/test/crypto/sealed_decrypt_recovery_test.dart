// Needs the native libsignal library (FFI); skipped on builders without it (--exclude-tags ffi).
@Tags(['ffi'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart'
    show
        IdentityKeyPair,
        PreKeyRecord,
        PreKeyStore,
        PrivateKey,
        ProtocolAddress,
        SessionRecord,
        SessionStore,
        createSenderCertificate,
        createServerCertificate;
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/persistent_stores.dart';

/// Ztráta zpráv na straně příjemce:
/// rozlišení chyb dešifrování, odesílatel z vnější vrstvy sealed senderu
/// a odložený zápis ratchetu, dokud není obsah uložený.
void main() {
  setUpAll(() async => SepotCrypto.init());

  late _Authority relay;
  setUp(() => relay = _Authority());

  test(
    'vnější vrstva: odesílatel PreKey i běžné zprávy sedí s libsignal',
    () async {
      final alice = _Peer('a1');
      final bob = _Peer('b1');
      await alice.connectTo(bob);

      for (var i = 0; i < 3; i++) {
        final sealed = await alice.send(bob, 'zpráva $i', relay);
        final sender = bob.crypto.identifySender(
          ciphertext: sealed,
          trustRoot: relay.trustRoot,
        );
        final opened = await bob.open(sealed, relay);
        expect(sender.name, opened.senderName);
        expect(sender.deviceId, opened.senderDeviceId);
        expect(sender.identityKey, opened.senderIdentityKey);
        expect(sender.identityKey, alice.crypto.identityPublicKey);
        expect(
          sender.messageType,
          SepotSealedSender.typePreKey,
          reason: 'Bob zatím neodpověděl',
        );
      }

      await alice.open(await bob.send(alice, 'odpověď', relay), relay);
      final whisper = await alice.send(bob, 'běžná', relay);
      expect(
        bob.crypto
            .identifySender(ciphertext: whisper, trustRoot: relay.trustRoot)
            .messageType,
        SepotSealedSender.typeWhisper,
      );
    },
  );

  test('vnější vrstva: cizí, poškozená nebo cizím relayem podepsaná obálka '
      'neprojde', () async {
    final alice = _Peer('a2');
    final bob = _Peer('b2');
    final carol = _Peer('c2');
    await alice.connectTo(bob);
    final sealed = await alice.send(bob, 'pro Boba', relay);

    expect(
      () => carol.crypto.identifySender(
        ciphertext: sealed,
        trustRoot: relay.trustRoot,
      ),
      throwsFormatException,
      reason: 'obálka pro jiného příjemce',
    );

    for (final at in [1, sealed.length ~/ 2, sealed.length - 1]) {
      final tampered = Uint8List.fromList(sealed)..[at] ^= 0x01;
      expect(
        () => bob.crypto.identifySender(
          ciphertext: tampered,
          trustRoot: relay.trustRoot,
        ),
        throwsFormatException,
        reason: 'změněný bajt $at',
      );
    }

    expect(
      () => bob.crypto.identifySender(
        ciphertext: sealed,
        trustRoot: _Authority().trustRoot,
      ),
      throwsFormatException,
      reason: 'certifikát od jiného trust rootu',
    );
  });

  group('druh chyby dešifrování (texty z libsignal)', () {
    test('opakované doručení téže obálky = duplicate', () async {
      final alice = _Peer('a3');
      final bob = _Peer('b3');
      await alice.connectTo(bob);
      final sealed = await alice.send(bob, 'jednou', relay);
      await bob.open(sealed, relay);
      await expectLater(
        bob.open(sealed, relay),
        throwsA(_failure(SepotDecryptFailure.duplicate)),
      );
    });

    test('příjemce ztratil relaci = brokenSession', () async {
      final alice = _Peer('a4');
      final bob = _Peer('b4');
      await alice.connectTo(bob);
      await bob.open(await alice.send(bob, 'první', relay), relay);
      // Bob odpoví → Alice přestane posílat PreKey zprávy.
      await alice.open(await bob.send(alice, 'odpověď', relay), relay);

      await bob.crypto.dropSession(alice.address);
      await expectLater(
        bob.open(await alice.send(bob, 'druhá', relay), relay),
        throwsA(_failure(SepotDecryptFailure.brokenSession)),
      );
    });

    test('relace nesedí (bad MAC) = brokenSession', () async {
      final alice = _Peer('a5');
      final bob = _Peer('b5');
      final carol = _Peer('c5');
      await alice.connectTo(bob);
      await bob.open(await alice.send(bob, 'první', relay), relay);
      await alice.open(await bob.send(alice, 'odpověď', relay), relay);

      // Bobův stav relace s Alicí nahradí cizí relace — jako po obnově
      // z jiného zařízení nebo poškozeném zápisu.
      await carol.connectTo(bob);
      await bob.open(await carol.send(bob, 'od Carol', relay), relay);
      await bob.stores.session.storeSession(
        alice.address,
        (await bob.stores.session.loadSession(carol.address))!,
      );

      await expectLater(
        bob.open(await alice.send(bob, 'druhá', relay), relay),
        throwsA(_failure(SepotDecryptFailure.brokenSession)),
      );
    });

    test('chybí signed prekey z bundle = brokenSession', () async {
      final alice = _Peer('a6');
      final bob = _Peer('b6');
      await alice.connectTo(bob);
      await bob.stores.signedPreKey.removeSignedPreKey(1);
      await expectLater(
        bob.open(await alice.send(bob, 'první', relay), relay),
        throwsA(_failure(SepotDecryptFailure.brokenSession)),
      );
    });

    test('vypršelý certifikát = invalidCertificate, s časem před vypršením '
        'projde', () async {
      final alice = _Peer('a7');
      final bob = _Peer('b7');
      await alice.connectTo(bob);
      final issued = DateTime.now().subtract(const Duration(days: 8));
      final sealed = await alice.send(
        bob,
        'stará',
        relay,
        certExpiresAt: issued.add(const Duration(days: 7)),
      );
      await expectLater(
        bob.open(sealed, relay),
        throwsA(_failure(SepotDecryptFailure.invalidCertificate)),
      );

      final sender = bob.crypto.identifySender(
        ciphertext: sealed,
        trustRoot: relay.trustRoot,
      );
      final opened = await bob.crypto.sealedDecrypt(
        ciphertext: sealed,
        trustRoot: relay.trustRoot,
        timestampMs: sender.certificateExpiresAtMs - 1,
      );
      expect(utf8.decode(opened.plaintext), 'stará');
    });

    test('poškozený záznam relace v úložišti = brokenSession, nová relace '
        'ho nahradí', () async {
      final alice = _Peer('a10');
      final bob = _DbPeer('b10');
      await alice.connectTo(bob.peer);
      await bob.peer.open(await alice.send(bob.peer, 'první', relay), relay);
      bob.db.raw.execute('UPDATE sessions SET record = ?', [
        Uint8List.fromList(List.filled(40, 7)),
      ]);

      await expectLater(
        bob.peer.open(await alice.send(bob.peer, 'druhá', relay), relay),
        throwsA(_failure(SepotDecryptFailure.brokenSession)),
      );

      // Obnova (žádost o znovuposlání): Bob založí novou relaci z bundle.
      final bundle = await alice.crypto.generatePreKeyBundle(
        preKeyId: 2,
        signedPreKeyId: 2,
        kyberPreKeyId: 2,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
      await expectLater(
        bob.peer.crypto.processRemoteBundle(alice.address, bundle),
        throwsA(anything),
        reason: 'na nečitelné relaci ztroskotá i založení nové',
      );
      await bob.peer.crypto.dropUnreadableSession(alice.address);
      await bob.peer.crypto.processRemoteBundle(alice.address, bundle);
      final rtr = await bob.peer.send(alice, 'pošli znovu', relay);
      expect(
        utf8.decode((await alice.open(rtr, relay)).plaintext),
        'pošli znovu',
      );
      expect(
        utf8.decode(
          (await bob.peer.open(
            await alice.send(bob.peer, 'třetí', relay),
            relay,
          )).plaintext,
        ),
        'třetí',
      );
    });

    test('nečitelný stav relace z úložiště = brokenSession', () async {
      final alice = _Peer('a11');
      final bob = _Peer('b11', corruptSessions: true);
      await alice.connectTo(bob);
      await bob.open(await alice.send(bob, 'první', relay), relay);
      bob.sessions!.corrupt = true;
      await expectLater(
        bob.open(await alice.send(bob, 'druhá', relay), relay),
        throwsA(_failure(SepotDecryptFailure.brokenSession)),
      );
    });

    test('nesmysl = malformed', () async {
      final bob = _Peer('b8');
      await expectLater(
        bob.open(Uint8List.fromList(List.filled(80, 0x11)), relay),
        throwsA(_failure(SepotDecryptFailure.malformed)),
      );
    });
  });

  group('odložený zápis ratchetu (beforeCommit)', () {
    test('do transakce se nevklíní zápis jiného kódu', () async {
      final alice = _Peer('a13');
      final bob = _DbPeer('b13');
      await alice.connectTo(bob.peer);
      final first = await alice.send(bob.peer, 'první', relay);

      // Cokoli, co appka zapíše mezitím (přijatá zpráva, nastavení), nesmí
      // skončit v transakci dešifrování a zmizet s jejím rollbackem.
      bob.sessions.onStore = () => scheduleMicrotask(
        () => bob.db.kvPut('jiny_zapis', Uint8List.fromList([1])),
      );
      bob.preKeys.failNextRemove = true;
      await expectLater(
        bob.peer.crypto.sealedDecrypt(
          ciphertext: first,
          trustRoot: relay.trustRoot,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          beforeCommit: (_) {},
        ),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(bob.db.kvGet('jiny_zapis'), [1]);
      expect(await bob.peer.crypto.hasSession(alice.address), isFalse);
    });

    test('obsah a ratchet v jedné transakci: pád uprostřed zápisu nenechá '
        'nic napůl', () async {
      final alice = _Peer('a12');
      final bob = _DbPeer('b12');
      await alice.connectTo(bob.peer);
      final first = await alice.send(bob.peer, 'první (PreKey)', relay);
      final uuid = Uint8List.fromList(List.filled(16, 1));

      Future<SepotSealedMessage> deliver(Uint8List sealed, Uint8List id) =>
          bob.peer.crypto.sealedDecrypt(
            ciphertext: sealed,
            trustRoot: relay.trustRoot,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            beforeCommit: (o) => bob.db.inboxPut(
              msgUuid: id,
              senderName: o.senderName,
              senderDevice: o.senderDeviceId,
              senderIdentity: o.senderIdentityKey,
              plaintext: o.plaintext,
            ),
          );

      // Relace a identita se zapíšou, spotřebování one-time prekey ne.
      bob.preKeys.failNextRemove = true;
      await expectLater(deliver(first, uuid), throwsStateError);
      expect(bob.db.inboxGet(uuid), isNull, reason: 'obsah se neuložil');
      expect(
        await bob.peer.crypto.hasSession(alice.address),
        isFalse,
        reason: 'bez obsahu ani relace',
      );
      expect(await bob.preKeys.containsPreKey(1), isTrue);

      // Relay obálku doručí znovu, pak přijde další zpráva.
      expect(
        utf8.decode((await deliver(first, uuid)).plaintext),
        'první (PreKey)',
      );
      expect(bob.db.inboxGet(uuid)!.plaintext, isNotNull);
      expect(await bob.preKeys.containsPreKey(1), isFalse);
      final second = await alice.send(bob.peer, 'druhá', relay);
      expect(
        utf8.decode(
          (await deliver(
            second,
            Uint8List.fromList(List.filled(16, 2)),
          )).plaintext,
        ),
        'druhá',
      );
    });

    test(
      'neuložený obsah neposune ratchet — obálka jde otevřít znovu',
      () async {
        final alice = _Peer('a9');
        final bob = _Peer('b9');
        await alice.connectTo(bob);
        final first = await alice.send(bob, 'první (PreKey s OTP)', relay);

        await expectLater(
          bob.crypto.sealedDecrypt(
            ciphertext: first,
            trustRoot: relay.trustRoot,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            beforeCommit: (_) => throw StateError('úložiště zamčené'),
          ),
          throwsStateError,
        );
        expect(
          await bob.stores.session.containsSession(alice.address),
          isFalse,
          reason: 'relace nevznikla',
        );
        expect(
          await bob.stores.preKey.containsPreKey(1),
          isTrue,
          reason: 'one-time prekey se nespotřeboval',
        );

        String? saved;
        await bob.crypto.sealedDecrypt(
          ciphertext: first,
          trustRoot: relay.trustRoot,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          beforeCommit: (o) => saved = utf8.decode(o.plaintext),
        );
        expect(saved, 'první (PreKey s OTP)');
        expect(await bob.stores.preKey.containsPreKey(1), isFalse);
        await expectLater(
          bob.open(first, relay),
          throwsA(_failure(SepotDecryptFailure.duplicate)),
          reason: 'po uložení je klíč zprávy spotřebovaný',
        );

        await alice.open(await bob.send(alice, 'odpověď', relay), relay);
        final second = await alice.send(bob, 'druhá', relay);
        await expectLater(
          bob.crypto.sealedDecrypt(
            ciphertext: second,
            trustRoot: relay.trustRoot,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            beforeCommit: (_) => throw StateError('pád'),
          ),
          throwsStateError,
        );
        expect(utf8.decode((await bob.open(second, relay)).plaintext), 'druhá');
      },
    );
  });
}

Matcher _failure(SepotDecryptFailure kind) =>
    isA<SepotDecryptException>().having((e) => e.kind, 'kind', kind);

/// Trust root + server certifikát jako na relayi (certs.rs).
class _Authority {
  _Authority() {
    final root = IdentityKeyPair.generate();
    _server = PrivateKey.generate();
    trustRoot = Uint8List.fromList(root.publicKey);
    _serverCert = createServerCertificate(
      keyId: 1,
      serverPublicKey: _server.getPublicKey().serialize(),
      trustRootPrivateKey: root.privateKey,
    );
  }

  late final Uint8List trustRoot;
  late final PrivateKey _server;
  late final Uint8List _serverCert;

  Uint8List certFor(_Peer peer, DateTime expires) => createSenderCertificate(
    senderUuid: peer.account,
    senderDeviceId: 1,
    senderIdentityKey: peer.crypto.identityPublicKey,
    expiration: BigInt.from(expires.millisecondsSinceEpoch),
    serverCertificate: _serverCert,
    serverPrivateKey: _server.serialize(),
  );
}

class _Peer {
  _Peer(
    String tag, {
    bool corruptSessions = false,
    SepotStores Function(IdentityKeyPair pair)? stores,
  }) : account = (tag * 16).substring(0, 32),
       _keys = SepotCrypto.generateIdentityKeys() {
    crypto = SepotCrypto.fromPrivateKey(
      privateKey: _keys.privateKey,
      accountId: account,
      registrationId: 1 + tag.codeUnits.fold(0, (a, b) => a + b),
      storesFactory: (pair) {
        if (stores != null) return this.stores = stores(pair);
        final mem = SepotStores.inMemory(pair, 77);
        if (!corruptSessions) return this.stores = mem;
        sessions = _CorruptibleSessions(mem.session);
        return this.stores = SepotStores(
          session: sessions!,
          identity: mem.identity,
          preKey: mem.preKey,
          signedPreKey: mem.signedPreKey,
          kyberPreKey: mem.kyberPreKey,
        );
      },
    );
  }

  final String account;
  final SepotIdentityKeys _keys;
  late final SepotCrypto crypto;
  late final SepotStores stores;
  _CorruptibleSessions? sessions;

  ProtocolAddress get address => ProtocolAddress(name: account, deviceId: 1);

  Future<void> connectTo(_Peer other) async {
    final bundle = await other.crypto.generatePreKeyBundle(
      preKeyId: 1,
      signedPreKeyId: 1,
      kyberPreKeyId: 1,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    await crypto.processRemoteBundle(other.address, bundle);
  }

  Future<Uint8List> send(
    _Peer to,
    String text,
    _Authority relay, {
    DateTime? certExpiresAt,
  }) => crypto.sealedEncrypt(
    recipient: to.address,
    plaintext: utf8.encode(text),
    senderCertificate: relay.certFor(
      this,
      certExpiresAt ?? DateTime.now().add(const Duration(days: 7)),
    ),
  );

  Future<SepotSealedMessage> open(Uint8List sealed, _Authority relay) =>
      crypto.sealedDecrypt(
        ciphertext: sealed,
        trustRoot: relay.trustRoot,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
}

/// Peer nad šifrovanou DB jako v appce (stores sdílí jednu transakci).
class _DbPeer {
  _DbPeer(String tag) {
    final dir = Directory.systemTemp.createTempSync('sepot_atomic');
    addTearDown(() => dir.deleteSync(recursive: true));
    final rng = Random.secure();
    db = CryptoDb.open(
      path: '${dir.path}/app.db',
      dek: Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256))),
    );
    addTearDown(db.close);
    preKeys = _FlakyPreKeys(DbPreKeyStore(db));
    sessions = _ObservedSessions(DbSessionStore(db));
    peer = _Peer(
      tag,
      stores: (pair) => SepotStores(
        session: sessions,
        identity: DbIdentityKeyStore(
          db,
          identityKeyPair: pair,
          registrationId: 9,
        ),
        preKey: preKeys,
        signedPreKey: DbSignedPreKeyStore(db),
        kyberPreKey: DbKyberPreKeyStore(db),
        transaction: db.transaction<void>,
      ),
    );
  }

  late final CryptoDb db;
  late final _FlakyPreKeys preKeys;
  late final _ObservedSessions sessions;
  late final _Peer peer;
}

/// Store relací, u kterého jde zjistit, kdy se relace skutečně zapisuje.
class _ObservedSessions implements SessionStore, SessionStoreSync {
  _ObservedSessions(this._inner);

  final DbSessionStore _inner;
  void Function()? onStore;

  @override
  void storeSessionSync(ProtocolAddress address, SessionRecord record) {
    onStore?.call();
    _inner.storeSessionSync(address, record);
  }

  @override
  Future<void> storeSession(ProtocolAddress address, SessionRecord record) =>
      _inner.storeSession(address, record);

  @override
  Future<SessionRecord?> loadSession(ProtocolAddress address) =>
      _inner.loadSession(address);

  @override
  Future<bool> containsSession(ProtocolAddress address) =>
      _inner.containsSession(address);

  @override
  Future<void> deleteSession(ProtocolAddress address) =>
      _inner.deleteSession(address);

  @override
  Future<void> deleteAllSessions(String name) => _inner.deleteAllSessions(name);

  @override
  Future<List<int>> getSubDeviceSessions(String name) =>
      _inner.getSubDeviceSessions(name);
}

/// Spotřebování one-time prekey jednou selže — „pád“ uprostřed zápisu.
class _FlakyPreKeys implements PreKeyStore, PreKeyStoreSync {
  _FlakyPreKeys(this._inner);

  final DbPreKeyStore _inner;
  bool failNextRemove = false;

  @override
  void removePreKeySync(int preKeyId) {
    if (failNextRemove) {
      failNextRemove = false;
      throw StateError('pád při zápisu');
    }
    _inner.removePreKeySync(preKeyId);
  }

  @override
  Future<void> removePreKey(int preKeyId) async => removePreKeySync(preKeyId);

  @override
  Future<PreKeyRecord?> loadPreKey(int preKeyId) => _inner.loadPreKey(preKeyId);

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _inner.storePreKey(preKeyId, record);

  @override
  Future<bool> containsPreKey(int preKeyId) => _inner.containsPreKey(preKeyId);

  @override
  Future<List<int>> getAllPreKeyIds() => _inner.getAllPreKeyIds();
}

/// Store relací, který po přepnutí vrací záznam, jemuž libsignal
/// nerozumí (jako po poškozeném zápisu na disk).
class _CorruptibleSessions implements SessionStore {
  _CorruptibleSessions(this._inner);

  final SessionStore _inner;
  bool corrupt = false;

  @override
  Future<SessionRecord?> loadSession(ProtocolAddress address) async {
    final record = await _inner.loadSession(address);
    return corrupt && record != null ? _GarbageRecord() : record;
  }

  @override
  Future<void> storeSession(ProtocolAddress address, SessionRecord record) =>
      _inner.storeSession(address, record);

  @override
  Future<bool> containsSession(ProtocolAddress address) =>
      _inner.containsSession(address);

  @override
  Future<void> deleteSession(ProtocolAddress address) =>
      _inner.deleteSession(address);

  @override
  Future<void> deleteAllSessions(String name) => _inner.deleteAllSessions(name);

  @override
  Future<List<int>> getSubDeviceSessions(String name) =>
      _inner.getSubDeviceSessions(name);
}

class _GarbageRecord implements SessionRecord {
  @override
  Uint8List serialize() => Uint8List.fromList(List.filled(40, 7));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
