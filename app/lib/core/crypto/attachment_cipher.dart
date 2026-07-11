/// Šifrování příloh (model Signal).
///
/// Každá příloha má vlastní náhodný klíč: soubor se zašifruje
/// AES-256-GCM, na relay jde UŽ ŠIFROVANÝ blob a klíč + nonce + digest
/// putují k příjemci uvnitř E2E zprávy (relay je nikdy nevidí).
///
/// Wire formát blobu: `ciphertext || GCM tag (16 B)`.
/// Digest = SHA-256 celého blobu — váže zprávu na konkrétní bajty na
/// relayi (relay nemůže blob vyměnit) a příjemce jím ověří stažená data
/// ještě PŘED dešifrováním.
///
/// Šifrování i dešifrování běží v samostatném isolate — soubory mají
/// megabajty a čistě dartový AES by jinak blokoval UI.
library;

import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Blob nesedí (digest mismatch / GCM tag fail) — poškozená nebo
/// podvržená příloha. Nikdy nepředávat obsah dál.
class AttachmentIntegrityException implements Exception {
  const AttachmentIntegrityException(this.reason);

  final String reason;

  @override
  String toString() => 'AttachmentIntegrityException: $reason';
}

/// Výsledek zašifrování přílohy — vše, co potřebuje odesílatel:
/// [blob] se nahraje na relay, zbytek jde do E2E zprávy.
class EncryptedAttachment {
  const EncryptedAttachment({
    required this.key,
    required this.nonce,
    required this.blob,
    required this.digest,
    required this.plaintextSize,
  });

  final Uint8List key; // 32 B, per-file
  final Uint8List nonce; // 12 B
  final Uint8List blob; // ciphertext || tag
  final Uint8List digest; // SHA-256(blob)
  final int plaintextSize;
}

class AttachmentCipher {
  AttachmentCipher._();

  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int tagLength = 16;

  static Future<EncryptedAttachment> encrypt(Uint8List plaintext) async {
    if (plaintext.isEmpty) {
      throw ArgumentError('empty attachment');
    }
    final key = _randomBytes(keyLength);
    final nonce = _randomBytes(nonceLength);

    final blob = await Isolate.run(() async {
      final aes = AesGcm.with256bits();
      final box = await aes.encrypt(
        plaintext,
        secretKey: SecretKey(key),
        nonce: nonce,
      );
      final out = Uint8List(box.cipherText.length + box.mac.bytes.length);
      out.setAll(0, box.cipherText);
      out.setAll(box.cipherText.length, box.mac.bytes);
      return out;
    });

    return EncryptedAttachment(
      key: key,
      nonce: nonce,
      blob: blob,
      digest: await sha256(blob),
      plaintextSize: plaintext.length,
    );
  }

  /// Digest se ověřuje PŘED dešifrováním (stažený blob nemusí být ten,
  /// na který zpráva ukazuje); GCM tag pak autentizuje obsah klíčem.
  static Future<Uint8List> decrypt({
    required Uint8List blob,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List expectedDigest,
  }) async {
    if (blob.length <= tagLength) {
      throw const AttachmentIntegrityException('blob too short');
    }
    final actualDigest = await sha256(blob);
    if (!_bytesEqual(actualDigest, expectedDigest)) {
      throw const AttachmentIntegrityException('digest mismatch');
    }

    try {
      final plaintext = await Isolate.run(() async {
        final aes = AesGcm.with256bits();
        final cipherText = blob.sublist(0, blob.length - tagLength);
        final mac = Mac(blob.sublist(blob.length - tagLength));
        final out = await aes.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: mac),
          secretKey: SecretKey(key),
        );
        return Uint8List.fromList(out);
      });
      return plaintext;
    } on SecretBoxAuthenticationError {
      throw const AttachmentIntegrityException('GCM tag mismatch');
    }
  }

  static Future<Uint8List> sha256(Uint8List data) async {
    final hash = await Sha256().hash(data);
    return Uint8List.fromList(hash.bytes);
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
