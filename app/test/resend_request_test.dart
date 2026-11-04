// Needs the native libsignal library (FFI); skipped on builders without it (--exclude-tags ffi).
@Tags(['ffi'])
library;

import 'dart:async';
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
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/message.dart';

/// Žádost o znovuposlání (`rtr`) na straně
/// odesílatele: co se pošle znovu, komu, a kdy zpráva skončí jako
/// nedoručená. Odesílání přes [MessagingService.debugSendTap].
void main() {
  late Directory tmp;
  late CryptoDb db;
  late SecureStorageService storage;
  late MessagingService service;
  late LocalIdentity me;
  late Contact bob;
  late Contact carol;
  final rng = Random.secure();
  final sent = <(String, Map<String, dynamic>)>[];
  Object? sendError;

  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));

  setUpAll(() async => SepotCrypto.init());

  Future<Contact> contact(String name) async {
    final id = await LocalIdentity.create(name);
    final c = Contact.fromPublicIdentity(
      id.publicIdentity.withRouting(
        accountId: 'a' * 32,
        deliveryAddress: bytes(32),
      ),
    );
    await storage.saveContact(c);
    return c;
  }

  MessagingService newService() {
    final s = MessagingService(storage: storage)
      ..debugSetIdentity(me)
      ..debugAttachStorageDb()
      ..debugSendTap = (to, content) {
        final error = sendError;
        if (error != null) throw error;
        sent.add((to, content));
      };
    return s;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sepot_rtr');
    db = CryptoDb.open(path: '${tmp.path}/app.db', dek: bytes(32));
    storage = SecureStorageService(dbPath: '${tmp.path}/app.db')
      ..debugAttachDb(db);
    me = await LocalIdentity.create('Já');
    bob = await contact('Bob');
    carol = await contact('Carol');
    service = newService();
    sent.clear();
    sendError = null;
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Message mine(String id, {String text = 'ahoj', int? ttl}) => Message(
    id: id,
    senderId: me.id,
    recipientId: bob.id,
    type: MessageType.text,
    content: text,
    timestamp: DateTime.now(),
    status: MessageStatus.delivered,
    isDelivered: true,
    disappearAfterSeconds: ttl,
  );

  /// Obálka, kterou jsme [to] poslali — vrací msg_uuid jako v `rtr`.
  String logged(
    Contact to,
    String target, {
    String kind = 'txt',
    String? conv,
  }) {
    final uuid = bytes(16);
    db.sentLogPut(
      msgUuid: uuid,
      contactId: to.id,
      convId: conv ?? to.id,
      targetId: target,
      kind: kind,
    );
    return base64Encode(uuid);
  }

  Future<void> request(Contact from, List<String> refs, {bool dup = false}) =>
      service.debugHandleResendRequest(from, {
        't': 'rtr',
        dup ? 'dup' : 'refs': refs,
      });

  Future<Message> load(String conv, String id) async =>
      (await storage.loadConversation(
        conv,
      ))!.messages.singleWhere((m) => m.id == id);

  List<int> resendRequestsTo(Contact c) {
    final raw = db.kvGet('rtr_limits');
    if (raw == null) return const [];
    final map = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    return ((map[c.id] as Map<String, dynamic>?)?['s'] as List? ?? const [])
        .cast<int>();
  }

  test(
    'řídicí zprávy se sestaví z aktuálního stavu, ne z uloženého obsahu',
    () async {
      await storage.saveConversation(
        Conversation(
          contactId: bob.id,
          messages: [
            mine('m1').copyWith(reactions: {me.id: '🔥'}),
            mine('m2').copyWith(isDeleted: true, content: ''),
            mine(
              'm3',
              text: 'opraveno podruhé',
            ).copyWith(editedAt: DateTime.now()),
            mine('m4'),
          ],
        ),
      );
      await request(bob, [
        logged(bob, 'm1', kind: 'rx'),
        logged(bob, 'm2', kind: 'del'),
        logged(bob, 'm3', kind: 'edit'),
        logged(bob, 'm4', kind: 'del'),
      ]);

      final byType = {for (final (_, c) in sent) c['t']: c};
      expect(sent.map((s) => s.$1), everyElement(bob.id));
      expect(byType['rx']?['e'], '🔥', reason: 'reakce, jak je teď');
      expect(byType['del']?['ref'], 'm2');
      expect(byType['edit']?['txt'], 'opraveno podruhé');
      expect(
        sent,
        hasLength(3),
        reason: 'm4 smazaná není — „del“ k ní už neplatí',
      );
    },
  );

  test(
    'po vyčerpání znovuposlání je zpráva nedoručená a outbox ji nechá',
    () async {
      await storage.saveConversation(
        Conversation(contactId: bob.id, messages: [mine('m1')]),
      );
      for (var i = 0; i < 2; i++) {
        await request(bob, [logged(bob, 'm1')]);
      }
      expect(sent, hasLength(2));
      expect((await load(bob.id, 'm1')).undeliveredTo, isEmpty);

      await request(bob, [logged(bob, 'm1')]);
      expect(sent, hasLength(2), reason: 'třetí žádost už nic neposílá');
      final m = await load(bob.id, 'm1');
      expect(m.status, MessageStatus.failed);
      expect(m.undeliveredTo, {bob.id});

      // Doručenka od příjemce stav napraví.
      final fixed = MessagingService.applyReceipt(
        m,
        from: bob.id,
        at: DateTime.now(),
        read: false,
      );
      expect(fixed.undeliveredTo, isEmpty);
      expect(fixed.status, MessageStatus.delivered);
    },
  );

  test('duplicita zprávu nikdy neoznačí jako nedoručenou', () async {
    await storage.saveConversation(
      Conversation(contactId: bob.id, messages: [mine('m1')]),
    );
    for (var i = 0; i < 2; i++) {
      await request(bob, [logged(bob, 'm1')]);
    }
    await request(bob, [logged(bob, 'm1')], dup: true);
    final m = await load(bob.id, 'm1');
    expect(m.undeliveredTo, isEmpty, reason: 'příjemce zprávu nejspíš má');
    expect(m.status, isNot(MessageStatus.failed));
  });

  test(
    've skupině se nedoručení eviduje u člena, stav zprávy zůstane',
    () async {
      await storage.saveGroup(
        Group(
          id: 'g1',
          name: 'Parta',
          memberIds: [me.id, bob.id, carol.id],
          createdBy: me.id,
        ),
      );
      await storage.saveConversation(
        Conversation(contactId: 'g1', messages: [mine('m1')]),
      );
      for (var i = 0; i < 3; i++) {
        await request(bob, [logged(bob, 'm1', conv: 'g1')]);
      }
      expect(sent.first.$2['gid'], 'g1');
      final m = await load('g1', 'm1');
      expect(m.undeliveredTo, {bob.id});
      expect(
        m.status,
        MessageStatus.delivered,
        reason: 'Carol zprávu má, stav skládají všichni',
      );
    },
  );

  test('kdo ze skupiny odešel, nic znovu nedostane', () async {
    await storage.saveGroup(
      Group(
        id: 'g1',
        name: 'Parta',
        memberIds: [me.id, carol.id],
        createdBy: me.id,
      ),
    );
    await storage.saveConversation(
      Conversation(contactId: 'g1', messages: [mine('m1')]),
    );
    await request(bob, [logged(bob, 'm1', conv: 'g1')]);
    expect(sent, isEmpty);
  });

  test(
    'síťová chyba při znovuposlání zprávu nechá odesílat, ne failed',
    () async {
      await storage.saveConversation(
        Conversation(contactId: bob.id, messages: [mine('m1')]),
      );
      sendError = const SocketException('spojení spadlo');
      await request(bob, [logged(bob, 'm1')]);
      final m = await load(bob.id, 'm1');
      expect(
        m.status,
        MessageStatus.sending,
        reason: 'dodatečné odeslání ji zkusí po připojení',
      );
      expect(m.undeliveredTo, isEmpty);
    },
  );

  test('zmizelá zpráva vezme záznam o obálce s sebou', () async {
    final old = Message(
      id: 'm1',
      senderId: me.id,
      recipientId: bob.id,
      type: MessageType.text,
      content: 'mizí',
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      disappearAfterSeconds: 5,
    );
    await storage.saveConversation(
      Conversation(contactId: bob.id, messages: [old]),
    );
    final ref = logged(bob, 'm1');
    final rx = logged(bob, 'm1', kind: 'rx');
    expect(await storage.purgeExpiredMessages(), isTrue);
    expect(db.sentLogTake(base64Decode(ref), bob.id), isNull);
    expect(db.sentLogTake(base64Decode(rx), bob.id), isNull);
  });

  test('limit žádostí o znovuposlání přežije restart appky', () async {
    final sender = SepotSealedSender(
      name: 'a' * 32,
      deviceId: 1,
      identityKey: bob.publicIdentity.identityKey,
      certificateExpiresAtMs: 0,
      messageType: SepotSealedSender.typeWhisper,
    );
    for (var i = 0; i < 6; i++) {
      await service.debugRequestResend(sender, bytes(16), resetSession: true);
      await service.debugFlushResendRequests();
    }
    expect(resendRequestsTo(bob), hasLength(6));

    // „Zabitá“ appka: nová instance služby nad touž DB.
    service = newService();
    await service.debugRequestResend(sender, bytes(16), resetSession: true);
    await service.debugFlushResendRequests();
    expect(
      resendRequestsTo(bob),
      hasLength(6),
      reason: 'sedmá žádost v hodině neodejde',
    );
  });

  Uint8List journaled() {
    final uuid = bytes(16);
    db.inboxPut(
      msgUuid: uuid,
      senderName: 'b' * 32,
      senderDevice: 1,
      senderIdentity: bob.publicIdentity.identityKey,
      plaintext: utf8.encode(
        jsonEncode({
          'v': 1,
          't': 'txt',
          'id': 'x1',
          'txt': 'jed',
          'p': {'n': 'Bob'},
        }),
      ),
    );
    return uuid;
  }

  test(
    'obsah, který nejde zpracovat, se vzdá a odesílatel ho pošle znovu',
    () async {
      final uuid = journaled();
      service.debugBeforeProcess = () async => throw StateError('úložiště');
      for (var i = 0; i < 4; i++) {
        await service.debugReplayInbox();
        expect(
          db.inboxGet(uuid)!.plaintext,
          isNotNull,
          reason: 'selhání ${i + 1}: ještě má šanci',
        );
      }
      await service.debugReplayInbox();
      final entry = db.inboxGet(uuid)!;
      expect(entry.done, isTrue);
      expect(entry.plaintext, isNull, reason: 'obsah nesmí ležet na disku');

      await service.debugFlushResendRequests();
      expect(
        resendRequestsTo(bob),
        hasLength(1),
        reason: 'odesílatel jinak dál vidí „doručeno“',
      );
    },
  );

  test('zabití appky uprostřed zpracování pokus nespálí', () async {
    final uuid = journaled();
    // Zpracování, které nikdy nedoběhne: iOS appku na pozadí zabije.
    service.debugBeforeProcess = () => Completer<void>().future;
    for (var i = 0; i < 6; i++) {
      unawaited(service.debugReplayInbox());
      await Future<void>.delayed(Duration.zero);
    }
    final attempts = db.raw.select(
      'SELECT attempts FROM inbox WHERE msg_uuid = ?',
      [uuid],
    ).first['attempts'];
    expect(attempts, 0);
    expect(db.inboxGet(uuid)!.plaintext, isNotNull);
  });

  test('smazání zprávy jen u mě vezme záznam o obálce s sebou', () async {
    await storage.saveConversation(
      Conversation(contactId: bob.id, messages: [mine('m1')]),
    );
    final ref = logged(bob, 'm1');
    await storage.deleteMessageLocally(bob.id, 'm1');
    expect((await storage.loadConversation(bob.id))!.messages, isEmpty);
    expect(db.sentLogTake(base64Decode(ref), bob.id), isNull);
  });
}
