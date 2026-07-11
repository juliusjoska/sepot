/// Šifrovaná lokální DB (SQLCipher) — krypto stavy i aplikační data.
///
/// Drží ratchet sessiony, prekeys, identity protistran a dále i kontakty,
/// konverzace se zprávami a nastavení (dřív plain Hive — nepřijatelné pro
/// privacy app). VLASTNÍ identity privátní klíč tu NENÍ — žije v OS keystore
/// (flutter_secure_storage), stejně jako DEK téhle databáze (obrana do
/// hloubky).
///
/// Nativní knihovnu (libsqlcipher) dodává build hook balíčku `sqlite3`
/// (pubspec: `hooks.user_defines.sqlite3.source: sqlcipher`) — jednotně
/// pro Android, iOS, desktop i testy na Linuxu.
///
/// Zápisy ratchet stavů jsou atomické (SQLite transakce + WAL) — neatomický
/// zápis session recordu = „bad MAC" a rozbitá konverzace.
library;

import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

class CryptoDb {
  CryptoDb._(this._db);

  final Database _db;

  /// Otevře (a případně založí) šifrovanou DB.
  ///
  /// [dek] je 32B klíč z OS keystore. Špatný klíč = [SqliteException]
  /// hned při první query (SQLCipher nerozliší „špatný klíč" od
  /// „poškozený soubor").
  static CryptoDb open({required String path, required Uint8List dek}) {
    if (dek.length != 32) {
      throw ArgumentError.value(dek.length, 'dek', 'DEK must be 32 bytes');
    }
    final db = sqlite3.open(path);
    try {
      // Pojistka: kdyby build přilinkl plain sqlite3 místo SQLCipher,
      // DB by se TIŠE založila nešifrovaná. To se nikdy nesmí stát.
      final cipherVersion = db.select('PRAGMA cipher_version;');
      if (cipherVersion.isEmpty) {
        throw StateError(
          'Native library is not SQLCipher — at-rest encryption would not run. '
          'Check hooks.user_defines.sqlite3.source in pubspec.yaml.',
        );
      }
      final hexKey =
          dek.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      // PRAGMA key s raw klíčem (x'..' formát) — žádné KDF ze stringu
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('PRAGMA foreign_keys = ON;');
      // První dotaz ověří klíč — na špatném klíči vyhodí NOTADB
      db.execute(_schema);
      return CryptoDb._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static const _schema = '''
    CREATE TABLE IF NOT EXISTS kv (
      k TEXT PRIMARY KEY,
      v BLOB NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      name      TEXT    NOT NULL,
      device_id INTEGER NOT NULL,
      record    BLOB    NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (name, device_id)
    );
    CREATE TABLE IF NOT EXISTS remote_identities (
      name      TEXT PRIMARY KEY,
      identity  BLOB NOT NULL,
      first_seen INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS prekeys (
      id     INTEGER PRIMARY KEY,
      record BLOB NOT NULL
    );
    CREATE TABLE IF NOT EXISTS signed_prekeys (
      id     INTEGER PRIMARY KEY,
      record BLOB NOT NULL
    );
    CREATE TABLE IF NOT EXISTS kyber_prekeys (
      id     INTEGER PRIMARY KEY,
      record BLOB NOT NULL,
      used   INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS contacts (
      id   TEXT PRIMARY KEY,
      json TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS conversations (
      contact_id TEXT PRIMARY KEY,
      json       TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS app_settings (
      k TEXT PRIMARY KEY,
      v TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS groups (
      id   TEXT PRIMARY KEY,
      json TEXT NOT NULL
    );
  ''';

  Database get raw => _db;

  /// Atomický blok — ratchet stavy se smí zapisovat jen takhle.
  T transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      final result = body();
      _db.execute('COMMIT;');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Uint8List? kvGet(String key) {
    final rows = _db.select('SELECT v FROM kv WHERE k = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['v'] as Uint8List;
  }

  void kvPut(String key, Uint8List value) {
    _db.execute(
      'INSERT INTO kv (k, v) VALUES (?, ?) '
      'ON CONFLICT(k) DO UPDATE SET v = excluded.v',
      [key, value],
    );
  }

  // ── Aplikační data — modely jako JSON, (de)serializuje volající ──

  List<String> contactsJsonAll() {
    final rows = _db.select('SELECT json FROM contacts');
    return [for (final r in rows) r['json'] as String];
  }

  void contactPut(String id, String json) {
    _db.execute(
      'INSERT INTO contacts (id, json) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET json = excluded.json',
      [id, json],
    );
  }

  /// Smaže kontakt VČETNĚ jeho konverzace (atomicky).
  void contactDelete(String id) {
    transaction(() {
      _db.execute('DELETE FROM contacts WHERE id = ?', [id]);
      _db.execute('DELETE FROM conversations WHERE contact_id = ?', [id]);
    });
  }

  String? conversationJson(String contactId) {
    final rows = _db.select(
      'SELECT json FROM conversations WHERE contact_id = ?',
      [contactId],
    );
    if (rows.isEmpty) return null;
    return rows.first['json'] as String;
  }

  List<String> conversationsJsonAll() {
    final rows = _db.select('SELECT json FROM conversations');
    return [for (final r in rows) r['json'] as String];
  }

  void conversationPut(String contactId, String json) {
    _db.execute(
      'INSERT INTO conversations (contact_id, json) VALUES (?, ?) '
      'ON CONFLICT(contact_id) DO UPDATE SET json = excluded.json',
      [contactId, json],
    );
  }

  List<String> groupsJsonAll() {
    final rows = _db.select('SELECT json FROM groups');
    return [for (final r in rows) r['json'] as String];
  }

  String? groupJson(String id) {
    final rows = _db.select('SELECT json FROM groups WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return rows.first['json'] as String;
  }

  void groupPut(String id, String json) {
    _db.execute(
      'INSERT INTO groups (id, json) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET json = excluded.json',
      [id, json],
    );
  }

  /// Smaže skupinu VČETNĚ její konverzace (atomicky).
  void groupDelete(String id) {
    transaction(() {
      _db.execute('DELETE FROM groups WHERE id = ?', [id]);
      _db.execute('DELETE FROM conversations WHERE contact_id = ?', [id]);
    });
  }

  String? appSettingGet(String key) {
    final rows = _db.select('SELECT v FROM app_settings WHERE k = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['v'] as String;
  }

  void appSettingPut(String key, String value) {
    _db.execute(
      'INSERT INTO app_settings (k, v) VALUES (?, ?) '
      'ON CONFLICT(k) DO UPDATE SET v = excluded.v',
      [key, value],
    );
  }

  void close() => _db.close();
}
