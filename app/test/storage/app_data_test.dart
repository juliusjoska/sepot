import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/message.dart';

/// S9: aplikační data (konverzace, zprávy, nastavení) žijí v SQLCipher DB,
/// ne v plain Hive. Testuje se DB vrstva i service nad ní (debugAttachDb —
/// OS keystore na Linux VM není).
void main() {
  late Directory tmp;
  late CryptoDb db;
  late SecureStorageService storage;
  final rng = Random.secure();

  Uint8List randomDek() =>
      Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sepot_s9_test');
    db = CryptoDb.open(path: '${tmp.path}/app.db', dek: randomDek());
    storage = SecureStorageService(dbPath: '${tmp.path}/app.db')
      ..debugAttachDb(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('zamčený storage nedá data — StateError, žádný tichý fallback', () {
    final locked = SecureStorageService(dbPath: '${tmp.path}/locked.db');
    expect(() => locked.db, throwsStateError);
    expect(locked.isUnlocked, isFalse);
  });

  test('zprávy uložené přes addMessage přežijí reopen DB', () async {
    final msg = Message.text(
      senderId: 'alice',
      recipientId: 'bob',
      content: 'Tajná zpráva',
    );
    await storage.addMessage('bob', msg);

    // reopen — data musí přijít z disku, ne z paměti
    final path = '${tmp.path}/reopen.db';
    final dek = randomDek();
    final db1 = CryptoDb.open(path: path, dek: dek);
    final s1 = SecureStorageService(dbPath: path)..debugAttachDb(db1);
    await s1.addMessage('bob', msg);
    db1.close();

    final db2 = CryptoDb.open(path: path, dek: dek);
    final s2 = SecureStorageService(dbPath: path)..debugAttachDb(db2);
    final conv = await s2.loadConversation('bob');
    expect(conv, isNotNull);
    expect(conv!.messages.single.content, 'Tajná zpráva');
    db2.close();
  });

  test('DB soubor neobsahuje plaintext obsahu zpráv', () async {
    await storage.addMessage(
      'bob',
      Message.text(
        senderId: 'alice',
        recipientId: 'bob',
        content: 'NAJDI-MELESS-TOKEN',
      ),
    );
    // WAL checkpoint, ať je obsah v hlavním souboru
    db.raw.execute('PRAGMA wal_checkpoint(TRUNCATE);');

    final bytes = File('${tmp.path}/app.db').readAsBytesSync();
    expect(
      String.fromCharCodes(bytes).contains('NAJDI-MELESS-TOKEN'),
      isFalse,
      reason: 'Obsah zprávy je na disku čitelný = at-rest šifrování neběží!',
    );
  });

  test('konverzace se řadí podle poslední aktivity', () async {
    await storage.saveConversation(
      Conversation(
        contactId: 'stary',
        lastActivity: DateTime(2026, 1, 1),
      ),
    );
    await storage.saveConversation(
      Conversation(
        contactId: 'novy',
        lastActivity: DateTime(2026, 7, 1),
      ),
    );

    final list = await storage.loadConversations();
    expect(list.map((c) => c.contactId).toList(), ['novy', 'stary']);
  });

  test('smazání kontaktu smaže i jeho konverzaci (atomicky)', () async {
    db.contactPut('bob', '{"id":"bob"}');
    db.conversationPut('bob', '{"contactId":"bob","messages":[],'
        '"lastActivity":"2026-07-03T00:00:00.000"}');

    db.contactDelete('bob');

    expect(db.contactsJsonAll(), isEmpty);
    expect(db.conversationJson('bob'), isNull);
  });

  test('nastavení: JSON roundtrip přes app_settings', () async {
    await storage.setSetting('disappearing_seconds', 86400);
    await storage.setSetting('theme', 'dark');

    expect(await storage.getSetting<int>('disappearing_seconds'), 86400);
    expect(await storage.getSetting<String>('theme'), 'dark');
    expect(await storage.getSetting<String>('neexistuje'), isNull);
  });
}
