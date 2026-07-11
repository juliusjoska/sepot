import 'dart:convert';
import 'dart:typed_data';

/// Stav přenosu přílohy — čistě lokální (na drát nikdy nejde).
enum AttachmentTransferState {
  /// Přijatá zpráva, blob se ještě nezačal stahovat.
  pending,
  downloading,

  /// Blob leží (šifrovaný) v lokálním AttachmentStore.
  ready,

  /// Download/ověření selhalo — UI nabídne opakování.
  failed,
}

/// Metadata přílohy. Klíč/nonce/digest dorazily E2E kanálem (relay je
/// nevidí); v lokální DB žijí uvnitř SQLCipher, takže at-rest jsou
/// chráněné stejně jako zbytek zpráv.
///
/// Wire tvar (pole `att` v content JSON, krátké klíče kvůli obálce):
///   { bid, k, n, d, s, mime, name?, w?, h?, th? }
class AttachmentMeta {
  const AttachmentMeta({
    required this.blobId,
    required this.keyB64,
    required this.nonceB64,
    required this.digestB64,
    required this.size,
    required this.mime,
    this.name,
    this.width,
    this.height,
    this.thumbB64,
    this.durationMs,
    this.state = AttachmentTransferState.pending,
  });

  final String blobId; // 32 hex znaků (id na relayi i lokálně)
  final String keyB64; // 32 B per-file AES klíč
  final String nonceB64; // 12 B GCM nonce
  final String digestB64; // SHA-256 šifrovaného blobu
  final int size; // velikost PLAINTEXTU v bajtech
  final String mime;
  final String? name; // původní název souboru (dokumenty)
  final int? width; // rozměry obrázku
  final int? height;
  final String? thumbB64; // JPEG náhled — jede UVNITŘ E2E plaintextu
  final int? durationMs; // délka hlasové zprávy / audia
  final AttachmentTransferState state;

  bool get isImage => mime.startsWith('image/');
  bool get isAudio => mime.startsWith('audio/');

  Uint8List get key => base64Decode(keyB64);
  Uint8List get nonce => base64Decode(nonceB64);
  Uint8List get digest => base64Decode(digestB64);
  Uint8List? get thumbnail =>
      thumbB64 == null ? null : base64Decode(thumbB64!);

  AttachmentMeta copyWith({AttachmentTransferState? state}) {
    return AttachmentMeta(
      blobId: blobId,
      keyB64: keyB64,
      nonceB64: nonceB64,
      digestB64: digestB64,
      size: size,
      mime: mime,
      name: name,
      width: width,
      height: height,
      thumbB64: thumbB64,
      durationMs: durationMs,
      state: state ?? this.state,
    );
  }

  /// Do content JSON zprávy (bez lokálního stavu).
  Map<String, dynamic> toWire() => {
        'bid': blobId,
        'k': keyB64,
        'n': nonceB64,
        'd': digestB64,
        's': size,
        'mime': mime,
        if (name != null) 'name': name,
        if (width != null) 'w': width,
        if (height != null) 'h': height,
        if (thumbB64 != null) 'th': thumbB64,
        if (durationMs != null) 'dur': durationMs,
      };

  /// Z content JSON příchozí zprávy. Remote input — tvary se validují
  /// (blob_id formát hlídá AttachmentStore, tady rozsahy a typy).
  factory AttachmentMeta.fromWire(Map<String, dynamic> wire) {
    final size = wire['s'] as int;
    if (size <= 0 || size > 512 * 1024 * 1024) {
      throw const FormatException('implausible attachment size');
    }
    return AttachmentMeta(
      blobId: wire['bid'] as String,
      keyB64: wire['k'] as String,
      nonceB64: wire['n'] as String,
      digestB64: wire['d'] as String,
      size: size,
      mime: wire['mime'] as String,
      name: wire['name'] as String?,
      width: wire['w'] as int?,
      height: wire['h'] as int?,
      thumbB64: wire['th'] as String?,
      durationMs: wire['dur'] as int?,
      state: AttachmentTransferState.pending,
    );
  }

  /// Lokální perzistence (SQLCipher) — wire tvar + stav.
  Map<String, dynamic> toJson() => {
        ...toWire(),
        'state': state.name,
      };

  factory AttachmentMeta.fromJson(Map<String, dynamic> json) {
    final base = AttachmentMeta.fromWire(json);
    final stateName = json['state'] as String?;
    return base.copyWith(
      state: AttachmentTransferState.values.asNameMap()[stateName] ??
          AttachmentTransferState.pending,
    );
  }
}
