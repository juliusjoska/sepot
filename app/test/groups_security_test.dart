// Needs the native libsignal library (FFI); skipped on builders without it (--exclude-tags ffi).
@Tags(['ffi'])
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';

/// Bezpečnostní pravidla skupin — invarianty příjmové cesty: fingerprint
/// v rosteru musí odpovídat identity klíči, odesílatel i já musíme být
/// členy, roster smí měnit jen stávající člen a identity klíč známého
/// kontaktu se nikdy nepřepisuje (TOFU). Útočné scénáře: podvržený roster,
/// cizí odesílatel, přepis identity klíče, pozvánka bez příjemce, roster
/// přes strop.
void main() {
  late Directory tmp;
  late CryptoDb db;
  late SecureStorageService storage;
  late MessagingService service;
  late LocalIdentity ja;
  final rng = Random.secure();

  Uint8List randomDek() =>
      Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));

  setUpAll(() async => SepotCrypto.init());

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sepot_groups_sec');
    db = CryptoDb.open(path: '${tmp.path}/app.db', dek: randomDek());
    storage = SecureStorageService(dbPath: '${tmp.path}/app.db')
      ..debugAttachDb(db);
    service = MessagingService(storage: storage);
    ja = await LocalIdentity.create('Já');
    service.debugSetIdentity(ja);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Roster entry pro danou identitu (poctivá: f == fingerprint(ik)).
  Map<String, dynamic> entry(LocalIdentity id, {bool routing = true}) => {
        'f': id.fingerprint.display,
        'n': id.displayName,
        'ik': base64Encode(id.publicIdentity.identityKey),
        if (routing) 'aid': 'a' * 32,
        if (routing) 'da': base64Encode(Uint8List(32)),
      };

  Map<String, dynamic> pozvanka(
    String gid,
    String gname,
    List<Map<String, dynamic>> roster,
  ) =>
      {'v': 1, 't': 'ginv', 'gid': gid, 'gname': gname, 'roster': roster};

  test('poctivá pozvánka založí skupinu a neznámé členy jako kontakty',
      () async {
    final alice = await LocalIdentity.create('Alice');
    await service.debugHandleGroupInvite(
      alice.fingerprint.display,
      pozvanka('g1', 'Rodina', [entry(alice), entry(ja)]),
    );

    final g = await storage.loadGroup('g1');
    expect(g, isNotNull);
    expect(g!.name, 'Rodina');
    expect(g.memberIds.toSet(),
        {alice.fingerprint.display, ja.fingerprint.display});

    final kontakty = await storage.loadContacts();
    expect(kontakty.map((c) => c.id), contains(alice.fingerprint.display),
        reason: 'člen z rosteru se založí jako neověřený kontakt');
    expect(kontakty.single.verified, isFalse);
  });

  test('PODVRŽENÝ ROSTER: fingerprint nesedící ke svému identity klíči '
      'se zahodí (anti-spoof)', () async {
    final alice = await LocalIdentity.create('Alice');
    final mallory = await LocalIdentity.create('Mallory');

    // Mallory tvrdí, že klíč patří Aliciinu fingerprintu.
    final falesny = entry(mallory)..['f'] = alice.fingerprint.display;

    await service.debugHandleGroupInvite(
      mallory.fingerprint.display,
      pozvanka('g1', 'Podvrh', [falesny, entry(mallory), entry(ja)]),
    );

    final g = await storage.loadGroup('g1');
    expect(g, isNotNull, reason: 'zbytek pozvánky je platný');
    expect(g!.memberIds, isNot(contains(alice.fingerprint.display)),
        reason: 'záznam s nesedícím fingerprintem se musí zahodit');

    final kontakty = await storage.loadContacts();
    expect(kontakty.map((c) => c.id), isNot(contains(alice.fingerprint.display)),
        reason: 'podvržený člen se nesmí založit jako kontakt');
  });

  test('pozvánka, ve které odesílatel není členem, se zahodí', () async {
    final alice = await LocalIdentity.create('Alice');
    final mallory = await LocalIdentity.create('Mallory');

    await service.debugHandleGroupInvite(
      mallory.fingerprint.display, // odesílatel chybí v rosteru
      pozvanka('g1', 'Cizí', [entry(alice), entry(ja)]),
    );
    expect(await storage.loadGroup('g1'), isNull);
  });

  test('pozvánka, ve které nejsem členem, se zahodí', () async {
    final alice = await LocalIdentity.create('Alice');
    final bob = await LocalIdentity.create('Bob');

    await service.debugHandleGroupInvite(
      alice.fingerprint.display,
      pozvanka('g1', 'Bez mě', [entry(alice), entry(bob)]),
    );
    expect(await storage.loadGroup('g1'), isNull);
  });

  test('roster přes strop 128 členů se zahodí', () async {
    final alice = await LocalIdentity.create('Alice');
    final roster = [entry(alice), entry(ja)];
    for (var i = 0; i < Group.maxMembers; i++) {
      roster.add(entry(await LocalIdentity.create('Člen $i')));
    }
    await service.debugHandleGroupInvite(
      alice.fingerprint.display,
      pozvanka('g1', 'Přeplněná', roster),
    );
    expect(await storage.loadGroup('g1'), isNull);
  });

  test('roster NEPŘEPÍŠE identity klíč existujícího kontaktu (TOFU)',
      () async {
    final alice = await LocalIdentity.create('Alice');
    final mallory = await LocalIdentity.create('Mallory');

    // Alici už znám a mám ověřený její pravý klíč.
    await storage.saveContact(Contact(
      displayName: 'Alice',
      publicIdentity: alice.publicIdentity,
      addedAt: DateTime(2026, 7, 1),
      verified: true,
    ));

    // Mallory pošle roster, kde Aliciin záznam nese Malloryin klíč pod
    // Malloryiným fingerprintem — Alice tam je poctivě, ale útočník
    // zkusí přejmenovat/přetlačit. Klíč Alice musí zůstat původní.
    final rosterAlice = entry(alice);
    await service.debugHandleGroupInvite(
      mallory.fingerprint.display,
      pozvanka('g1', 'Skupina', [rosterAlice, entry(mallory), entry(ja)]),
    );

    final kontakty = await storage.loadContacts();
    final ulozena = kontakty.firstWhere((c) => c.id == alice.fingerprint.display);
    expect(ulozena.publicIdentity.identityKey,
        equals(alice.publicIdentity.identityKey));
    expect(ulozena.verified, isTrue,
        reason: 'pozvánka nesmí shodit ověření existujícího kontaktu');
  });

  test('MEMBERSHIP GUARD: obsah od nečlena → drop (null)', () async {
    final alice = await LocalIdentity.create('Alice');
    final mallory = await LocalIdentity.create('Mallory');
    await storage.saveGroup(Group(
      id: 'g1',
      name: 'Uzavřená',
      memberIds: [ja.fingerprint.display, alice.fingerprint.display],
      createdBy: ja.fingerprint.display,
    ));

    expect(await service.debugGroupForIncoming('g1', alice.fingerprint.display),
        isNotNull);
    expect(
        await service.debugGroupForIncoming('g1', mallory.fingerprint.display),
        isNull,
        reason: 'nečlen nesmí psát do skupiny');
    expect(await service.debugGroupForIncoming('neznama', alice.fingerprint.display),
        isNull);
  });

  test('MEMBERSHIP GUARD: do opuštěné skupiny nedorazí nic', () async {
    final alice = await LocalIdentity.create('Alice');
    await storage.saveGroup(Group(
      id: 'g1',
      name: 'Opuštěná',
      memberIds: [alice.fingerprint.display],
      createdBy: alice.fingerprint.display,
      left: true,
    ));
    expect(await service.debugGroupForIncoming('g1', alice.fingerprint.display),
        isNull);
  });

  test('aktualizaci rosteru smí poslat jen stávající člen', () async {
    final alice = await LocalIdentity.create('Alice');
    final mallory = await LocalIdentity.create('Mallory');
    await storage.saveGroup(Group(
      id: 'g1',
      name: 'Původní',
      memberIds: [ja.fingerprint.display, alice.fingerprint.display],
      createdBy: ja.fingerprint.display,
    ));

    // Mallory (nečlen) se zkusí přidat vlastní pozvánkou.
    await service.debugHandleGroupInvite(
      mallory.fingerprint.display,
      pozvanka('g1', 'Únos', [entry(mallory), entry(alice), entry(ja)]),
    );

    final g = await storage.loadGroup('g1');
    expect(g!.memberIds, isNot(contains(mallory.fingerprint.display)));
    expect(g.name, 'Původní', reason: 'nečlen nesmí ani přejmenovat');
  });

  test('člen smí rozšířit roster (trust model v1: každý smí přidávat)',
      () async {
    final alice = await LocalIdentity.create('Alice');
    final bob = await LocalIdentity.create('Bob');
    await storage.saveGroup(Group(
      id: 'g1',
      name: 'Skupina',
      memberIds: [ja.fingerprint.display, alice.fingerprint.display],
      createdBy: ja.fingerprint.display,
    ));

    await service.debugHandleGroupInvite(
      alice.fingerprint.display,
      pozvanka('g1', 'Skupina', [entry(alice), entry(bob), entry(ja)]),
    );

    final g = await storage.loadGroup('g1');
    expect(g!.memberIds, contains(bob.fingerprint.display));
  });

  test('pozvánka s prázdným jménem nebo přerostlým gid se zahodí', () async {
    final alice = await LocalIdentity.create('Alice');
    await service.debugHandleGroupInvite(
      alice.fingerprint.display,
      pozvanka('g1', '', [entry(alice), entry(ja)]),
    );
    expect(await storage.loadGroup('g1'), isNull);

    final dlouheGid = 'g' * 65;
    await service.debugHandleGroupInvite(
      alice.fingerprint.display,
      pozvanka(dlouheGid, 'Dlouhé', [entry(alice), entry(ja)]),
    );
    expect(await storage.loadGroup(dlouheGid), isNull);
  });
}
