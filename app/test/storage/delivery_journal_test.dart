import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/storage/crypto_db.dart';

/// Deník příjmu a záznam odeslaných obálek.
void main() {
  late Directory tmp;
  late CryptoDb db;
  final rng = Random.secure();

  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sepot_denik');
    db = CryptoDb.open(path: '${tmp.path}/app.db', dek: bytes(32));
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Uint8List pending([Uint8List? uuid]) {
    final id = uuid ?? bytes(16);
    db.inboxPut(
      msgUuid: id,
      senderName: 'ab' * 16,
      senderDevice: 1,
      senderIdentity: bytes(33),
      plaintext: Uint8List.fromList([1, 2, 3]),
    );
    return id;
  }

  group('deník příjmu', () {
    test('vyřízená obálka si drží jen msg_uuid, obsah zmizí', () {
      final uuid = pending();
      expect(db.inboxPending().single.plaintext, [1, 2, 3]);

      db.inboxDone(uuid);
      final entry = db.inboxGet(uuid)!;
      expect(entry.done, isTrue);
      expect(entry.plaintext, isNull, reason: 'mizící zpráva nesmí přežít');
      expect(entry.senderIdentity, isNull);
      expect(db.inboxPending(), isEmpty);
    });

    test('zahozená obálka bez obsahu se taky pamatuje', () {
      final uuid = bytes(16);
      db.inboxDone(uuid);
      expect(db.inboxGet(uuid)!.done, isTrue);
    });

    test('čas příjmu jen na den', () {
      final uuid = pending();
      final at =
          db.raw.select('SELECT received_at FROM inbox WHERE msg_uuid = ?', [
                uuid,
              ]).first['received_at']
              as int;
      final t = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
      expect([t.hour, t.minute, t.second, t.millisecond], [0, 0, 0, 0]);
    });

    test('úklid maže jen vyřízené a staré, čerstvý obsah nechá', () {
      final old = bytes(16);
      db.inboxDone(old);
      final fresh = pending();
      final later = DateTime.now().add(const Duration(days: 2));
      db.inboxPurge(
        before: later,
        pendingBefore: later.subtract(const Duration(days: 7)),
      );
      expect(db.inboxGet(old), isNull);
      expect(
        db.inboxGet(fresh)!.plaintext,
        isNotNull,
        reason: 'nezpracovaný obsah má ještě šanci',
      );
    });

    test('obsah, který nejde zpracovat ani po týdnu, z disku zmizí', () {
      final stuck = pending();
      db.inboxPurge(
        before: DateTime.now().subtract(const Duration(days: 35)),
        pendingBefore: DateTime.now().add(const Duration(days: 2)),
      );
      final entry = db.inboxGet(stuck)!;
      expect(entry.plaintext, isNull);
      expect(
        entry.done,
        isTrue,
        reason: 'msg_uuid zůstává — redelivery se pozná bez dešifrování',
      );
    });

    test('pokusy o zpracování se počítají', () {
      final uuid = pending();
      expect(db.inboxAttempt(uuid), 1);
      expect(db.inboxAttempt(uuid), 2);
      expect(db.inboxAttempt(bytes(16)), 0, reason: 'neznámá obálka');
    });
  });

  group('odeslané obálky', () {
    void put(
      Uint8List uuid, {
      String contact = 'BOB',
      String conv = 'BOB',
      String target = 'm1',
      String kind = 'txt',
    }) => db.sentLogPut(
      msgUuid: uuid,
      contactId: contact,
      convId: conv,
      targetId: target,
      kind: kind,
    );

    test('o obálku si řekne jen její adresát, a jen jednou', () {
      final uuid = bytes(16);
      put(uuid);
      expect(
        db.sentLogTake(uuid, 'MALLORY'),
        isNull,
        reason: 'cizí kontakt nesmí vyvolat znovuposlání',
      );
      final entry = db.sentLogTake(uuid, 'BOB')!;
      expect(entry.targetId, 'm1');
      expect(entry.kind, 'txt');
      expect(db.sentLogTake(uuid, 'BOB'), isNull, reason: 'nanejvýš jednou');
    });

    test('záznam nenese obsah zprávy', () {
      final columns = {
        for (final r in db.raw.select('PRAGMA table_info(sent_log)'))
          r['name'] as String,
      };
      expect(columns, isNot(contains('content')));
    });

    test('počítá, kolikrát adresát touž zprávu nedokázal otevřít', () {
      final first = bytes(16);
      final second = bytes(16);
      final reaction = bytes(16);
      put(first);
      put(second);
      put(reaction, kind: 'rx');
      expect(db.sentLogTake(first, 'BOB')!.failures, 1);
      expect(db.sentLogTake(second, 'BOB')!.failures, 2);
      expect(
        db.sentLogTake(reaction, 'BOB')!.failures,
        1,
        reason: 'reakce k téže zprávě je jiná věc',
      );
    });

    test('neodeslaná obálka se nepočítá', () {
      final lost = bytes(16);
      final sent = bytes(16);
      put(lost);
      db.sentLogDrop(lost);
      put(sent);
      expect(db.sentLogTake(lost, 'BOB'), isNull);
      expect(db.sentLogTake(sent, 'BOB')!.failures, 1);
    });

    test('zmizelá zpráva, smazaný kontakt i skupina berou záznamy s sebou', () {
      final msg = bytes(16);
      final rx = bytes(16);
      final other = bytes(16);
      final contact = bytes(16);
      final inGroup = bytes(16);
      put(msg);
      put(rx, kind: 'rx');
      put(other, target: 'm2');
      put(contact, contact: 'CAROL', conv: 'CAROL');
      put(inGroup, contact: 'CAROL', conv: 'G1');

      db.sentLogForget('BOB', ['m1']);
      expect(db.sentLogTake(msg, 'BOB'), isNull);
      expect(db.sentLogTake(rx, 'BOB'), isNull);
      expect(db.sentLogTake(other, 'BOB'), isNotNull);

      db.contactDelete('CAROL');
      expect(db.sentLogTake(contact, 'CAROL'), isNull);
      put(inGroup, contact: 'DAVE', conv: 'G1');
      db.groupDelete('G1');
      expect(db.sentLogTake(inGroup, 'DAVE'), isNull);
    });

    test('úklid po době, kdy relay obálku ještě drží', () {
      final uuid = bytes(16);
      put(uuid);
      db.sentLogPurge(DateTime.now().add(const Duration(seconds: 1)));
      expect(db.sentLogTake(uuid, 'BOB'), isNull);
    });
  });

  group('transakce', () {
    test('vnořená transakce se vrací s vnější', () {
      expect(
        () => db.transaction(() {
          db.kvPut('a', Uint8List.fromList([1]));
          db.transaction(() => db.kvPut('b', Uint8List.fromList([2])));
          throw StateError('pád');
        }),
        throwsStateError,
      );
      expect(db.kvGet('a'), isNull);
      expect(db.kvGet('b'), isNull);
    });

    test('chyba vnořené transakce vrátí jen ji', () {
      db.transaction(() {
        db.kvPut('a', Uint8List.fromList([1]));
        expect(
          () => db.transaction(() {
            db.kvPut('b', Uint8List.fromList([2]));
            throw StateError('vnořená');
          }),
          throwsStateError,
        );
      });
      expect(db.kvGet('a'), [1]);
      expect(db.kvGet('b'), isNull);
    });
  });

  test('DB z prvních sestavení 1.2.5 se otevře a tabulky se srovnají', () {
    // Tvar deníku a záznamu odeslaných obálek z prvních sestavení 1.2.5.
    final dek = bytes(32);
    final path = '${tmp.path}/stara.db';
    final old = CryptoDb.open(path: path, dek: dek);
    final uuid = bytes(16);
    old.raw.execute('''
      DROP TABLE inbox;
      DROP TABLE sent_log;
      CREATE TABLE inbox (
        msg_uuid        BLOB PRIMARY KEY,
        sender_name     TEXT,
        sender_device   INTEGER,
        sender_identity BLOB,
        plaintext       BLOB,
        received_at     INTEGER NOT NULL,
        done_at         INTEGER
      );
      CREATE TABLE sent_log (
        msg_uuid   BLOB PRIMARY KEY,
        contact_id TEXT    NOT NULL,
        conv_id    TEXT    NOT NULL,
        message_id TEXT    NOT NULL,
        content    TEXT,
        sent_at    INTEGER NOT NULL,
        resends    INTEGER NOT NULL DEFAULT 0
      );
    ''');
    old.raw.execute(
      'INSERT INTO inbox (msg_uuid, sender_name, sender_device, '
      'sender_identity, plaintext, received_at) VALUES (?, ?, 1, ?, ?, 0)',
      [
        uuid,
        'ab' * 16,
        bytes(33),
        Uint8List.fromList([7]),
      ],
    );
    old.raw.execute(
      'INSERT INTO sent_log (msg_uuid, contact_id, conv_id, message_id, '
      "content, sent_at) VALUES (?, 'BOB', 'BOB', 'm1', '{\"t\":\"del\"}', 0)",
      [bytes(16)],
    );
    old.close();

    final db2 = CryptoDb.open(path: path, dek: dek);
    addTearDown(db2.close);
    expect(db2.inboxPending().single.plaintext, [
      7,
    ], reason: 'nezpracovaný obsah migrace nezahodí');
    expect(db2.inboxAttempt(uuid), 1);
    expect(
      db2.raw.select('SELECT COUNT(*) AS n FROM sent_log').first['n'],
      0,
      reason: 'starý záznam s obsahem zprávy je pryč',
    );
    final next = bytes(16);
    db2.sentLogPut(
      msgUuid: next,
      contactId: 'BOB',
      convId: 'BOB',
      targetId: 'm1',
      kind: 'txt',
    );
    expect(db2.sentLogTake(next, 'BOB')!.targetId, 'm1');
  });
}
