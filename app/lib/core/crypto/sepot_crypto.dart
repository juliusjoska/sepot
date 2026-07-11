/// Fasáda SepotCrypto — port/adapter nad krypto backendem (libsignal).
///
/// Smysl: veškerý kód Šepotu mluví JEN s touhle fasádou,
/// nikdy přímo s balíčkem `libsignal`. Backend tak zůstává vyměnitelný
/// (libsignal FFI ↔ libsignal_protocol_dart ↔ vlastní FRB fork) bez zásahu
/// do zbytku aplikace.
///
/// Stores jsou zatím in-memory; později je nahradí
/// perzistence nad SQLCipher.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:libsignal/libsignal.dart';

/// Pár serializovaných identity klíčů — jediný tvar, ve kterém identity
/// klíče opouštějí fasádu (žádné backend-specifické typy ven).
class SepotIdentityKeys {
  SepotIdentityKeys({required this.privateKey, required this.publicKey});

  /// 32 B, serializovaný (clampnutý) privátní klíč. Přesně tyhle bajty
  /// se enkódují do mnemonic — díky clampingu při serializaci je
  /// deserialize→serialize bitově stabilní roundtrip.
  final Uint8List privateKey;

  /// 33 B, serializovaný veřejný klíč (libsignal type byte + 32 B).
  /// Z něj se počítá fingerprint.
  final Uint8List publicKey;
}

/// Serializovatelný obsah prekey bundle — přesně to, co klient nahraje
/// na relay a co si druhá strana stáhne. Jen bajty a čísla, žádné
/// backend-specifické typy (musí projít protobufem beze změny).
class SepotPreKeyBundle {
  SepotPreKeyBundle({
    required this.registrationId,
    required this.deviceId,
    required this.preKeyId,
    required this.preKeyPublic,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    required this.identityKey,
    required this.kyberPreKeyId,
    required this.kyberPreKeyPublic,
    required this.kyberPreKeySignature,
  });

  final int registrationId;
  final int deviceId;
  final int? preKeyId;
  final Uint8List? preKeyPublic;
  final int signedPreKeyId;
  final Uint8List signedPreKeyPublic;
  final Uint8List signedPreKeySignature;
  final Uint8List identityKey;
  final int kyberPreKeyId;
  final Uint8List kyberPreKeyPublic;
  final Uint8List kyberPreKeySignature;
}

/// Výsledek dešifrování sealed-sender obálky.
class SepotSealedMessage {
  SepotSealedMessage({
    required this.plaintext,
    required this.senderName,
    required this.senderDeviceId,
    required this.senderIdentityKey,
  });

  final Uint8List plaintext;

  /// accountId odesílatele (hex) ze SenderCertificate — zná ho JEN příjemce.
  final String senderName;
  final int senderDeviceId;

  /// Serializovaný identity klíč odesílatele (33 B) — kryptograficky
  /// ověřený certifikátem. Fingerprint z něj mapuje zprávu na kontakt.
  final Uint8List senderIdentityKey;
}

/// Jeden one-time prekey k publikaci na relay.
class SepotOneTimePreKey {
  SepotOneTimePreKey({required this.id, required this.publicKey});

  final int id;
  final Uint8List publicKey;
}

/// Sada stores, nad kterými krypto instance pracuje. Produkce dodává
/// perzistentní (SQLCipher, `persistent_stores.dart`), testy in-memory.
class SepotStores {
  SepotStores({
    required this.session,
    required this.identity,
    required this.preKey,
    required this.signedPreKey,
    required this.kyberPreKey,
  });

  /// In-memory sada (spike, testy) — po zabití procesu je pryč.
  factory SepotStores.inMemory(IdentityKeyPair identity, int registrationId) {
    return SepotStores(
      session: InMemorySessionStore(),
      identity: InMemoryIdentityKeyStore(identity, registrationId),
      preKey: InMemoryPreKeyStore(),
      signedPreKey: InMemorySignedPreKeyStore(),
      kyberPreKey: InMemoryKyberPreKeyStore(),
    );
  }

