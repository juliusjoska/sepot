import 'dart:convert';
import 'dart:typed_data';

import 'package:sepot/core/crypto/attachment_cipher.dart';
import 'package:sepot/core/storage/attachment_store.dart';

/// Odkaz na profilovou fotku: šifrovaný blob na relayi + klíč k němu.
///
/// Fotka sama nejde v každé zprávě — v profilu `p` cestuje jen tenhle
/// odkaz (pár set bajtů). Příjemce blob stáhne jednou, ověří digest
/// a drží si ho šifrovaný u sebe.
class AvatarRef {
  const AvatarRef({
    required this.blobId,
    required this.key,
    required this.nonce,
    required this.digest,
    this.uploadedAt,
  });

  /// Profilová fotka je malá (256 px JPEG) — cokoli většího je podvrh.
  static const maxBlobBytes = 256 * 1024;

  final String blobId;
  final Uint8List key;
  final Uint8List nonce;
  final Uint8List digest;

  /// Kdy jsem blob nahrál (jen u vlastní fotky — kvůli obnově před
  /// vypršením na relayi).
  final DateTime? uploadedAt;

  Map<String, dynamic> toWire() => {
        'b': blobId,
        'k': base64Encode(key),
        'n': base64Encode(nonce),
        'd': base64Encode(digest),
      };

  /// Odkaz od protistrany; cokoli podezřelého = null (fotka se neukáže).
  static AvatarRef? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final b = raw['b'];
    if (b is! String || !AttachmentStore.isValidBlobId(b)) return null;
    try {
      final key = base64Decode(raw['k'] as String);
      final nonce = base64Decode(raw['n'] as String);
      final digest = base64Decode(raw['d'] as String);
      if (key.length != AttachmentCipher.keyLength ||
          nonce.length != AttachmentCipher.nonceLength ||
          digest.length != 32) {
        return null;
      }
      return AvatarRef(blobId: b, key: key, nonce: nonce, digest: digest);
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        ...toWire(),
        if (uploadedAt != null) 'u': uploadedAt!.millisecondsSinceEpoch,
      };

  static AvatarRef? fromJson(Object? raw) {
    final ref = fromWire(raw);
    if (ref == null || raw is! Map) return ref;
    final u = raw['u'];
    return u is int
        ? AvatarRef(
            blobId: ref.blobId,
            key: ref.key,
            nonce: ref.nonce,
            digest: ref.digest,
            uploadedAt: DateTime.fromMillisecondsSinceEpoch(u),
          )
        : ref;
  }
}
