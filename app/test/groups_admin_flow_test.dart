// Needs the native libsignal library (FFI); skipped on builders without it (--exclude-tags ffi).
@Tags(['ffi'])
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
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';

/// Správci skupin end-to-end přes MessagingService: skutečné XEdDSA
/// podpisy, skutečné úložiště, relay nahrazený přímým předáním obsahu mezi
/// „telefony" (debugSendTap). Pokrývá tvorbu a příjem `gop`, legacy stín
/// pro v1 klienty, kompatibilní režim a resync po mezeře / rozchodu.
///
/// Potřebuje nativní libsignal i sqlcipher (jako groups_security_test).
void main() {
  final rng = Random.secure();
  final tmpDirs = <Directory>[];
  final dbs = <CryptoDb>[];

  /// Odeslaný obsah čekající na doručení (kdo, komu, co).
  final outbox = <({String from, String to, Map<String, dynamic> content})>[];

  setUpAll(() async => SepotCrypto.init());

  tearDown(() {
    outbox.clear();
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
    final tmp = Directory.systemTemp.createTempSync('sepot_admini');
    tmpDirs.add(tmp);
    final dek = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    final db = CryptoDb.open(path: '${tmp.path}/app.db', dek: dek);
    dbs.add(db);
    final storage = SecureStorageService(dbPath: '${tmp.path}/app.db')
      ..debugAttachDb(db);
    final service = MessagingService(storage: storage);
    final identity = await LocalIdentity.create(name);
    service.debugSetIdentity(identity);
    final p = _Phone(name, identity, storage, service);
    service.debugSendTap = (to, content) => outbox.add((
          from: p.fp,
          to: to,
          // Přes JSON jako na drátu — žádné sdílené objekty mezi telefony.
          content: jsonDecode(jsonEncode(content)) as Map<String, dynamic>,
        ));
    return p;
  }

  /// Každý zná každého jako kontakt s routingem (jako po výměně QR).
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

  /// Doručí frontu (FIFO) příjemcům ze seznamu; ostatní zahodí.
  Future<void> deliver(List<_Phone> phones,
      {bool Function(Map<String, dynamic>)? where}) async {
    final byFp = {for (final p in phones) p.fp: p};
    final batch = [...outbox];
    outbox.clear();
    for (final m in batch) {
      if (where != null && !where(m.content)) {
        outbox.add(m);
        continue;
      }
      await byFp[m.to]?.service.debugHandleGroupControl(m.from, m.content);
    }
  }

  List<Map<String, dynamic>> sentTo(_Phone p, String type) => [
        for (final m in outbox)
          if (m.to == p.fp && m.content['t'] == type) m.content,
      ];

  test('založení: v2 člen zná správce hned, v1 dostane obyčejný ginv',
      () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await introduce([a, b]);
    final contactB = (await a.storage.loadContacts()).single;
    final g = await a.service.createGroup('Chata', [contactB]);

    final ginv = sentTo(b, 'ginv').single;
    // Tvar, který zpracuje v1 klient: v:1, gid, gname, roster se mnou i s ním.
    expect(ginv['v'], 1);
    expect(ginv['gname'], 'Chata');
    expect((ginv['roster'] as List).map((e) => e['f']),
        containsAll([a.fp, b.fp]));
    expect(ginv['gop'], isA<Map>(), reason: 'vnořený podepsaný stav pro v2');
    expect(ginv['gv'], 2);

    await deliver([a, b]);
    final gb = (await b.storage.loadGroup(g.id))!;
    expect(gb.admins, [a.fp]);
    expect(gb.epoch, 0);
    expect(gb.provisional, isFalse, reason: 'stav je podepsaný');
  });

  group('skupina A (správce), B, C', () {
    late _Phone a, b, c;
    late String gid;

    setUp(() async {
      outbox.clear();
      a = await phone('Alice');
      b = await phone('Bob');
      c = await phone('Cyril');
      await introduce([a, b, c]);
      final contacts = await a.storage.loadContacts();
      gid = (await a.service.createGroup('Chata', contacts)).id;
      await deliver([a, b, c]);
    });

    Future<Group> load(_Phone p) async => (await p.storage.loadGroup(gid))!;

    test('odebrání: B aplikuje, C se dozví, že už není členem', () async {
      await a.service.removeGroupMember(await load(a), c.fp);
      expect(sentTo(c, 'ginv'), hasLength(1),
          reason: 'odebraný dostane výsledný stav taky');
      await deliver([a, b, c]);

      expect((await load(b)).memberIds, isNot(contains(c.fp)));
      expect((await load(b)).epoch, 1);
      expect((await load(c)).left, isTrue);
    });

    test('povýšení a přejmenování novým správcem projde u ostatních',
        () async {
      await a.service.setGroupAdmin(await load(a), b.fp, true);
      await deliver([a, b, c]);
      expect((await load(c)).admins, containsAll([a.fp, b.fp]));

      await b.service.renameGroup(await load(b), 'Chata 2026');
      await deliver([a, b, c]);
      expect((await load(a)).name, 'Chata 2026');
      expect((await load(c)).name, 'Chata 2026');
      expect((await load(c)).epoch, 2);
    });

    test('NE-SPRÁVCE: B podepsaný gop se nepostaví a podvržený se odmítne',
        () async {
      await expectLater(b.service.renameGroup(await load(b), 'Únos'),
          throwsA(isA<NotGroupAdminError>()));

      // B si vyrobí operaci s podpisem sebe sama (upravený klient).
      await a.service.setGroupAdmin(await load(a), b.fp, true);
      final gop = Map<String, dynamic>.from(
          sentTo(c, 'ginv').single['gop'] as Map);
      outbox.clear();
      // Stejné pole, ale autor B, který v C správce není → notAdmin.
      await c.service.debugHandleGroupControl(b.fp, {
        'v': 1,
        't': 'gop',
        ...gop,
        'by': b.fp,
      });
      final gc = await load(c);
      expect(gc.admins, [a.fp]);
      expect(gc.rejectedOpAt, isNotNull);
    });

    test('SPOOF: operaci správce A přeposlanou od B C odmítne', () async {
      await a.service.renameGroup(await load(a), 'Nové jméno');
      final gmeta = sentTo(c, 'gmeta').single;
      outbox.clear();
      await c.service.debugHandleGroupControl(b.fp, gmeta);
      final gc = await load(c);
      expect(gc.epoch, 0);
      expect(gc.rejectedOpAt, isNotNull);
    });

    test('ŠPATNÝ PODPIS: pozměněné jméno se stejným podpisem neprojde',
        () async {
      await a.service.renameGroup(await load(a), 'Poctivé');
      final gmeta = sentTo(c, 'gmeta').single;
      outbox.clear();
      (gmeta['gop'] as Map)['gname'] = 'Podvržené';
      await c.service.debugHandleGroupControl(a.fp, gmeta);
      final gc = await load(c);
      expect(gc.epoch, 0);
      expect(gc.rejectedOpAt, isNotNull);
      expect(gc.name, isNot('Podvržené'));
    });

    test('MEZERA: epocha 2 před 1 se podrží, vyžádá stav a po 1 aplikuje',
        () async {
      await a.service.renameGroup(await load(a), 'Jedna');
      final e1 = sentTo(c, 'gmeta').single;
      await a.service.renameGroup(await load(a), 'Dvě');
      final e2 = sentTo(c, 'gmeta').last;
      outbox.clear();

      await c.service.debugHandleGroupControl(a.fp, e2);
      var gc = await load(c);
      expect(gc.epoch, 0);
      expect(gc.needsResync, isTrue);
      expect(gc.pendingOps, hasLength(1));
      expect(sentTo(a, 'gsync'), hasLength(1),
          reason: 'žádost o stav jde správci');

      await c.service.debugHandleGroupControl(a.fp, e1);
      gc = await load(c);
      expect(gc.epoch, 2);
      expect(gc.name, 'Dvě');
      expect(gc.needsResync, isFalse);
      expect(gc.pendingOps, isEmpty);
    });

    test('ZASTARALÁ: opakované doručení téže operace nic nezmění', () async {
      await a.service.renameGroup(await load(a), 'Jednou');
      final e1 = sentTo(c, 'gmeta').single;
      await deliver([a, b, c]);
      final before = jsonEncode((await load(c)).toJson());
      await c.service.debugHandleGroupControl(a.fp, e1);
      expect(jsonEncode((await load(c)).toJson()), before);
    });

    test('FORK přes prev: resync stavem od správce a konec bez smyčky',
        () async {
      // C má kvůli rozdílné historii jiný stav na stejné epoše.
      final gc0 = await load(c)..name = 'Rozešlá historie';
      await c.storage.saveGroup(gc0);

      await a.service.renameGroup(await load(a), 'Pravda');
      await deliver([c]);
      var gc = await load(c);
      expect(gc.needsResync, isTrue);
      expect(gc.name, 'Rozešlá historie');

      // gsync → A odpoví podepsaným stavem → C ho přijme (epocha 1 > 0).
      await deliver([a, c]);
      await deliver([a, c]);
      gc = await load(c);
      expect(gc.name, 'Pravda');
      expect(gc.epoch, 1);
      expect(gc.needsResync, isFalse);
      expect(outbox, isEmpty, reason: 'odpověď už nic dalšího nevyvolá');
    });

    test('poslední správce se nemůže degradovat; při odchodu předá roli',
        () async {
      await expectLater(a.service.setGroupAdmin(await load(a), a.fp, false),
          throwsA(isA<LastGroupAdminError>()));

      await a.service.leaveGroup(await load(a));
      await deliver([a, b, c]);
      final gb = await load(b);
      final naslednik = ([b.fp, c.fp]..sort()).first;
      expect(gb.memberIds, isNot(contains(a.fp)));
      expect(gb.admins, [naslednik]);
      expect((await load(c)).admins, [naslednik]);
      expect((await load(a)).left, isTrue);
    });
  });

  group('kompatibilní režim v1 ↔ v2', () {
    late _Phone a, b, c, d;
    late String gid;

    setUp(() async {
      outbox.clear();
      a = await phone('Alice');
      b = await phone('Bob');
      c = await phone('Cyril');
      d = await phone('Dana');
      await introduce([a, b, c, d]);
      final contacts = (await a.storage.loadContacts())
          .where((x) => x.id != d.fp)
          .toList();
      gid = (await a.service.createGroup('Chata', contacts)).id;
      await deliver([a, b, c]);
    });

    /// Legacy `ginv` od B (bez `gop`), který přidává Danu — tak přidává v1.
    Map<String, dynamic> legacyAddFromB() {
      Map<String, dynamic> e(_Phone p) => {
            'f': p.fp,
            'n': p.name,
            'ik': base64Encode(p.identity.publicIdentity.identityKey),
            'aid': 'a' * 32,
            'da': base64Encode(Uint8List(32)),
          };
      return {
        'v': 1,
        't': 'ginv',
        'gid': gid,
        'gname': 'Chata',
        'roster': [e(a), e(b), e(c), e(d)],
      };
    }

    test('v1 člen ve skupině → ginv od ne-správce projde (jen přidání)',
        () async {
      // C inzeruje v2 (poslal skupinovou zprávu s gv), B je v1 — nic.
      final gc = (await c.storage.loadGroup(gid))!..v2Members.add(a.fp);
      await c.storage.saveGroup(gc);

      await c.service.debugHandleGroupControl(b.fp, legacyAddFromB());
      final after = (await c.storage.loadGroup(gid))!;
      expect(after.memberIds, contains(d.fp));
      expect(after.admins, [a.fp], reason: 'role se legacy cestou nemění');
    });

    test('všichni inzerují v2 → ginv od ne-správce neprojde', () async {
      final gc = (await c.storage.loadGroup(gid))!
        ..v2Members.addAll([a.fp, b.fp]);
      await c.storage.saveGroup(gc);

      await c.service.debugHandleGroupControl(b.fp, legacyAddFromB());
      final after = (await c.storage.loadGroup(gid))!;
      expect(after.memberIds, isNot(contains(d.fp)));
      expect(after.rejectedOpAt, isNotNull);
    });

    test('ve vynucené skupině jde operace samostatně jako t:gop', () async {
      final ga = (await a.storage.loadGroup(gid))!
        ..v2Members.addAll([b.fp, c.fp]);
      await a.storage.saveGroup(ga);
      await a.service.renameGroup(ga, 'Jen v2');
      expect(sentTo(c, 'gop'), hasLength(1));
      expect(sentTo(c, 'gmeta'), isEmpty);
      await deliver([a, b, c]);
      expect((await c.storage.loadGroup(gid))!.name, 'Jen v2');
    });

    test('ne-správce v kompatibilním režimu přidá legacy cestou, ve '
        'vynucené skupině nesmí', () async {
      final contactD =
          (await b.storage.loadContacts()).firstWhere((x) => x.id == d.fp);
      var gb = (await b.storage.loadGroup(gid))!;
      await b.service.addGroupMembers(gb, [contactD]);
      final inv = sentTo(c, 'ginv').single;
      expect(inv.containsKey('gop'), isFalse);

      outbox.clear();
      gb = (await b.storage.loadGroup(gid))!
        ..memberIds.remove(d.fp)
        ..v2Members.addAll([a.fp, c.fp, d.fp]);
      await b.storage.saveGroup(gb);
      await expectLater(b.service.addGroupMembers(gb, [contactD]),
          throwsA(isA<NotGroupAdminError>()));
    });

    test('capability se učí z gv ve skupinové zprávě a nejde odebrat',
        () async {
      final ga = (await a.storage.loadGroup(gid))!;
      expect(ga.v2Members, isEmpty);
      // Legacy gmeta od B s gv:2 (v2 klient) — naučí; bez gv nic neodebere.
      await a.service.debugHandleGroupControl(
          b.fp, {'v': 1, 't': 'gmeta', 'gid': gid, 'gname': 'X', 'gv': 2});
      await a.service.debugHandleGroupControl(
          b.fp, {'v': 1, 't': 'gmeta', 'gid': gid, 'gname': 'Y'});
      expect((await a.storage.loadGroup(gid))!.v2Members, {b.fp});
    });
  });

  test('migrace uložené v1 skupiny proběhne při načtení bez sítě', () async {
    final a = await phone('Alice');
    dbs.last.groupPut(
      'stara',
      jsonEncode({
        'id': 'stara',
        'name': 'Z verze 1.1',
        'memberIds': [a.fp, 'fpB'],
        'createdBy': a.fp,
        'createdAt': '2026-07-10T10:00:00.000',
        'left': false,
      }),
    );
    final g = (await a.storage.loadGroup('stara'))!;
    expect(g.admins, [a.fp]);
    expect(g.epoch, 0);
    expect(outbox, isEmpty);
  });
}

class _Phone {
  _Phone(this.name, this.identity, this.storage, this.service);

  final String name;
  final LocalIdentity identity;
  final SecureStorageService storage;
  final MessagingService service;

  String get fp => identity.fingerprint.display;
}
