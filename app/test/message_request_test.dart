// Potřebuje nativní libsignal (FFI) — na builderu bez Rust toolchainu se vynechává (--exclude-tags ffi).
@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart' show ProtocolAddress;
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/persistent_stores.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/message.dart';

/// Phishing „Máma“: cizí klíč se jménem existujícího kontaktu nesmí
/// splynout s kontaktem ani převzít jeho jméno, ověření nebo hovory.
/// Změna klíče pod adresou známého kontaktu ruší ověření a varuje.
void main() {
  late Directory tmp;
  late CryptoDb db;
  late SecureStorageService storage;
  late MessagingService service;
  late LocalIdentity ja;
  late LocalIdentity mama;
  late Contact mamaContact;
  final rng = Random.secure();
  final sent = <(String, Map<String, dynamic>)>[];
  final calls = <String>[];

  Uint8List randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));

  const mamaAccount = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  setUpAll(() async => SepotCrypto.init());

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sepot_request');
    db = CryptoDb.open(path: '${tmp.path}/app.db', dek: randomBytes(32));
    storage = SecureStorageService(dbPath: '${tmp.path}/app.db')
      ..debugAttachDb(db);
    service = MessagingService(storage: storage);
    ja = await LocalIdentity.create('Já');
    service.debugSetIdentity(ja);
    sent.clear();
    calls.clear();
    service.debugSendTap = (to, content) => sent.add((to, content));
    service.onCallSignal = (contact, _) => calls.add(contact.id);

    mama = await LocalIdentity.create('Máma');
    mamaContact = Contact.fromPublicIdentity(
      mama.publicIdentity
          .withRouting(accountId: mamaAccount, deliveryAddress: randomBytes(32)),
      verified: true,
    );
    await storage.saveContact(mamaContact);
    await storage.saveConversation(Conversation(contactId: mamaContact.id));
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Obálka od [from] po dešifrování (sealed sender už ověřil klíč a účet).
  Future<void> deliver(
    LocalIdentity from,
    String account,
    Map<String, dynamic> content,
  ) =>
      service.debugProcessOpened(
        SepotSealedMessage(
          plaintext: utf8.encode(jsonEncode({'v': 1, ...content})),
          senderName: account,
          senderDeviceId: 1,
          senderIdentityKey: from.publicIdentity.identityKey,
        ),
        randomBytes(16),
      );

  Map<String, dynamic> text(String name, String txt) => {
        't': 'txt',
        'id': 'm-${rng.nextInt(1 << 30)}',
        'txt': txt,
        'p': {'n': name, 'da': base64Encode(randomBytes(32))},
      };

  Future<Contact> contactOf(LocalIdentity id) async =>
      (await storage.loadContacts()).singleWhere((c) => c.id == id.id);

  test('cizí klíč se jménem „Máma“ = žádost o zprávu, ne splynutí', () async {
    final podvrh = await LocalIdentity.create('Máma');
    await deliver(podvrh, 'b' * 32, text('Máma', 'Pošli mi kód z SMS'));

    final kontakty = await storage.loadContacts();
    expect(kontakty, hasLength(2), reason: 'nový klíč = nový kontakt');

    final skutecna = await contactOf(mama);
    expect(skutecna.displayName, 'Máma');
    expect(skutecna.verified, isTrue, reason: 'cizí klíč ověření nemění');
    expect(skutecna.publicIdentity.identityKey, mama.publicIdentity.identityKey);

    final zadost = await contactOf(podvrh);
    expect(zadost.accepted, isFalse);
    expect(zadost.verified, isFalse);

    final zprava = (await storage.loadConversation(zadost.id))!.messages.single;
    expect(zprava.content, 'Pošli mi kód z SMS');
    expect(zprava.senderId, podvrh.id, reason: 'zpráva patří podvrhu');

    final upozorneni =
        (await storage.loadConversation(skutecna.id))!.messages.single;
    expect(upozorneni.notice, MessageNotice.lookalikeRequest);
    expect(upozorneni.content, 'Máma');
  });

  test('podobné jméno (cyrilice, velká písmena, mezery) se taky pozná',
      () async {
    final podvrh = await LocalIdentity.create('x');
    await deliver(podvrh, 'c' * 32, text(' МÁМА ', 'ahoj'));
    final upozorneni =
        (await storage.loadConversation(mamaContact.id))!.messages.single;
    expect(upozorneni.notice, MessageNotice.lookalikeRequest);
  });

  test('stejný účet na relayi s jiným klíčem = změna bezpečnostního kódu',
      () async {
    final novyKlic = await LocalIdentity.create('Máma');
    await deliver(novyKlic, mamaAccount, text('Máma', 'nový telefon'));

    final skutecna = await contactOf(mama);
    expect(skutecna.verified, isFalse, reason: 'ověření se ruší');
    expect(skutecna.displayName, 'Máma');
    final upozorneni =
        (await storage.loadConversation(skutecna.id))!.messages.single;
    expect(upozorneni.notice, MessageNotice.identityChanged);

    final zadost = await contactOf(novyKlic);
    expect(zadost.accepted, isFalse, reason: 'nový klíč se nepřebírá');
  });

  test('opakovaná změna nepřidává další a další upozornění', () async {
    final novyKlic = await LocalIdentity.create('Máma');
    await deliver(novyKlic, mamaAccount, text('Máma', '1'));
    await deliver(novyKlic, mamaAccount, text('Máma', '2'));
    final zpravy = (await storage.loadConversation(mamaContact.id))!.messages;
    expect(zpravy.where((m) => m.notice != null), hasLength(1));
  });

  test('žádost o zprávu nezvoní, přijatý kontakt ano', () async {
    final cizi = await LocalIdentity.create('Máma');
    await deliver(cizi, 'd' * 32, text('Máma', 'ahoj'));
    await deliver(cizi, 'd' * 32, {'t': 'call', 'id': 'c1', 'k': 'offer'});
    expect(calls, isEmpty);

    await deliver(mama, mamaAccount, {'t': 'call', 'id': 'c2', 'k': 'offer'});
    expect(calls, [mama.id]);
  });

  test('neznámý odesílatel nedostane potvrzení přečtení', () async {
    await storage.setSetting('read_receipts_enabled', true);
    final cizi = await LocalIdentity.create('Někdo');
    await deliver(cizi, 'e' * 32, text('Někdo', 'ahoj'));
    final zadost = await contactOf(cizi);
    sent.clear();
    await service.sendReadReceipts(zadost, ['m1']);
    expect(sent, isEmpty);

    await service.sendReadReceipts(await contactOf(mama), ['m2']);
    expect(sent.single.$2['t'], 'rr');
  });

  test('známý kontakt dál chodí do své konverzace beze změny', () async {
    await deliver(mama, mamaAccount, text('Úplně jiné jméno', 'ahoj'));
    final kontakty = await storage.loadContacts();
    expect(kontakty, hasLength(1));
    expect(kontakty.single.displayName, 'Máma',
        reason: 'jméno z profilu odesílatele nepřepisuje moje');
    expect(kontakty.single.accepted, isTrue);
    expect(kontakty.single.verified, isTrue);
  });

  test('kontakt uložený před 1.2.3 (bez příznaku) je přijatý', () {
    final json = mamaContact.toJson()..remove('accepted');
    expect(Contact.fromJson(json).accepted, isTrue);
  });

  group('odesílání: relace patřící cizímu klíči', () {
    late SepotCrypto ja2;
    late ProtocolAddress addr;

    setUp(() {
      addr = ProtocolAddress(name: mamaAccount, deviceId: 1);
      ja2 = SepotCrypto.fromPrivateKey(
        privateKey: ja.identityPrivateKey,
        accountId: 'f' * 32,
        registrationId: 7,
        storesFactory: (pair) => SepotStores(
          session: DbSessionStore(db),
          identity: DbIdentityKeyStore(db,
              identityKeyPair: pair, registrationId: 7),
          preKey: DbPreKeyStore(db),
          signedPreKey: DbSignedPreKeyStore(db),
          kyberPreKey: DbKyberPreKeyStore(db),
        ),
      );
    });

    Future<SepotPreKeyBundle> bundleOf(LocalIdentity id) =>
        SepotCrypto.fromPrivateKey(
          privateKey: id.identityPrivateKey,
          accountId: mamaAccount,
          registrationId: 9,
        ).generatePreKeyBundle(
          preKeyId: 1,
          signedPreKeyId: 1,
          kyberPreKeyId: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );

    test('relace s klíčem kontaktu zůstává', () async {
      await ja2.processRemoteBundle(addr, await bundleOf(mama));
      await service.debugDropForeignSession(ja2, addr, mamaContact);
      expect(await ja2.hasSession(addr), isTrue);
      expect((await contactOf(mama)).verified, isTrue);
    });

    test('relace přepsaná cizím klíčem se zahodí a kontakt varuje', () async {
      await ja2.processRemoteBundle(addr, await bundleOf(mama));
      final utocnik = await LocalIdentity.create('Máma');
      await ja2.processRemoteBundle(addr, await bundleOf(utocnik));

      await service.debugDropForeignSession(ja2, addr, mamaContact);

      expect(await ja2.hasSession(addr), isFalse,
          reason: 'odpověď nesmí odejít útočníkovi');
      final kontakt = await contactOf(mama);
      expect(kontakt.verified, isFalse);
      final upozorneni =
          (await storage.loadConversation(kontakt.id))!.messages.single;
      expect(upozorneni.notice, MessageNotice.identityChanged);
    });
  });
}
