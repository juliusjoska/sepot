// Needs the native libsignal library (FFI); skipped on builders without it (--exclude-tags ffi).
@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/message.dart';

/// Časovač mizících zpráv platí pro celou konverzaci: změna jde řídicí
/// zprávou `tmr` protistraně / členům, ti ji převezmou a zapíšou oznámení.
/// Řídicí zprávy, které shodila síť, čekají ve frontě na další připojení.
/// Relay nahrazuje přímé předání obsahu mezi „telefony“ (debugSendTap).
void main() {
  final rng = Random.secure();
  final tmpDirs = <Directory>[];
  final dbs = <CryptoDb>[];
  final outbox = <({String from, String to, Map<String, dynamic> content})>[];

  /// Chyba, kterou odeslání danému fingerprintu vyhodí (výpadek sítě…).
  final failing = <String, Object>{};

  setUpAll(() async => SepotCrypto.init());

  tearDown(() {
    outbox.clear();
    failing.clear();
    for (final db in dbs) {
      db.close();
    }
    for (final d in tmpDirs) {
      d.deleteSync(recursive: true);
    }
    dbs.clear();
    tmpDirs.clear();
  });

  Future<_Phone> phone(String name) async {
    final tmp = Directory.systemTemp.createTempSync('sepot_casovac');
    tmpDirs.add(tmp);
    final dek = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    final db = CryptoDb.open(path: '${tmp.path}/app.db', dek: dek);
    dbs.add(db);
    final storage = SecureStorageService(dbPath: '${tmp.path}/app.db')
      ..debugAttachDb(db);
    final service = MessagingService(storage: storage);
    final identity = await LocalIdentity.create(name);
    service.debugSetIdentity(identity);
    final p = _Phone(identity, storage, service);
    service.debugSendTap = (to, content) {
      final error = failing[to];
      if (error != null) throw error;
      outbox.add((
        from: p.fp,
        to: to,
        content: jsonDecode(jsonEncode(content)) as Map<String, dynamic>,
      ));
    };
    return p;
  }

  Future<void> introduce(List<_Phone> phones) async {
    for (final p in phones) {
      for (final q in phones) {
        if (p == q) continue;
        await p.storage.saveContact(Contact.fromPublicIdentity(
          q.identity.publicIdentity.withRouting(
            accountId: 'a' * 32,
            deliveryAddress: Uint8List(32),
          ),
        ));
      }
    }
  }

  /// Doručí frontu: správu skupin i `tmr`, ostatní typy zahodí.
  Future<void> deliver(List<_Phone> phones) async {
    final byFp = {for (final p in phones) p.fp: p};
    final batch = [...outbox];
    outbox.clear();
    for (final m in batch) {
      final to = byFp[m.to]?.service;
      if (to == null) continue;
      if (m.content['t'] == 'tmr') {
        await to.debugHandleTimer(m.from, m.content);
      } else {
        await to.debugHandleGroupControl(m.from, m.content);
      }
    }
  }

  Future<List<Message>> timerNotices(_Phone p, String convId) async =>
      (await p.storage.loadConversation(convId))!
          .messages
          .where((m) => m.notice == MessageNotice.timerChanged)
          .toList();

  test('1:1: změna dorazí protistraně i s oznámením, kdo ji udělal', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await introduce([a, b]);
    final bobAtAlice =
        (await a.storage.loadContacts()).firstWhere((c) => c.id == b.fp);

    await a.service.setDisappearing(b.fp, 3600, contact: bobAtAlice);
    expect(outbox.single.content['s'], 3600);
    await deliver([a, b]);

    expect((await b.storage.loadConversation(a.fp))!.disappearAfterSeconds,
        3600);
    final atBob = await timerNotices(b, a.fp);
    expect(atBob.single.senderId, a.fp);
    expect(atBob.single.content, '3600');
    expect((await timerNotices(a, b.fp)).single.isMine(a.identity.id), isTrue);

    await a.service.setDisappearing(b.fp, null, contact: bobAtAlice);
    expect(outbox.single.content['s'], 0, reason: '0 = vypnuto na drátu');
    await deliver([a, b]);
    expect((await b.storage.loadConversation(a.fp))!.disappearAfterSeconds,
        isNull);
  });

  test('fronta: smazání, které shodila síť, dojde po připojení', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await introduce([a, b]);
    final bobAtAlice =
        (await a.storage.loadContacts()).firstWhere((c) => c.id == b.fp);

    failing[b.fp] = const RelayUnavailableError();
    await a.service.deleteMessage(bobAtAlice, 'zprava-1');
    expect(outbox, isEmpty);
    expect(await a.service.debugPendingControls(), hasLength(1));

    await a.service.debugFlushPendingControls();
    expect(await a.service.debugPendingControls(), hasLength(1),
        reason: 'síť pořád leží — položka zůstává');

    failing.clear();
    await a.service.debugFlushPendingControls();
    expect(outbox.single.content['t'], 'del');
    expect(outbox.single.content['ref'], 'zprava-1');
    expect(await a.service.debugPendingControls(), isEmpty);
  });

  test('fronta: trvalá chyba příjemce se neopakuje', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await introduce([a, b]);
    final bobAtAlice =
        (await a.storage.loadContacts()).firstWhere((c) => c.id == b.fp);
    failing[b.fp] = const ContactNoDeliveryAddressError();
    await a.service.deleteMessage(bobAtAlice, 'zprava-1');
    expect(await a.service.debugPendingControls(), isEmpty);
  });

  test('neplatná hodnota z drátu se ignoruje', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await introduce([a, b]);
    await b.storage.ensureConversation(a.fp);
    for (final s in [12345, -30, '3600', 31 * 86400]) {
      await b.service.debugHandleTimer(a.fp, {'v': 1, 't': 'tmr', 's': s});
    }
    expect((await b.storage.loadConversation(a.fp))!.disappearAfterSeconds,
        isNull);
    expect(await timerNotices(b, a.fp), isEmpty);
  });

  group('skupina A (správce), B, C', () {
    late _Phone a, b, c;
    late String gid;

    setUp(() async {
      a = await phone('Alice');
      b = await phone('Bob');
      c = await phone('Cyril');
      await introduce([a, b, c]);
      gid = (await a.service.createGroup('Chata', await a.storage.loadContacts()))
          .id;
      await deliver([a, b, c]);
    });

    test('správce nastaví časovač → platí u všech členů', () async {
      await a.service.setDisappearing(gid, 86400,
          group: await a.storage.loadGroup(gid));
      await deliver([a, b, c]);
      for (final p in [b, c]) {
        expect((await p.storage.loadConversation(gid))!.disappearAfterSeconds,
            86400);
        expect((await timerNotices(p, gid)).single.senderId, a.fp);
      }
    });

    test('starší změna doručená později novější nepřepíše', () async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      Map<String, dynamic> tmr(int s, int at) =>
          {'v': 1, 't': 'tmr', 'gid': gid, 's': s, 'ts': at};
      await b.service.debugHandleTimer(a.fp, tmr(300, ts));
      await b.service.debugHandleTimer(a.fp, tmr(604800, ts - 60000));
      expect((await b.storage.loadConversation(gid))!.disappearAfterSeconds,
          300);
      expect(await timerNotices(b, gid), hasLength(1));
    });

    test('ne-správce: ve vynucené skupině neprojde, v kompatibilní ano',
        () async {
      final tmr = {'v': 1, 't': 'tmr', 'gid': gid, 's': 30};
      final g = (await c.storage.loadGroup(gid))!
        ..v2Members.addAll([a.fp, b.fp, c.fp]);
      await c.storage.saveGroup(g);
      await c.service.debugHandleTimer(b.fp, tmr);
      expect((await c.storage.loadConversation(gid))!.disappearAfterSeconds,
          isNull);

      final legacy = (await c.storage.loadGroup(gid))!..v2Members.clear();
      await c.storage.saveGroup(legacy);
      await c.service.debugHandleTimer(b.fp, tmr);
      expect((await c.storage.loadConversation(gid))!.disappearAfterSeconds,
          30);
    });

    test('fronta ve skupině: jen člen, kterému to neodešlo', () async {
      failing[c.fp] = const RelayUnavailableError();
      await a.service
          .sendGroupReaction((await a.storage.loadGroup(gid))!, 'z1', '👍');
      final pending = await a.service.debugPendingControls();
      expect(pending.single['to'], c.fp);
      expect(outbox.single.to, b.fp);
    });

    test('zprávu, která neodešla nikomu, dosílá outbox, ne fronta', () async {
      failing[b.fp] = const RelayUnavailableError();
      failing[c.fp] = const RelayUnavailableError();
      await a.service.sendGroupText((await a.storage.loadGroup(gid))!, 'Ahoj');
      expect(await a.service.debugPendingControls(), isEmpty);
    });

    test('člen odebraný mezitím frontu nedostane', () async {
      failing[c.fp] = const RelayUnavailableError();
      await a.service
          .sendGroupReaction((await a.storage.loadGroup(gid))!, 'z1', '👍');
      outbox.clear();
      failing.clear();
      await a.service.removeGroupMember((await a.storage.loadGroup(gid))!, c.fp);
      outbox.clear();
      await a.service.debugFlushPendingControls();
      expect(outbox, isEmpty);
      expect(await a.service.debugPendingControls(), isEmpty);
    });

    test('nový člen dostane časovač v pozvánce', () async {
      await a.service.setDisappearing(gid, 3600,
          group: await a.storage.loadGroup(gid));
      await deliver([a, b, c]);
      final d = await phone('Dana');
      await introduce([a, b, c, d]);
      final dana =
          (await a.storage.loadContacts()).firstWhere((x) => x.id == d.fp);
      await a.service.addGroupMembers((await a.storage.loadGroup(gid))!, [dana]);
      await deliver([a, b, c, d]);

      expect((await d.storage.loadConversation(gid))!.disappearAfterSeconds,
          3600);
      expect(await timerNotices(b, gid), hasLength(1),
          reason: 'stávající člen nedostane oznámení podruhé');
    });

    test('cizí (nečlen) skupinu nepřenastaví', () async {
      final d = await phone('Dana');
      await introduce([a, b, c, d]);
      await b.service
          .debugHandleTimer(d.fp, {'v': 1, 't': 'tmr', 'gid': gid, 's': 30});
      expect((await b.storage.loadConversation(gid))!.disappearAfterSeconds,
          isNull);
    });
  });
}

class _Phone {
  _Phone(this.identity, this.storage, this.service);

  final LocalIdentity identity;
  final SecureStorageService storage;
  final MessagingService service;

  String get fp => identity.fingerprint.display;
}