  final SessionStore session;
  final IdentityKeyStore identity;
  final PreKeyStore preKey;
  final SignedPreKeyStore signedPreKey;
  final KyberPreKeyStore kyberPreKey;
}

/// Jedna krypto identita (účet na jednom zařízení) se všemi stores.
class SepotCrypto {
  SepotCrypto._({
    required this.address,
    required IdentityKeyPair identity,
    required int registrationId,
    SepotStores? stores,
  }) : _identity = identity,
       _registrationId = registrationId,
       _stores = stores ?? SepotStores.inMemory(identity, registrationId);

  /// Inicializace nativní knihovny — volat jednou per proces, před
  /// jakoukoli jinou operací fasády (v `main()` před `runApp`).
  ///
  /// iOS: libsignal doručuje `libsignal_frb` výhradně přes Flutter native
  /// assets a jeho podspec framework nelinkuje. Výchozí FRB loader proto
  /// dlopen-uje bez `@rpath` prefixu, dyld hledá v kořeni `.app` místo ve
  /// `Frameworks/` a selže → němá bílá obrazovka. Předaná cesta se přesně
  /// shoduje s install name, které frameworku nastaví flutter_tools, a
  /// Runner má `@executable_path/Frameworks` v LD_RUNPATH_SEARCH_PATHS.
  static Future<void> init() {
    if (Platform.isIOS) {
      return LibSignal.init(
        libraryPath: '@rpath/libsignal_frb.framework/libsignal_frb',
      );
    }
    return LibSignal.init();
  }

  /// Vytvoří novou identitu (keypair + registration ID).
  factory SepotCrypto.generate({
    required String accountId,
    int deviceId = 1,
    required int registrationId,
    SepotStores? stores,
  }) {
    return SepotCrypto._(
      address: ProtocolAddress(name: accountId, deviceId: deviceId),
      identity: IdentityKeyPair.generate(),
      registrationId: registrationId,
      stores: stores,
    );
  }

  /// Obnoví krypto instanci z existujícího privátního identity klíče
  /// (onboarding po recovery z mnemonic, běžný start aplikace).
  ///
  /// [storesFactory] dostává rekonstruovaný keypair — produkce z něj
  /// postaví perzistentní stores (DbIdentityKeyStore keypair potřebuje).
  factory SepotCrypto.fromPrivateKey({
    required Uint8List privateKey,
    required String accountId,
    int deviceId = 1,
    required int registrationId,
    SepotStores Function(IdentityKeyPair identity)? storesFactory,
  }) {
    final private = PrivateKey.deserialize(bytes: privateKey.toList());
    final identity = IdentityKeyPair.fromKeys(
      privateKey: private,
      publicKey: private.getPublicKey(),
    );
    return SepotCrypto._(
      address: ProtocolAddress(name: accountId, deviceId: deviceId),
      identity: identity,
      registrationId: registrationId,
      stores: storesFactory?.call(identity),
    );
  }

  /// Vygeneruje nový identity keypair a vrátí ho serializovaný.
  /// Používá onboarding; privátní část jde do secure storage
  /// a do mnemonic, nic z toho nedrží backend typy.
  static SepotIdentityKeys generateIdentityKeys() {
    final pair = IdentityKeyPair.generate();
    return SepotIdentityKeys(
      privateKey: Uint8List.fromList(pair.privateKey.toList()),
      publicKey: Uint8List.fromList(pair.publicKey.toList()),
    );
  }

  /// Odvodí veřejný klíč (33 B serialized) z privátního (32 B).
  /// Deterministické — základ recovery z mnemonic.
  static Uint8List derivePublicKey(Uint8List privateKey) {
    final private = PrivateKey.deserialize(bytes: privateKey.toList());
    return Uint8List.fromList(private.getPublicKey().serialize().toList());
  }

  /// Lokální adresa. Po registraci na relay se přepíná na hex(account_id)
  /// přes [bindAccount] — musí sedět se sender_uuid v SenderCertificate.
  ProtocolAddress address;
  final IdentityKeyPair _identity;
  final int _registrationId;
  final SepotStores _stores;

