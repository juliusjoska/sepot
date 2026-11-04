@Tags(['relay'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/network/relay_client.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/message.dart';

/// Ztrácení zpráv: dva plné MessagingService proti REÁLNÉMU
/// lokálnímu relayi, každý scénář z analýzy příčin zvlášť.
/// Spuštění: relay musí běžet (SEPOT_RELAY, default http://127.0.0.1:8470).
///   flutter test test/integration --tags relay
void main() {
  final relayUrl =
      Platform.environment['SEPOT_RELAY'] ?? 'http://127.0.0.1:8470';
  final rng = Random.secure();
  final phones = <_Phone>[];

  setUpAll(() async => SepotCrypto.init());

  final retired = <_Phone>[];

  tearDown(() async {
    for (final p in phones) {
      await p.service.stop();
    }
    retired.addAll(phones);
    phones.clear();
  });

  // Služba po stop() ještě dobíhá odeslání na pozadí (čekání na receipt má
  // timeout 10 s) a pak zapisuje do fronty řídicích zpráv — DB se proto
  // zavírá až na konci, ne mezi testy.
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(seconds: 11));
    for (final p in retired) {
      p.db.close();
      p.dir.deleteSync(recursive: true);
    }
  });

  Future<_Phone> phone(String name) async {
    final dir = Directory.systemTemp.createTempSync('sepot_doruceni');
    final dek = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    final db = CryptoDb.open(path: '${dir.path}/app.db', dek: dek);
    final storage = SecureStorageService(dbPath: '${dir.path}/app.db')
      ..debugAttachDb(db);
    final service = MessagingService(storage: storage, relayUrl: relayUrl);
    final p = _Phone(
      await LocalIdentity.create(name),
      storage,
      service,
      db,
      dir,
    );
    phones.add(p);
    await service.start(p.identity);
    await _until(
      () => service.accountId != null && p.connected,
      reason: '$name: registrace a připojení',
    );
    return p;
  }

  Future<void> befriend(_Phone a, _Phone b, {bool accepted = true}) async {
    await a.storage.saveContact(
      Contact.fromPublicIdentity(
        b.service.shareableIdentity!,
        accepted: accepted,
      ),
    );
    await b.storage.saveContact(
      Contact.fromPublicIdentity(a.service.shareableIdentity!),
    );
  }

  Future<void> exchange(_Phone a, _Phone b) async {
    await a.service.sendText(await a.contact(b), 'ahoj ${b.name}');
    await _until(() => b.has(a, 'ahoj ${b.name}'), reason: 'první zpráva');
    await b.service.sendText(await b.contact(a), 'ahoj ${a.name}');
    await _until(() => a.has(b, 'ahoj ${a.name}'), reason: 'odpověď');
  }

  test(
    '(a) ztracený ACK: znovu doručená obálka se potvrdí bez dešifrování',
    () async {
      final a = await phone('Alice');
      final b = await phone('Bob');
      await befriend(a, b);

      b.service.debugDropAcks = true;
      await a.service.sendText(await a.contact(b), 'ACK se ztratí');
      await _until(() => b.has(a, 'ACK se ztratí'), reason: 'doručeno');
      b.service.debugDropAcks = false;

      await b.restart();
      await _until(
        () => b.service.debugDeliveries > 0,
        reason: 'relay obálku bez ACK poslal znovu',
      );
      await _settle();
      await b.restart();
      await _settle();
      expect(
        b.service.debugDeliveries,
        0,
        reason: 'po druhém připojení už ve frontě nic není',
      );
      expect(await b.count(a, 'ACK se ztratí'), 1);
    },
  );

  test(
    '(b) pád po dešifrování před uložením: zpráva se po restartu obnoví',
    () async {
      final a = await phone('Alice');
      final b = await phone('Bob');
      await befriend(a, b);

      b.service.debugCrashAfterDecrypt = true;
      await a.service.sendText(await a.contact(b), 'přežije pád');
      await _until(() => b.service.debugDeliveries > 0, reason: 'doručeno');
      await _settle();
      expect(await b.has(a, 'přežije pád'), isFalse, reason: 'proces „spadl“');

      await b.restart();
      await _until(() => b.has(a, 'přežije pád'), reason: 'obnoveno z deníku');
      await _settle();
      await b.restart();
      await _settle();
      expect(b.service.debugDeliveries, 0, reason: 'obálka se potvrdila');
      expect(await b.count(a, 'přežije pád'), 1);
    },
  );

  test(
    '(c) příjemce ztratil relaci: požádá o znovuposlání, relace se obnoví',
    () async {
      final a = await phone('Alice');
      final b = await phone('Bob');
      await befriend(a, b);
      await exchange(a, b);

      b.db.raw.execute('DELETE FROM sessions WHERE name = ?', [
        a.service.accountId,
      ]);
      await a.service.sendText(await a.contact(b), 'po ztrátě relace');
      await _until(
        () => b.has(a, 'po ztrátě relace'),
        timeout: const Duration(seconds: 30),
        reason: 'Alice zprávu poslala znovu novou relací',
      );
      await _until(
        () async =>
            (await a.message(b, 'po ztrátě relace'))?.status ==
            MessageStatus.delivered,
      );

      await exchange(a, b);
      expect(await b.count(a, 'po ztrátě relace'), 1);
    },
  );

  test('(c) žádost o znovuposlání nejde k nepřijatému kontaktu', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await befriend(a, b);
    await exchange(a, b);
    // Bob Alici vede jen jako žádost o zprávu.
    final atBob = await b.contact(a);
    atBob.accepted = false;
    await b.storage.saveContact(atBob);

    b.db.raw.execute('DELETE FROM sessions WHERE name = ?', [
      a.service.accountId,
    ]);
    a.service.debugDeliveries = 0;
    await a.service.sendText(await a.contact(b), 'od cizího');
    await _until(() => b.service.debugDeliveries > 0);
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(a.service.debugDeliveries, 0, reason: 'Alice nedostala nic');

    await b.restart();
    await _settle();
    expect(
      b.service.debugDeliveries,
      0,
      reason: 'obálka je vyřízená, frontu neotravuje',
    );
  });

  test(
    '(c) obnova pořád selhává: odesílatel uvidí nedoručenou zprávu',
    () async {
      final a = await phone('Alice');
      final b = await phone('Bob');
      await befriend(a, b);
      await exchange(a, b);

      b.service.debugBeforeDecrypt = () async => b.db.raw.execute(
        'DELETE FROM sessions WHERE name = ?',
        [a.service.accountId],
      );
      await a.service.sendText(await a.contact(b), 'nikdy nedojde');
      await _until(
        () async =>
            (await a.message(b, 'nikdy nedojde'))?.status ==
            MessageStatus.failed,
        timeout: const Duration(seconds: 40),
        reason: 'po vyčerpání znovuposlání je zpráva nedoručená',
      );
      expect(await b.has(a, 'nikdy nedojde'), isFalse);
      final message = (await a.message(b, 'nikdy nedojde'))!;
      expect(message.undeliveredTo, {b.fp});

      // Další připojení (dodatečné odeslání zaseklých zpráv) ji už znovu
      // neposílá — jinak by se kolečko rtr → znovuposlání točilo 24 h.
      int envelopes() =>
          a.db.raw.select(
                'SELECT COUNT(*) AS n FROM sent_log WHERE target_id = ?',
                [message.id],
              ).first['n']
              as int;
      final before = envelopes();
      await a.restart();
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(envelopes(), before);
      expect(
        (await a.message(b, 'nikdy nedojde'))!.status,
        MessageStatus.failed,
      );
    },
  );

  test(
    '(c) obě strany založí relaci naráz: zprávy dojdou oběma směry',
    () async {
      final a = await phone('Alice');
      final b = await phone('Bob');
      await befriend(a, b);

      await Future.wait([
        a.service.sendText(await a.contact(b), 'naráz od Alice'),
        b.service.sendText(await b.contact(a), 'naráz od Boba'),
      ]);
      await _until(
        () async =>
            await b.has(a, 'naráz od Alice') && await a.has(b, 'naráz od Boba'),
      );
      await exchange(a, b);
      await exchange(b, a);
    },
  );

  test(
    '(d) trust root je připravený hned po startu, ne až po certifikátu',
    () async {
      final a = await phone('Alice');
      await a.service.stop();
      await a.service.start(a.identity);
      expect(
        a.service.debugTrustRootReady,
        isTrue,
        reason: 'obálky z fronty, které předběhnou certifikát, se zpracují',
      );
    },
  );

  test('(d) obálky, které přišly při zamykání, dojdou po odemčení', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await befriend(a, b);
    await exchange(a, b);

    await b.service.stop();
    await a.service.sendText(await a.contact(b), 'během zámku');
    await b.restart();
    await _until(() => b.has(a, 'během zámku'));
  });

  test('(e) certifikát vypršel, než si příjemce obálku vyzvedl', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await befriend(a, b);
    await exchange(a, b);

    // Bob byl déle než týden offline: certifikát Alice z doby odeslání
    // podle jeho hodin už neplatí.
    b.service.debugClock = () => DateTime.now().add(const Duration(days: 8));
    await a.service.sendText(await a.contact(b), 'po dovolené');
    await _until(() => b.has(a, 'po dovolené'));
  });

  test('(e) obálka starší, než ji relay drží, žádost o znovuposlání '
      'nevyvolá', () async {
    final a = await phone('Alice');
    final b = await phone('Bob');
    await befriend(a, b);
    await exchange(a, b);
    await _settle();

    // Certifikát vypršel před víc než 35 dny: taková obálka se do fronty
    // nevejde, jde o přehranou starou — reset relace kvůli ní nedává smysl.
    b.service.debugClock = () => DateTime.now().add(const Duration(days: 45));
    a.service.debugDeliveries = 0;
    b.service.debugDeliveries = 0;
    await a.service.sendText(await a.contact(b), 'přehraná');
    await _until(() => b.service.debugDeliveries > 0);
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(await b.has(a, 'přehraná'), isFalse);
    expect(a.service.debugDeliveries, 0, reason: 'Alice žádost nedostala');
  });

  for (final existing in [false, true]) {
    test('(e) PreKey zprávu se starým certifikátem nebere '
        '(${existing ? 'relace už je' : 'první kontakt'}) — odesílatel ji '
        'pošle s čerstvým', () async {
      final a = await phone('Alice');
      final b = await phone('Bob');
      await befriend(a, b);
      if (existing) {
        // Bob relaci má, Alice založí novou: PreKey zpráva by ji tiše
        // přepsala.
        await exchange(a, b);
        a.db.raw.execute('DELETE FROM sessions WHERE name = ?', [
          b.service.accountId,
        ]);
        await _settle();
      }
      int settled() => b.db.raw
          .select('SELECT 1 FROM inbox WHERE done_at IS NOT NULL')
          .length;
      final settledBefore = settled();

      // PreKey zpráva zakládá relaci: výjimka pro starý certifikát by tu
      // dovolila zakládat relace uniklým klíčem ještě měsíc.
      b.service.debugClock = () => DateTime.now().add(const Duration(days: 8));
      await a.service.sendText(await a.contact(b), 'po dovolené');
      await _until(
        () => settled() > settledBefore,
        reason: 'Bob obálku vyřídil',
      );
      expect(await b.has(a, 'po dovolené'), isFalse);

      // Žádost o znovuposlání odejde až po sběrné prodlevě; Bobovy hodiny
      // se mezitím vrátí do normálu.
      b.service.debugClock = DateTime.now;
      await _until(
        () => b.has(a, 'po dovolené'),
        reason: 'Alice ji poslala znovu s platným certifikátem',
      );
    });
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(seconds: 2));

