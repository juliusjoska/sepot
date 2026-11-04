/// Vnější vrstva sealed senderu v1 — jen tolik, kolik je potřeba ke zjištění
/// odesílatele obálky, kterou se nepodařilo dešifrovat.
///
/// Balíček `libsignal` umí sealed sender jen vcelku: když selže vnitřní
/// Double Ratchet (chybí relace, duplicita, rozbitý stav), zahodí i už
/// ověřeného odesílatele a vrátí holý text chyby. Bez odesílatele nejde
/// požádat o obnovu relace a zpráva by zmizela potichu. Krok
/// `sealed_sender_decrypt_to_usmc` z libsignal (sealed_sender.rs, v0.96.4)
/// proto opakujeme tady: ECDH + HKDF-SHA256 + AES-256-CTR s HMAC-SHA256.
/// Ověření certifikátu proti trust rootu zůstává na libsignal.
///
/// Nic odsud se nepoužívá k dešifrování obsahu — vnitřní zprávu dál
/// otevírá výhradně libsignal.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal/libsignal.dart'
    show PrivateKey, PublicKey, hkdfDerive;
import 'package:pointycastle/export.dart'
    show
        AESEngine,
        HMac,
        KeyParameter,
        ParametersWithIV,
        SHA256Digest,
        SICStreamCipher;
import 'package:protobuf/protobuf.dart'
    show
        CodedBufferReader,
        WIRETYPE_LENGTH_DELIMITED,
        WIRETYPE_VARINT,
        getTagFieldNumber,
        getTagWireType;

/// Obsah vnější obálky (UnidentifiedSenderMessageContent).
class UnsealedContent {
  UnsealedContent({
    required this.messageType,
    required this.senderCertificate,
    required this.senderStaticKey,
  });

  /// 1 = PreKey zpráva, 2 = běžná zpráva (Whisper), viz sealed_sender.proto.
  final int messageType;

  /// Serializovaný SenderCertificate — ověřuje ho libsignal.
  final Uint8List senderCertificate;

  /// Identity klíč, kterým odesílatel obálku zapečetil. MAC vnitřní vrstvy
  /// ho dokazuje — padělat ho jde jen s privátním klíčem odesílatele.
  final Uint8List senderStaticKey;
}

class SealedSenderOuter {
  static const _v1Major = 1;
  static const _macLength = 10;
  static final _saltPrefix = utf8.encode('UnidentifiedDelivery');

  /// Otevře vnější vrstvu obálky určené identitě [ourPrivate]/[ourPublic].
  /// Cokoli jiného než platná obálka v1 pro tuhle identitu = [FormatException].
  static UnsealedContent open({
    required Uint8List ciphertext,
    required PrivateKey ourPrivate,
    required Uint8List ourPublic,
  }) {
    if (ciphertext.isEmpty) throw const FormatException('empty envelope');
    final major = ciphertext[0] >> 4;
    // Verze 0 libsignal přijímá jako v1; v2 (multi-recipient) Šepot neposílá.
    if (major != 0 && major != _v1Major) {
      throw FormatException('unsupported sealed sender version $major');
    }
    final outer = _fields(Uint8List.sublistView(ciphertext, 1));
    final ephemeral = outer[1];
    final encryptedStatic = outer[2];
    final encryptedMessage = outer[3];
    if (ephemeral == null ||
        encryptedStatic == null ||
        encryptedMessage == null) {
      throw const FormatException('incomplete sealed sender message');
    }

    final ephemeralKey = _publicKey(ephemeral);
    final ephemeralKeys = _derive(ourPrivate.agree(publicKey: ephemeralKey), [
      ..._saltPrefix,
      ...ourPublic,
      ...ephemeralKey.serialize(),
    ]);
    final staticKeyBytes = _openCtrHmac(
      encryptedStatic,
      ephemeralKeys.sublist(32, 64),
      ephemeralKeys.sublist(64, 96),
    );
    final staticKey = _publicKey(staticKeyBytes);
    final staticKeys = _derive(ourPrivate.agree(publicKey: staticKey), [
      ...ephemeralKeys.sublist(0, 32),
      ...encryptedStatic,
    ]);
    final usmc = _fields(
      _openCtrHmac(
        encryptedMessage,
        staticKeys.sublist(32, 64),
        staticKeys.sublist(64, 96),
      ),
    );

    final type = usmc[1];
    final certificate = usmc[2];
    if (type == null || certificate == null) {
      throw const FormatException('incomplete sealed sender content');
    }
    return UnsealedContent(
      messageType: type.isEmpty ? 0 : type.first,
      senderCertificate: certificate,
      senderStaticKey: Uint8List.fromList(staticKey.serialize()),
    );
  }

  static PublicKey _publicKey(List<int> bytes) {
    try {
      return PublicKey.deserialize(bytes: bytes);
    } on Object {
      throw const FormatException('invalid public key');
    }
  }

  /// HKDF-SHA256 na 96 B: chain ‖ cipher ‖ mac (EphemeralKeys/StaticKeys).
  static Uint8List _derive(List<int> secret, List<int> salt) => hkdfDerive(
    outputLength: 96,
    inputKeyMaterial: secret,
    salt: salt,
    info: const [],
  );

  /// aes256_ctr_hmacsha256_decrypt: poslední 10 B je zkrácený HMAC
  /// ciphertextu, CTR s nulovým čítačem.
  static Uint8List _openCtrHmac(
    Uint8List data,
    Uint8List cipherKey,
    Uint8List macKey,
  ) {
    if (data.length < _macLength) {
      throw const FormatException('truncated ciphertext');
    }
    final body = Uint8List.sublistView(data, 0, data.length - _macLength);
    final mac = (HMac(
      SHA256Digest(),
      64,
    )..init(KeyParameter(macKey))).process(body);
    var diff = 0;
    for (var i = 0; i < _macLength; i++) {
      diff |= mac[i] ^ data[body.length + i];
    }
    if (diff != 0) throw const FormatException('MAC verification failed');
    final ctr = SICStreamCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(cipherKey), Uint8List(16)));
    return ctr.process(body);
  }

  /// Pole protobuf zprávy podle čísla: length-delimited jako bajty, varint
  /// jako jednobajtová hodnota (stačí na enum typu zprávy). Ostatní přeskočí.
  static Map<int, Uint8List> _fields(Uint8List bytes) {
    final out = <int, Uint8List>{};
    final reader = CodedBufferReader(bytes);
    try {
      while (!reader.isAtEnd()) {
        final tag = reader.readTag();
        final field = getTagFieldNumber(tag);
        switch (getTagWireType(tag)) {
          case WIRETYPE_LENGTH_DELIMITED:
            out[field] = Uint8List.fromList(reader.readBytes());
          case WIRETYPE_VARINT:
            out[field] = Uint8List.fromList([reader.readInt32() & 0xff]);
          default:
            reader.skipField(tag);
        }
      }
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('invalid protobuf');
    }
    return out;
  }
}