  Uint8List get identityPublicKey => Uint8List.fromList(_identity.publicKey);

  int get registrationId => _registrationId;

  /// Po registraci: server přidělil account_id → lokální adresa se váže
  /// na hex(account_id), aby seděla se sender_uuid v SenderCertificate.
  void bindAccount(String accountHex) {
    address = ProtocolAddress(name: accountHex, deviceId: address.deviceId());
  }

  /// XEdDSA podpis identity klíčem (AUTH výzva, REST auth hlavička).
  Uint8List sign(List<int> message) {
    final identityPrivate = PrivateKey.deserialize(
      bytes: _identity.privateKey.toList(),
    );
    return Uint8List.fromList(identityPrivate.sign(message: message).toList());
  }

  /// Vygeneruje sadu prekeys (one-time + signed + Kyber), uloží je do
  /// vlastních stores a vrátí bundle k publikaci na relay.
  Future<SepotPreKeyBundle> generatePreKeyBundle({
    required int preKeyId,
    required int signedPreKeyId,
    required int kyberPreKeyId,
    required int timestampMs,
  }) async {
    final identityPrivate = PrivateKey.deserialize(
      bytes: _identity.privateKey.toList(),
    );
    final timestamp = BigInt.from(timestampMs);

    final preKeyPrivate = PrivateKey.generate();
    final preKeyPublic = preKeyPrivate.getPublicKey();
    await _stores.preKey.storePreKey(
      preKeyId,
      PreKeyRecord(
        id: preKeyId,
        publicKey: preKeyPublic,
        privateKey: preKeyPrivate,
      ),
    );

    final signedPreKeyPrivate = PrivateKey.generate();
    final signedPreKeyPublic = signedPreKeyPrivate.getPublicKey();
    final signedPreKeySignature = identityPrivate.sign(
      message: signedPreKeyPublic.serialize().toList(),
    );
    await _stores.signedPreKey.storeSignedPreKey(
      signedPreKeyId,
      SignedPreKeyRecord(
        id: signedPreKeyId,
        publicKey: signedPreKeyPublic,
        privateKey: signedPreKeyPrivate,
        signature: signedPreKeySignature.toList(),
        timestamp: timestamp,
      ),
    );

    final kyberKeyPair = KyberKeyPair.generate();
    final kyberPublic = kyberKeyPair.getPublicKey();
    final kyberSignature = identityPrivate.sign(
      message: kyberPublic.serialize().toList(),
    );
    await _stores.kyberPreKey.storeKyberPreKey(
      kyberPreKeyId,
      KyberPreKeyRecord.create(
        id: kyberPreKeyId,
        keyPair: kyberKeyPair,
        signature: kyberSignature.toList(),
        timestamp: timestamp,
      ),
    );

    return SepotPreKeyBundle(
      registrationId: _registrationId,
      deviceId: address.deviceId(),
      preKeyId: preKeyId,
      preKeyPublic: preKeyPublic.serialize(),
      signedPreKeyId: signedPreKeyId,
      signedPreKeyPublic: Uint8List.fromList(
        signedPreKeyPublic.serialize().toList(),
      ),
      signedPreKeySignature: Uint8List.fromList(signedPreKeySignature.toList()),
      identityKey: Uint8List.fromList(_identity.publicKey.toList()),
      kyberPreKeyId: kyberPreKeyId,
      kyberPreKeyPublic: Uint8List.fromList(kyberPublic.serialize().toList()),
      kyberPreKeySignature: Uint8List.fromList(kyberSignature.toList()),
    );
  }

  /// Existuje už ratchet session s protistranou?
  Future<bool> hasSession(ProtocolAddress remote) =>
      _stores.session.containsSession(remote);