Future<void> _until(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Nesplněno do ${timeout.inSeconds} s: ${reason ?? ''}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

class _Phone {
  _Phone(this.identity, this.storage, this.service, this.db, this.dir);

  final LocalIdentity identity;
  final SecureStorageService storage;
  final MessagingService service;
  final CryptoDb db;
  final Directory dir;

  String get name => identity.displayName;
  String get fp => identity.id;
  bool get connected =>
      service.connectionState == RelayConnectionState.connected;

  Future<Contact> contact(_Phone other) async =>
      (await storage.loadContacts()).firstWhere((c) => c.id == other.fp);

  Future<Message?> message(_Phone other, String text) async =>
      (await storage.loadConversation(
        other.fp,
      ))?.messages.where((m) => m.content == text).firstOrNull;

  Future<int> count(_Phone other, String text) async =>
      (await storage.loadConversation(
        other.fp,
      ))?.messages.where((m) => m.content == text).length ??
      0;

  Future<bool> has(_Phone other, String text) async =>
      await count(other, text) > 0;

  /// Zámek a odemčení appky: služba se zastaví a nastartuje znovu.
  Future<void> restart() async {
    await service.stop();
    service.debugDeliveries = 0;
    await service.start(identity);
    await _until(() => connected, reason: '$name: znovu připojeno');
  }
}
