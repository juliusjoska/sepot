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
      _migrateDeliveryTables(db);
      db.execute(_deliverySchema);
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

  static const _deliverySchema = '''
    CREATE TABLE IF NOT EXISTS inbox (
      msg_uuid        BLOB PRIMARY KEY,
      sender_name     TEXT,
      sender_device   INTEGER,
      sender_identity BLOB,
      plaintext       BLOB,
      received_at     INTEGER NOT NULL,
      done_at         INTEGER,
      attempts        INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS sent_log (
      msg_uuid   BLOB PRIMARY KEY,
      contact_id TEXT    NOT NULL,
      conv_id    TEXT    NOT NULL,
      target_id  TEXT    NOT NULL,
      kind       TEXT    NOT NULL,
      sent_at    INTEGER NOT NULL,
      taken      INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS sent_log_target
      ON sent_log (conv_id, target_id);
  ''';

  /// Deník příjmu a záznam odeslaných obálek mají od prvních sestavení
  /// 1.2.5 jiný tvar. `CREATE TABLE IF NOT EXISTS` starou tabulku nechá
  /// a index nad chybějícím sloupcem pak shodí otevření celé DB — appka
  /// by nešla odemknout.
  static void _migrateDeliveryTables(Database db) {
    Set<String> columns(String table) => {
          for (final r in db.select('PRAGMA table_info($table)'))
            r['name'] as String,
        };
    final sent = columns('sent_log');
    // Pomocná data pro žádost o znovuposlání; ztratí se nejvýš možnost
    // znovu poslat zprávy odeslané před aktualizací.
    if (sent.isNotEmpty && !sent.contains('target_id')) {
      db.execute('DROP TABLE sent_log;');
    }
    final inbox = columns('inbox');
    if (inbox.isNotEmpty && !inbox.contains('attempts')) {
      db.execute(
          'ALTER TABLE inbox ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;');
    }
  }

  Database get raw => _db;

  /// Atomický blok — ratchet stavy se smí zapisovat jen takhle. Uvnitř jiné
  /// transakce se vnoří jako savepoint: store relací zapisuje transakcí
  /// i tehdy, když ho uložení dešifrované obálky volá uvnitř větší.
  T transaction<T>(T Function() body) {
    if (!_db.autocommit) {
      _db.execute('SAVEPOINT nested;');
      try {
        final result = body();
        _db.execute('RELEASE nested;');
        return result;
      } catch (_) {
        _db.execute('ROLLBACK TO nested;');
        _db.execute('RELEASE nested;');
        rethrow;
      }
    }
    _db.execute('BEGIN IMMEDIATE;');
    try {
      final result = body();
      _db.execute('COMMIT;');
      return result;
    } catch (_) {
      _rollback();
      rethrow;
    }
  }

  /// Některé chyby (plný disk, I/O) transakci v SQLite zruší samy; druhý
  /// ROLLBACK by pak původní chybu přebil.
  void _rollback() {
    if (!_db.autocommit) _db.execute('ROLLBACK;');
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
      _db.execute(
          'DELETE FROM sent_log WHERE contact_id = ? OR conv_id = ?', [id, id]);
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
      _db.execute('DELETE FROM sent_log WHERE conv_id = ?', [id]);
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

  // ── Deník příjmu ────────────────────────────────────────────────────
  //
  // Obsah dešifrované obálky se zapíše DŘÍV, než se posune ratchet, a do
  // zpracování v deníku zůstane. Po zpracování zůstane jen msg_uuid: relay
  // obálku, jejíž ACK se ztratil, pošle znovu a ta se pozná bez dešifrování.

  InboxEntry? inboxGet(List<int> msgUuid) {
    final rows = _db.select('SELECT * FROM inbox WHERE msg_uuid = ?',
        [Uint8List.fromList(msgUuid)]);
    return rows.isEmpty ? null : InboxEntry._(rows.first);
  }

  void inboxPut({
    required List<int> msgUuid,
    required String senderName,
    required int senderDevice,
    required Uint8List senderIdentity,
    required Uint8List plaintext,
  }) {
    _db.execute(
      'INSERT INTO inbox (msg_uuid, sender_name, sender_device, '
      'sender_identity, plaintext, received_at) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(msg_uuid) DO NOTHING',
      [
        Uint8List.fromList(msgUuid),
        senderName,
        senderDevice,
        senderIdentity,
        plaintext,
        _today(),
      ],
    );
  }

  /// Čas příjmu jen na den: deník slouží k úklidu, přesný čas, kdy kdo
  /// komu psal, v něm nemá co dělat.
  static int _today() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  /// Obálka je vyřízená (uložená, nebo vědomě zahozená). Obsah se maže
  /// hned — mizící zpráva nesmí přežít v deníku.
  void inboxDone(List<int> msgUuid) {
    final today = _today();
    _db.execute(
      'INSERT INTO inbox (msg_uuid, received_at, done_at) VALUES (?, ?, ?) '
      'ON CONFLICT(msg_uuid) DO UPDATE SET plaintext = NULL, '
      'sender_name = NULL, sender_device = NULL, sender_identity = NULL, '
      'done_at = excluded.done_at',
      [Uint8List.fromList(msgUuid), today, today],
    );
  }

  /// Započítá další pokus o zpracování nevyřízené obálky a vrátí, kolikátý
  /// to je.
  int inboxAttempt(List<int> msgUuid) {
    final key = Uint8List.fromList(msgUuid);
    _db.execute(
        'UPDATE inbox SET attempts = attempts + 1 WHERE msg_uuid = ?', [key]);
    final rows =
        _db.select('SELECT attempts FROM inbox WHERE msg_uuid = ?', [key]);
    return rows.isEmpty ? 0 : rows.first['attempts'] as int;
  }

  List<InboxEntry> inboxPending() => [
        for (final r in _db.select(
            'SELECT * FROM inbox WHERE done_at IS NULL ORDER BY received_at'))
          InboxEntry._(r),
      ];

  /// Vyřízené záznamy starší než [before] pryč (relay po 30 dnech obálku
  /// stejně zahodí, takže redelivery už nepřijde). Nevyřízené starší než
  /// [pendingBefore] se vyřídí: obsah, který nejde zpracovat ani po dnech,
  /// nesmí ležet na disku napořád.
  void inboxPurge({required DateTime before, required DateTime pendingBefore}) {
    transaction(() {
      _db.execute(
          'DELETE FROM inbox WHERE done_at IS NOT NULL AND done_at < ?',
          [before.millisecondsSinceEpoch]);
      _db.execute(
          'UPDATE inbox SET plaintext = NULL, sender_name = NULL, '
          'sender_device = NULL, sender_identity = NULL, done_at = ? '
          'WHERE done_at IS NULL AND received_at < ?',
          [_today(), pendingBefore.millisecondsSinceEpoch]);
    });
  }

  // ── Odeslané obálky (pro žádost o znovuposlání) ─────────────────────
  //
  // Jen odkaz (druh a id zprávy, které se obálka týká), nikdy obsah: při
  // znovuposlání se obsah sestaví z aktuálního stavu konverzace, takže
  // smazaná, upravená nebo zmizelá zpráva nikam nejde v původní podobě.

  void sentLogPut({
    required List<int> msgUuid,
    required String contactId,
    required String convId,
    required String targetId,
    required String kind,
  }) {
    _db.execute(
      'INSERT INTO sent_log (msg_uuid, contact_id, conv_id, target_id, kind, '
      'sent_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(msg_uuid) DO NOTHING',
      [
        Uint8List.fromList(msgUuid),
        contactId,
        convId,
        targetId,
        kind,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  /// Obálka se k relayi nedostala — záznam by jinak počítal pokus, který
  /// příjemce nikdy neviděl.
  void sentLogDrop(List<int> msgUuid) {
    _db.execute('DELETE FROM sent_log WHERE msg_uuid = ?',
        [Uint8List.fromList(msgUuid)]);
  }

  /// Vyzvedne záznam obálky poslané [contactId]; o jednu obálku se žádá
  /// nanejvýš jednou. Obálka jiného adresáta = null: o cizí zprávu si nikdo
  /// říct nesmí. Záznam zůstává (jako vyzvednutý), aby šlo spočítat, kolik
  /// obálek s touž věcí adresát už nedokázal otevřít.
  SentLogEntry? sentLogTake(List<int> msgUuid, String contactId) {
    final key = Uint8List.fromList(msgUuid);
    final rows = _db.select(
        'SELECT * FROM sent_log WHERE msg_uuid = ? AND contact_id = ? '
        'AND taken = 0',
        [key, contactId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    _db.execute('UPDATE sent_log SET taken = 1 WHERE msg_uuid = ?', [key]);
    final failures = _db.select(
        'SELECT COUNT(*) AS n FROM sent_log WHERE contact_id = ? '
        'AND conv_id = ? AND target_id = ? AND kind = ? AND taken = 1',
        [contactId, r['conv_id'], r['target_id'], r['kind']]).first['n'] as int;
    return SentLogEntry._(r, failures);
  }

  /// Zpráva zmizela (mizící zprávy) — záznamy o ní ani o reakcích či
  /// úpravách k ní nesmí přežít.
  void sentLogForget(String convId, Iterable<String> targetIds) {
    final ids = targetIds.toList();
    if (ids.isEmpty) return;
    _db.execute(
      'DELETE FROM sent_log WHERE conv_id = ? AND target_id IN '
      '(${List.filled(ids.length, '?').join(', ')})',
      [convId, ...ids],
    );
  }

  void sentLogPurge(DateTime before) {
    _db.execute('DELETE FROM sent_log WHERE sent_at < ?',
        [before.millisecondsSinceEpoch]);
  }

  void close() => _db.close();
}

class InboxEntry {
  InboxEntry._(Row r)
      : msgUuid = r['msg_uuid'] as Uint8List,
        senderName = r['sender_name'] as String?,
        senderDevice = r['sender_device'] as int?,
        senderIdentity = r['sender_identity'] as Uint8List?,
        plaintext = r['plaintext'] as Uint8List?,
        done = r['done_at'] != null;

  final Uint8List msgUuid;
  final String? senderName;
  final int? senderDevice;
  final Uint8List? senderIdentity;
  final Uint8List? plaintext;
  final bool done;
}

class SentLogEntry {
  SentLogEntry._(Row r, this.failures)
      : convId = r['conv_id'] as String,
        targetId = r['target_id'] as String,
        kind = r['kind'] as String,
        sentAt = DateTime.fromMillisecondsSinceEpoch(r['sent_at'] as int);

  final String convId;

  /// Id zprávy (`txt`/`att`), cílové zprávy řídicí zprávy, nebo konverzace
  /// (`tmr`).
  final String targetId;

  /// Typ obsahu obálky (`t`).
  final String kind;
  final DateTime sentAt;

  /// Kolik obálek s touž věcí adresát nedokázal otevřít, včetně této.
  final int failures;
}
