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
import 'package:sepot/core/crypto/sealed_sender_outer.dart';

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

/// Proč sealed-sender obálku nešlo otevřít. Rozhoduje, jestli ji ACKnout
/// a jestli požádat odesílatele o obnovu relace.
enum SepotDecryptFailure {
  /// Klíč zprávy už byl spotřebován — obálka se dešifrovala dřív.
  duplicate,

  /// Relace s odesílatelem chybí nebo nesedí (přeinstalace, ztracený stav,
  /// ztracený prekey). Opakování nepomůže, pomůže jen nová relace.
  brokenSession,

  /// Odesílatel přišel s jiným identity klíčem, než který známe.
  untrustedIdentity,

  /// Certifikát odesílatele neprošel (typicky vypršel, než si příjemce
  /// obálku vyzvedl).
  invalidCertificate,

  /// Obálka není platná sealed-sender zpráva pro nás.
  malformed,

  /// Nic z výše uvedeného — může jít o dočasný stav (úložiště, FFI).
  other,
}

class SepotDecryptException implements Exception {
  SepotDecryptException(this.message) : kind = classify(message);

  final String message;
  final SepotDecryptFailure kind;

  /// Balíček `libsignal` vrací chyby jen jako text (Display variant
  /// SignalProtocolError z libsignal v0.96.4 a vlastní hlášky wrapperu
  /// v sealed_sender.rs). Texty ověřuje test proti skutečné knihovně,
  /// takže změnu po upgradu balíčku zachytí.
  static SepotDecryptFailure classify(String message) {
    final m = message.toLowerCase();
    if (m.contains('message with old counter')) {
      return SepotDecryptFailure.duplicate;
    }
    if (m.contains('untrusted identity')) {
      return SepotDecryptFailure.untrustedIdentity;
    }
    if (m.contains('sender certificate validation failed')) {
      return SepotDecryptFailure.invalidCertificate;
    }
    if (m.contains('not found') && m.contains('session') ||
        m.contains('failed to deserialize existing session') ||
        m.contains('invalid session') ||
        m.contains('invalid prekey message') ||
        m.contains('invalid whisper message') ||
        m.contains('prekey identifier') ||
        m.contains('pre-key') && m.contains('not found')) {
      return SepotDecryptFailure.brokenSession;
    }
    if (m.contains('sealed sender') ||
        m.contains('protobuf encoding was invalid') ||
        m.contains('ciphertext')) {
      return SepotDecryptFailure.malformed;
    }
    return SepotDecryptFailure.other;
  }

  @override
  String toString() => 'SepotDecryptException(${kind.name}): $message';
}

/// Ověřený odesílatel obálky z vnější vrstvy sealed senderu.
class SepotSealedSender {
  SepotSealedSender({
    required this.name,
    required this.deviceId,
    required this.identityKey,
    required this.certificateExpiresAtMs,
    required this.messageType,
  });

  /// Typ vnitřní zprávy (UnidentifiedSenderMessageContent.Type): běžná
  /// zpráva existující relace, nebo PreKey zpráva, která relaci zakládá.
  static const typePreKey = 1;
  static const typeWhisper = 2;

  /// accountId odesílatele (hex).
  final String name;
  final int deviceId;
  final Uint8List identityKey;
  final int certificateExpiresAtMs;
  final int messageType;
}

/// Nový signed prekey k nahrání na relay (rotace).
class SepotSignedPreKey {
  SepotSignedPreKey({
    required this.id,
    required this.publicKey,
    required this.signature,
  });

  final int id;
  final Uint8List publicKey;
  final Uint8List signature;
}

/// Nový last-resort Kyber prekey k nahrání na relay.
class SepotKyberPreKey {
  SepotKyberPreKey({
    required this.id,
    required this.publicKey,
    required this.signature,
  });

