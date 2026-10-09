import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:base32/encodings.dart';
import 'package:pointycastle/digests/blake2b.dart';
import 'package:sepot/core/crypto/mnemonic.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';

/// Fingerprint identity — jediné user-facing ID Šepotu.
///
/// fingerprint = BLAKE2b-256( serializovaný identity pubkey, 33 B )
///
/// Zobrazuje se jako Crockford base32 (52 znaků), zkráceně „SEP-XXXXXXXXXX".
/// POZOR: NEPLÉST s `account_id` — to je náhodný 16B routing handle, který
/// přiděluje relay při registraci a nemá k identitě kryptografický vztah.
class SepotFingerprint {
  SepotFingerprint(this.bytes)
      : assert(bytes.length == 32, 'BLAKE2b-256 = 32 bytes');

  /// Spočítá fingerprint ze serializovaného veřejného identity klíče.
  factory SepotFingerprint.ofPublicKey(Uint8List identityPublicKey) {
    final digest = Blake2bDigest(digestSize: 32);
    return SepotFingerprint(digest.process(identityPublicKey));
  }

  final Uint8List bytes;

  /// Plné zobrazení — 52 znaků Crockford base32, bez paddingu.
  String get display =>
      base32.encode(bytes, encoding: Encoding.crockford).toUpperCase();

  /// UX zkratka do titulků, QR popisků a seznamů.
  String get short => 'SEP-${display.substring(0, 10)}';

  @override
  String toString() => display;

  @override
  bool operator ==(Object other) =>
      other is SepotFingerprint && display == other.display;

  @override
  int get hashCode => display.hashCode;
}

/// Lokální identita uživatele — identity keypair + zobrazované jméno.
///
/// Identita = klíč. Žádné UUID, žádný telefon, žádný e-mail. Obnova
/// přes 24slovný mnemonic (reverzibilní enkódování privátního klíče).
class LocalIdentity {
  LocalIdentity({
    required this.displayName,
    required this.identityPrivateKey,
    required this.identityPublicKey,
    required this.createdAt,
  }) : fingerprint = SepotFingerprint.ofPublicKey(identityPublicKey);

  final String displayName;

  /// 32 B, serializovaný (clampnutý). Nikdy neopouští zařízení jinak než
  /// jako mnemonic záloha uživatele. ZÁKAZ kopírování do schránky.
  final Uint8List identityPrivateKey;

  /// 33 B, serializovaný (libsignal type byte + 32 B).
  final Uint8List identityPublicKey;

  final DateTime createdAt;
  final SepotFingerprint fingerprint;

  /// Vytvoř novou identitu (onboarding).
  static Future<LocalIdentity> create(String displayName) async {
    final keys = SepotCrypto.generateIdentityKeys();
    return LocalIdentity(
      displayName: displayName,
      identityPrivateKey: keys.privateKey,
      identityPublicKey: keys.publicKey,
      createdAt: DateTime.now(),
    );
  }

  /// Obnov identitu z 24slovného mnemonic (recovery flow).
  ///
  /// Obnoví IDENTITU (stejný klíč → stejný fingerprint → „verified"
  /// kontakty drží), ne historii zpráv — ta je díky forward secrecy pryč
  /// a UI to musí říct.
  static Future<LocalIdentity> recover({
    required List<String> mnemonicWords,
    required String displayName,
  }) async {
    final privateKey = SepotMnemonic.decode(mnemonicWords);
    return LocalIdentity(
      displayName: displayName,
      identityPrivateKey: privateKey,
      identityPublicKey: SepotCrypto.derivePublicKey(privateKey),
      createdAt: DateTime.now(),
    );
  }

  /// 24 slov zálohy identity. Zobrazit jen v chráněném recovery UI.
  List<String> get mnemonic => SepotMnemonic.encode(identityPrivateKey);

  /// Kompatibilní alias — dřív tu bylo UUID, teď je ID totožné
  /// s fingerprintem (deterministicky z klíče).
  String get id => fingerprint.display;

  /// Šepot ID pro zobrazení v UI.
  String get sepotId => fingerprint.short;

  /// Veřejná identita (bezpečné ke sdílení).
  PublicIdentity get publicIdentity => PublicIdentity(
        displayName: displayName,
        identityKey: identityPublicKey,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'v': 2,
        'displayName': displayName,
        'identityPrivateKey': base64Encode(identityPrivateKey),
        'identityPublicKey': base64Encode(identityPublicKey),
        'createdAt': createdAt.toIso8601String(),
      };