  /// X3DH/PQXDH: zpracuje bundle protistrany a založí session.
  Future<void> processRemoteBundle(
    ProtocolAddress remote,
    SepotPreKeyBundle bundle,
  ) async {
    final preKeyBundle = PreKeyBundle(
      registrationId: bundle.registrationId,
      deviceId: bundle.deviceId,
      preKeyId: bundle.preKeyId,
      preKeyPublic: bundle.preKeyPublic,
      signedPreKeyId: bundle.signedPreKeyId,
      signedPreKeyPublic: bundle.signedPreKeyPublic.toList(),
      signedPreKeySignature: bundle.signedPreKeySignature.toList(),
      identityKey: bundle.identityKey.toList(),
      kyberPreKeyId: bundle.kyberPreKeyId,
      kyberPreKeyPublic: bundle.kyberPreKeyPublic.toList(),
      kyberPreKeySignature: bundle.kyberPreKeySignature.toList(),
    );
    final builder = SessionBuilder(
      localAddress: address,
      sessionStore: _stores.session,
      identityKeyStore: _stores.identity,
    );
    await builder.processPreKeyBundle(remote, preKeyBundle);
  }

  SessionCipher get _cipher => SessionCipher(
    localAddress: address,
    sessionStore: _stores.session,
    identityKeyStore: _stores.identity,
    preKeyStore: _stores.preKey,
    signedPreKeyStore: _stores.signedPreKey,
    kyberPreKeyStore: _stores.kyberPreKey,
  );

  /// Double Ratchet šifrování 1:1.
  Future<CiphertextMessage> encryptTo(
    ProtocolAddress remote,
    List<int> plaintext,
  ) => _cipher.encrypt(remote, Uint8List.fromList(plaintext));

  /// Double Ratchet dešifrování 1:1.
  Future<Uint8List> decryptFrom(
    ProtocolAddress remote,
    CiphertextMessage message,
  ) => _cipher.decrypt(remote, message);

  SealedSenderCipher get _sealedCipher => SealedSenderCipher(
    localAddress: address,
    sessionStore: _stores.session,
    identityKeyStore: _stores.identity,
    preKeyStore: _stores.preKey,
    signedPreKeyStore: _stores.signedPreKey,
    kyberPreKeyStore: _stores.kyberPreKey,
  );

  /// Sealed sender: zašifruje tak, že relay nezjistí odesílatele.
  /// [senderCertificate] vydává relay (server-signed).
  Future<Uint8List> sealedEncrypt({
    required ProtocolAddress recipient,
    required List<int> plaintext,
    required Uint8List senderCertificate,
  }) => _sealedCipher.encrypt(
    recipientAddress: recipient,
    plaintext: Uint8List.fromList(plaintext),
    senderCertificate: senderCertificate,
  );

  /// Sealed sender: dešifruje obálku a ověří sender certificate proti
  /// pinnutému trust rootu relaye.
  Future<SepotSealedMessage> sealedDecrypt({
    required Uint8List ciphertext,
    required Uint8List trustRoot,
    required int timestampMs,
  }) async {
    final result = await _sealedCipher.decrypt(
      ciphertext: ciphertext,
      trustRoot: trustRoot,
      timestamp: timestampMs,
    );
    return SepotSealedMessage(
      plaintext: result.plaintext,
      senderName: result.senderAddress.name(),
      senderDeviceId: result.senderAddress.deviceId(),
      senderIdentityKey: Uint8List.fromList(
        result.senderIdentityKey.serialize().toList(),
      ),
    );
  }

  /// Vygeneruje dávku one-time prekeys (uloží privátní části do store,
  /// vrátí veřejné k publikaci). Zásoba 100 ks, doplnění pod
  /// prahem.
  Future<List<SepotOneTimePreKey>> generateOneTimePreKeys({
    required int startId,
    required int count,
  }) async {
    final result = <SepotOneTimePreKey>[];
    for (var i = 0; i < count; i++) {
      final id = startId + i;
      final private = PrivateKey.generate();
      final public = private.getPublicKey();
      await _stores.preKey.storePreKey(
        id,
        PreKeyRecord(id: id, publicKey: public, privateKey: private),
      );
      result.add(
        SepotOneTimePreKey(
          id: id,
          publicKey: Uint8List.fromList(public.serialize().toList()),
        ),
      );
    }
    return result;
  }
}