  final int id;
  final Uint8List publicKey;
  final Uint8List signature;
}

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
    this.transaction,
  });

  /// In-memory sada (testy) — po zabití procesu je pryč.
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

  /// Provede [body] jako jednu synchronní transakci nad všemi stores.
  /// S ní musí stores relací, identit a one-time prekeys umět zapisovat
  /// i synchronně ([SessionStoreSync], [IdentityKeyStoreSync],
  /// [PreKeyStoreSync]). Bez ní (paměťové stores) se zápisy dějí postupně.
  final void Function(void Function() body)? transaction;
}

/// Synchronní zápisy stores. Uložení obsahu z deníku a posun ratchetu
/// proběhnou v jedné transakci bez jediného `await` — mezi ně se nevklíní
/// zápis jiného kódu, který by jinak skončil v téže transakci (a při chybě
/// se s ní vrátil).
abstract interface class SessionStoreSync {
  void storeSessionSync(ProtocolAddress address, SessionRecord record);
}

abstract interface class IdentityKeyStoreSync {
  bool saveIdentitySync(ProtocolAddress address, PublicKey identityKey);
}

abstract interface class PreKeyStoreSync {
  void removePreKeySync(int preKeyId);
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

  /// Identity klíč, pod kterým naposledy vznikla relace s [remote]
  /// (zapisuje ho libsignal při X3DH i při příjmu PreKey zprávy).
  /// Null = zatím žádný.
  Future<Uint8List?> sessionIdentity(ProtocolAddress remote) async {
    final key = await _stores.identity.getIdentity(remote);
    return key == null ? null : Uint8List.fromList(key.serialize().toList());
  }

  /// Zahodí relaci s [remote]; další zpráva založí novou z bundle.
  Future<void> dropSession(ProtocolAddress remote) =>
      _stores.session.deleteSession(remote);

  /// Zahodí relaci, jejíž záznam nejde ani načíst (poškozený zápis). Na
  /// takové by ztroskotalo i založení nové relace z bundle — libsignal
  /// starou před přepsáním načítá, aby ji archivoval.
  Future<void> dropUnreadableSession(ProtocolAddress remote) async {
    try {
      await _stores.session.loadSession(remote);
    } on Object {
      await _stores.session.deleteSession(remote);
    }
  }

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
  /// pinnutému trust rootu relaye. Selhání hází [SepotDecryptException]
  /// s rozlišeným druhem.
  ///
  /// S [beforeCommit] se změny stavu (posun ratchetu, identita protistrany,
  /// spotřebovaný one-time prekey) zapíšou až PO jeho úspěšném doběhnutí.
  /// Volající v něm uloží otevřený obsah; když to nestihne (pád procesu,
  /// zamčená DB), ratchet zůstane, kde byl, a obálka jde dešifrovat znovu.
  /// Obráceně by šlo o zprávu navždy: libsignal klíč zprávy po prvním
  /// dešifrování zahodí.
  Future<SepotSealedMessage> sealedDecrypt({
    required Uint8List ciphertext,
    required Uint8List trustRoot,
    required int timestampMs,
    void Function(SepotSealedMessage opened)? beforeCommit,
  }) async {
    final staged = beforeCommit == null ? null : _StagedWrites(_stores);
    final SealedSenderDecryptionResult result;
    try {
      result = await (staged?.cipher(address) ?? _sealedCipher).decrypt(
        ciphertext: ciphertext,
        trustRoot: trustRoot,
        timestamp: timestampMs,
      );
    } on Object catch (e) {
      throw SepotDecryptException(e.toString());
    }
    final opened = SepotSealedMessage(
      plaintext: result.plaintext,
      senderName: result.senderAddress.name(),
      senderDeviceId: result.senderAddress.deviceId(),
      senderIdentityKey: Uint8List.fromList(
        result.senderIdentityKey.serialize().toList(),
      ),
    );
    if (beforeCommit != null) {
      // Uložený obsah a posun ratchetu buď oba, nebo nic. Pád mezi nimi by
      // jinak u PreKey zprávy nechal obsah bez relace (další zprávy od
      // odesílatele by nešly otevřít) a u běžné zprávy ratchet, kterým jde
      // tutéž obálku pod jiným msg_uuid otevřít podruhé.
      final transaction = _stores.transaction;
      if (transaction == null) {
        beforeCommit(opened);
        await staged!.commit();
      } else {
        transaction(() {
          beforeCommit(opened);
          staged!.commitSync();
        });
      }
    }
    return opened;
  }