  factory LocalIdentity.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 2) {
      throw const FormatException(
        'Unsupported identity format (pre-libsignal era) — new onboarding required',
      );
    }
    return LocalIdentity(
      displayName: json['displayName'] as String,
      identityPrivateKey: base64Decode(json['identityPrivateKey'] as String),
      identityPublicKey: base64Decode(json['identityPublicKey'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Veřejná identita — bezpečné ke sdílení, pro QR kódy a `sepot://` odkazy.
///
/// Vedle krypto identity (identity klíč → fingerprint) nese i ROUTING:
/// `accountId` (náhodný server handle — pojmenovává libsignal session
/// odesílatele, musí sedět se SenderCertificate) a `deliveryAddress`
/// (32B blind token, podle kterého relay směruje obálky). Bez nich nejde
/// kontaktu poslat první zpráva. Obě pole jsou náhodná — s identitou je
/// spojuje jen sám uživatel tím, že je sdílí ve svém odkazu.
class PublicIdentity {
  /// Nejvyšší délka jména z odkazu/QR — delší odkaz je vadný vstup.
  static const maxDisplayNameLength = 64;

  PublicIdentity({
    required this.displayName,
    required this.identityKey,
    required this.createdAt,
    this.accountId,
    this.deliveryAddress,
  }) : fingerprint = SepotFingerprint.ofPublicKey(identityKey);

  final String displayName;

  /// 33 B, serializovaný veřejný identity klíč.
  final Uint8List identityKey;

  final DateTime createdAt;
  final SepotFingerprint fingerprint;

  /// Hex accountId na relayi (null = ještě neregistrováno / neznámo).
  final String? accountId;

  /// 32 B routing token na relayi (null = neznámo).
  final Uint8List? deliveryAddress;

  static const _linkPrefix = 'sepot://add/';

  /// Kompatibilní alias na fingerprint (dřív UUID).
  String get id => fingerprint.display;

  /// Šepot ID pro zobrazení.
  String get sepotId => fingerprint.short;

  PublicIdentity withRouting({
    required String accountId,
    required Uint8List deliveryAddress,
  }) =>
      PublicIdentity(
        displayName: displayName,
        identityKey: identityKey,
        createdAt: createdAt,
        accountId: accountId,
        deliveryAddress: deliveryAddress,
      );

  /// Export jako `sepot://add/...` odkaz (obsah QR kódu i sdílený link).
  String toShareString() {
    final payload = base64UrlEncode(
      utf8.encode(jsonEncode({
        'v': 2,
        'n': displayName,
        'ik': base64Encode(identityKey),
        'ts': createdAt.toIso8601String(),
        if (accountId != null) 'aid': accountId,
        if (deliveryAddress != null) 'da': base64Encode(deliveryAddress!),
      })),
    );
    return '$_linkPrefix$payload';
  }

  /// Import z odkazu / QR. Vrací null, pokud vstup není platný.
  static PublicIdentity? fromShareString(String s) {
    try {
      var payload = s.trim();
      if (payload.startsWith(_linkPrefix)) {
        payload = payload.substring(_linkPrefix.length);
      }
      final map = jsonDecode(utf8.decode(base64Url.decode(payload)))
          as Map<String, dynamic>;
      if (map['v'] != 2) return null;
      final identityKey = base64Decode(map['ik'] as String);
      // 33 B = typový bajt 0x05 + Curve25519; jiný prefix libsignal odmítne
      // až při první zprávě, tady ho odmítneme hned.
      if (identityKey.length != 33 || identityKey[0] != 0x05) return null;
      final aid = map['aid'] as String?;
      // Relay dává 32 hex znaků; starší testovací odkazy kratší — hex a strop stačí.
      if (aid != null && !RegExp(r'^[0-9a-f]{8,64}$').hasMatch(aid)) return null;
      final rawName = (map['n'] as String).trim();
      if (rawName.length > maxDisplayNameLength) return null;
      final da = map['da'] as String?;
      Uint8List? deliveryAddress;
      if (da != null) {
        deliveryAddress = base64Decode(da);
        // deliveryAddress je 32B routing token — vadný odkaz odmítni
        // (stejně jako u identityKey), ať se do kontaktů nedostane nesmysl.
        if (deliveryAddress.length != 32) return null;
      }
      return PublicIdentity(
        displayName: rawName,
        identityKey: identityKey,
        createdAt: DateTime.parse(map['ts'] as String),
        accountId: aid,
        deliveryAddress: deliveryAddress,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'v': 2,
        'displayName': displayName,
        'identityKey': base64Encode(identityKey),
        'createdAt': createdAt.toIso8601String(),
        'accountId': accountId,
        'deliveryAddress':
            deliveryAddress == null ? null : base64Encode(deliveryAddress!),
      };

  factory PublicIdentity.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 2) {
      throw const FormatException('Unsupported contact format');
    }
    final da = json['deliveryAddress'] as String?;
    return PublicIdentity(
      displayName: json['displayName'] as String,
      identityKey: base64Decode(json['identityKey'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      accountId: json['accountId'] as String?,
      deliveryAddress: da == null ? null : base64Decode(da),
    );
  }
}
