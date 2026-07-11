/// Lokální úložiště blobů příloh.
///
/// Na disku leží VŽDY jen šifrovaný blob (ciphertext || tag) pod názvem
/// blob_id — stejné bajty jako na relayi. At-rest ochrana = AES-256-GCM
/// per-file klíčem, který žije výhradně v SQLCipher DB (metadata zprávy).
/// Dešifruje se až při zobrazení, do paměti; plaintext se na disk dostane
/// jen krátkodobě při sdílení do jiné aplikace (viz UI vrstva).
///
/// blob_id přichází i od protistrany (remote input) — před použitím jako
/// název souboru se validuje tvar (32 hex znaků), žádný path traversal.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class AttachmentStore {
  AttachmentStore({String? dirOverride}) : _dirOverride = dirOverride;

  final String? _dirOverride;

  static final _blobIdPattern = RegExp(r'^[0-9a-f]{32}$');

  static bool isValidBlobId(String blobId) => _blobIdPattern.hasMatch(blobId);

  Future<Directory> _dir() async {
    final base = _dirOverride ??
        '${(await getApplicationSupportDirectory()).path}/attachments';
    return Directory(base).create(recursive: true);
  }

  Future<File> _file(String blobId) async {
    if (!isValidBlobId(blobId)) {
      throw ArgumentError.value(blobId, 'blobId', 'invalid blob_id format');
    }
    return File('${(await _dir()).path}/$blobId');
  }

  Future<void> save(String blobId, Uint8List blob) async {
    final file = await _file(blobId);
    // přes temp + rename, ať pád zápisu nenechá poloviční blob
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(blob, flush: true);
    await tmp.rename(file.path);
  }

  Future<bool> exists(String blobId) async => (await _file(blobId)).exists();

  /// Vrátí šifrovaný blob, nebo null, když (ještě) není stažený.
  Future<Uint8List?> load(String blobId) async {
    final file = await _file(blobId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(String blobId) async {
    final file = await _file(blobId);
    if (await file.exists()) await file.delete();
  }

  /// Factory reset — smaže celý adresář příloh.
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
