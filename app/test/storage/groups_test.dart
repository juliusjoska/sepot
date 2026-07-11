import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/message.dart';

/// Skupiny v1 — perzistence a model. Bezpečnostní pravidla
/// příjmové cesty (roster anti-spoof, membership guard) mají vlastní test
/// v `test/groups_security_test.dart`, protože nepotřebují DB.
void main() {
  late Directory tmp;
  late CryptoDb db;
  late SecureStorageService storage;
  final rng = Random.secure();

  Uint8List randomDek() =>
      Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sepot_groups_test');
    db = CryptoDb.open(path: '${tmp.path}/app.db', dek: randomDek());
    storage = SecureStorageService(dbPath: '${tmp.path}/app.db')
      ..debugAttachDb(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Group vzorovaSkupina({String id = 'g-1', List<String>? members}) => Group(
        id: id,
        name: 'Rodina',
        memberIds: members ?? ['ME', 'ALICE', 'BOB'],
        createdBy: 'ME',
      );

  test('skupina přežije uložení a načtení (JSON roundtrip přes DB)', () async {
    final g = vzorovaSkupina();
    await storage.saveGroup(g);

    final nactena = await storage.loadGroup('g-1');
    expect(nactena, isNotNull);
    expect(nactena!.name, 'Rodina');
    expect(nactena.memberIds, ['ME', 'ALICE', 'BOB']);
    expect(nactena.createdBy, 'ME');
    expect(nactena.left, isFalse);
    expect(nactena.createdAt.toIso8601String(), g.createdAt.toIso8601String());
  });

  test('loadGroup vrátí null pro id, které patří 1:1 kontaktu', () async {
    await storage.saveGroup(vzorovaSkupina());
    expect(await storage.loadGroup('ALICE'), isNull,
        reason: 'rozlišení skupina vs kontakt stojí na tomhle null');
  });

  test('loadGroups vrátí všechny skupiny včetně opuštěných', () async {
    await storage.saveGroup(vzorovaSkupina(id: 'g-1'));
    final opustena = vzorovaSkupina(id: 'g-2')
      ..left = true
      ..memberIds = ['ALICE', 'BOB'];
    await storage.saveGroup(opustena);

    final vsechny = await storage.loadGroups();
    expect(vsechny.map((g) => g.id).toSet(), {'g-1', 'g-2'});
    expect(vsechny.firstWhere((g) => g.id == 'g-2').left, isTrue,
        reason: 'opuštěná skupina zůstává kvůli historii');
  });

  test('uložení stejného id skupinu přepíše, nezdvojí', () async {
    await storage.saveGroup(vzorovaSkupina());
    final zmenena = vzorovaSkupina()
      ..name = 'Rodina a přátelé'
      ..memberIds = ['ME', 'ALICE', 'BOB', 'CILKA'];
    await storage.saveGroup(zmenena);

    final vsechny = await storage.loadGroups();
    expect(vsechny.length, 1);
    expect(vsechny.single.name, 'Rodina a přátelé');
    expect(vsechny.single.memberIds.length, 4);
  });

  test('deleteGroup skupinu odstraní', () async {
    await storage.saveGroup(vzorovaSkupina());
    await storage.deleteGroup('g-1');
    expect(await storage.loadGroup('g-1'), isNull);
    expect(await storage.loadGroups(), isEmpty);
  });

  test('skupinová konverzace žije pod contact_id = gid', () async {
    final g = vzorovaSkupina();
    await storage.saveGroup(g);
    await storage.saveConversation(Conversation(
      contactId: g.id,
      messages: [
        Message.text(senderId: 'ALICE', recipientId: g.id, content: 'ahoj'),
      ],
    ));

    final conv = await storage.loadConversation(g.id);
    expect(conv, isNotNull);
    expect(conv!.messages.single.content, 'ahoj');
    expect(conv.messages.single.senderId, 'ALICE',
        reason: 'autor zprávy = fingerprint člena, ne gid');
  });

  test('Group.isMember rozhoduje o membership guardu', () {
    final g = vzorovaSkupina();
    expect(g.isMember('ALICE'), isTrue);
    expect(g.isMember('MALLORY'), isFalse);
  });

  test('strop členů je 128 (párový fanout = N obálek na zprávu)', () {
    expect(Group.maxMembers, 128);
  });

  test('fromJson snese chybějící "left" (starší záznam)', () {
    final g = Group.fromJson({
      'id': 'g-old',
      'name': 'Staré',
      'memberIds': ['ME'],
      'createdBy': 'ME',
      'createdAt': DateTime(2026, 7, 1).toIso8601String(),
    });
    expect(g.left, isFalse);
  });
}