  /// Odesílatel obálky z vnější vrstvy sealed senderu, i když vnitřní
  /// zpráva nejde dešifrovat. Certifikát musí podepsat [trustRoot]; jeho
  /// platnost v čase se jen hlásí ([SepotSealedSender.certificateExpiresAtMs]).
  /// Obálka, která není platně zapečetěná pro tuhle identitu, hází
  /// [FormatException].
  SepotSealedSender identifySender({
    required Uint8List ciphertext,
    required Uint8List trustRoot,
  }) {
    final content = SealedSenderOuter.open(
      ciphertext: ciphertext,
      ourPrivate: PrivateKey.deserialize(bytes: _identity.privateKey.toList()),
      ourPublic: identityPublicKey,
    );
    final cert = content.senderCertificate;
    try {
      final expires = senderCertificateGetExpiration(certificate: cert);
      // Podpis trust rootem se ověřuje v okamžiku těsně před vypršením —
      // samotné stáří certifikátu řeší volající.
      final signed = validateSenderCertificate(
        certificate: cert,
        trustRoot: trustRoot,
        timestamp: expires - BigInt.one,
      );
      final key = senderCertificateGetKey(certificate: cert);
      if (!signed || !_bytesEqual(key, content.senderStaticKey)) {
        throw const FormatException('sender certificate not trusted');
      }
      return SepotSealedSender(
        name: senderCertificateGetSenderName(certificate: cert),
        deviceId: senderCertificateGetSenderDeviceId(certificate: cert),
        identityKey: Uint8List.fromList(key),
        certificateExpiresAtMs: expires.toInt(),
        messageType: content.messageType,
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('invalid sender certificate');
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
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

  /// Nový signed prekey (rotace). Starý zůstává ve store — relace založené
  /// z bundle těsně před rotací ho ještě potřebují.
  Future<SepotSignedPreKey> generateSignedPreKey({
    required int id,
    required int timestampMs,
  }) async {
    final identityPrivate = PrivateKey.deserialize(
      bytes: _identity.privateKey.toList(),
    );
    final private = PrivateKey.generate();
    final public = private.getPublicKey();
    final signature = identityPrivate.sign(
      message: public.serialize().toList(),
    );
    await _stores.signedPreKey.storeSignedPreKey(
      id,
      SignedPreKeyRecord(
        id: id,
        publicKey: public,
        privateKey: private,
        signature: signature.toList(),
        timestamp: BigInt.from(timestampMs),
      ),
    );
    return SepotSignedPreKey(
      id: id,
      publicKey: Uint8List.fromList(public.serialize().toList()),
      signature: Uint8List.fromList(signature.toList()),
    );
  }

  /// Nový last-resort Kyber prekey (rotace PQXDH kotvy).
  Future<SepotKyberPreKey> generateKyberPreKey({
    required int id,
    required int timestampMs,
  }) async {
    final identityPrivate = PrivateKey.deserialize(
      bytes: _identity.privateKey.toList(),
    );
    final keyPair = KyberKeyPair.generate();
    final public = keyPair.getPublicKey();
    final signature = identityPrivate.sign(
      message: public.serialize().toList(),
    );
    await _stores.kyberPreKey.storeKyberPreKey(
      id,
      KyberPreKeyRecord.create(
        id: id,
        keyPair: keyPair,
        signature: signature.toList(),
        timestamp: BigInt.from(timestampMs),
      ),
    );
    return SepotKyberPreKey(
      id: id,
      publicKey: Uint8List.fromList(public.serialize().toList()),
      signature: Uint8List.fromList(signature.toList()),
    );
  }
}

/// Zápisy jednoho dešifrování odložené na později ([SepotCrypto.sealedDecrypt]
/// s `beforeCommit`). Čtení jde do skutečných stores, ale vidí i vlastní
/// odložené zápisy; pořadí zápisů se při [commit] zachová.
class _StagedWrites implements SessionStore, IdentityKeyStore, PreKeyStore {
  _StagedWrites(this._real);

  final SepotStores _real;
  final _ops = <({Future<void> Function() apply, void Function() applySync})>[];
  final _sessions = <String, SessionRecord>{};
  final _identities = <String, PublicKey>{};
  final _removedPreKeys = <int>{};

  static String _key(ProtocolAddress a) => '${a.name()}.${a.deviceId()}';

  SealedSenderCipher cipher(ProtocolAddress local) => SealedSenderCipher(
        localAddress: local,
        sessionStore: this,
        identityKeyStore: this,
        preKeyStore: this,
        signedPreKeyStore: _real.signedPreKey,
        kyberPreKeyStore: _real.kyberPreKey,
      );

  Future<void> commit() async {
    for (final op in _ops) {
      await op.apply();
    }
    _ops.clear();
  }

  void commitSync() {
    for (final op in _ops) {
      op.applySync();
    }
    _ops.clear();
  }

  // ── SessionStore ──
  @override
  Future<SessionRecord?> loadSession(ProtocolAddress address) async =>
      _sessions[_key(address)] ?? await _real.session.loadSession(address);

  @override
  Future<void> storeSession(ProtocolAddress address, SessionRecord record) async {
    _sessions[_key(address)] = record;
    _ops.add((
      apply: () => _real.session.storeSession(address, record),
      applySync: () => (_real.session as SessionStoreSync)
          .storeSessionSync(address, record),
    ));
  }

  @override
  Future<bool> containsSession(ProtocolAddress address) async =>
      _sessions.containsKey(_key(address)) ||
      await _real.session.containsSession(address);

  @override
  Future<void> deleteSession(ProtocolAddress address) =>
      throw UnsupportedError('deleteSession during staged decrypt');

  @override
  Future<void> deleteAllSessions(String name) =>
      throw UnsupportedError('deleteAllSessions during staged decrypt');

  @override
  Future<List<int>> getSubDeviceSessions(String name) =>
      _real.session.getSubDeviceSessions(name);

  // ── IdentityKeyStore ──
  @override
  Future<IdentityKeyPair> getIdentityKeyPair() =>
      _real.identity.getIdentityKeyPair();

  @override
  Future<int> getLocalRegistrationId() =>
      _real.identity.getLocalRegistrationId();

  @override
  Future<bool> saveIdentity(ProtocolAddress address, PublicKey identityKey) async {
    final known = await getIdentity(address);
    _identities[address.name()] = identityKey;
    _ops.add((
      apply: () => _real.identity.saveIdentity(address, identityKey),
      applySync: () => (_real.identity as IdentityKeyStoreSync)
          .saveIdentitySync(address, identityKey),
    ));
    return known == null ||
        !SepotCrypto._bytesEqual(known.serialize(), identityKey.serialize());
  }

  @override
  Future<PublicKey?> getIdentity(ProtocolAddress address) async =>
      _identities[address.name()] ?? await _real.identity.getIdentity(address);

  @override
  Future<bool> isTrustedIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
    Direction direction,
  ) =>
      _real.identity.isTrustedIdentity(address, identityKey, direction);

  // ── PreKeyStore ──
  @override
  Future<PreKeyRecord?> loadPreKey(int preKeyId) async =>
      _removedPreKeys.contains(preKeyId)
          ? null
          : await _real.preKey.loadPreKey(preKeyId);

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      throw UnsupportedError('storePreKey during staged decrypt');

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      !_removedPreKeys.contains(preKeyId) &&
      await _real.preKey.containsPreKey(preKeyId);

  @override
  Future<void> removePreKey(int preKeyId) async {
    _removedPreKeys.add(preKeyId);
    _ops.add((
      apply: () => _real.preKey.removePreKey(preKeyId),
      applySync: () =>
          (_real.preKey as PreKeyStoreSync).removePreKeySync(preKeyId),
    ));
  }

  @override
  Future<List<int>> getAllPreKeyIds() async => [
        for (final id in await _real.preKey.getAllPreKeyIds())
          if (!_removedPreKeys.contains(id)) id,
      ];
}
