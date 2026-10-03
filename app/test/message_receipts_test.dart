import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/models/message.dart';

/// Doručenky a potvrzení přečtení nesou čas od příjemce; stav mé zprávy
/// z nich roste, ale nikdy neklesá.
void main() {
  final odeslano = DateTime(2026, 9, 28, 14, 0);

  Message moje({MessageStatus status = MessageStatus.sent}) => Message(
        id: 'm1',
        senderId: 'ja',
        recipientId: 'bob',
        type: MessageType.text,
        content: 'ahoj',
        timestamp: odeslano,
        status: status,
      );

  Message receipt(Message m, String from, int minut,
          {bool read = false, int recipients = 1}) =>
      MessagingService.applyReceipt(
        m,
        from: from,
        at: odeslano.add(Duration(minutes: minut)),
        read: read,
        recipients: recipients,
      );

  test('doručenka zapíše čas a povýší na doručeno', () {
    final m = receipt(moje(), 'bob', 1);
    expect(m.status, MessageStatus.delivered);
    expect(m.deliveredTo['bob'], odeslano.add(const Duration(minutes: 1)));
    expect(m.firstReadAt, isNull);
  });

  test('přečtení zároveň znamená doručení', () {
    final m = receipt(moje(), 'bob', 5, read: true);
    expect(m.status, MessageStatus.read);
    expect(m.firstDeliveredAt, m.firstReadAt);
  });

  test('pozdní doručenka po přečtení stav nesníží', () {
    // Doručenka poslaná znovu po výpadku spojení dorazí až po „přečteno".
    var m = receipt(moje(), 'bob', 5, read: true);
    m = receipt(m, 'bob', 9);
    expect(m.status, MessageStatus.read);
  });

  test('opakované potvrzení nepřepíše první čas', () {
    var m = receipt(moje(), 'bob', 2);
    m = receipt(m, 'bob', 30);
    expect(m.deliveredTo['bob'], odeslano.add(const Duration(minutes: 2)));
  });

  test('doručenka zachrání zprávu označenou jako neodeslaná', () {
    // Timeout před ACK relaye → failed, přitom zpráva dorazila.
    final m = receipt(moje(status: MessageStatus.failed), 'bob', 1);
    expect(m.status, MessageStatus.delivered);
  });

  test('opožděné hodiny příjemce nepřečtou zprávu před odesláním', () {
    final m = receipt(moje(), 'bob', -10, read: true);
    expect(m.firstReadAt, odeslano);
  });

  test('skupina: ✓✓ a přečteno až za všechny ostatní členy', () {
    var m = receipt(moje(), 'bob', 1, recipients: 2);
    expect(m.status, MessageStatus.sent);
    m = receipt(m, 'cyril', 2, recipients: 2);
    expect(m.status, MessageStatus.delivered);
    m = receipt(m, 'bob', 3, read: true, recipients: 2);
    expect(m.status, MessageStatus.delivered);
    m = receipt(m, 'cyril', 4, read: true, recipients: 2);
    expect(m.status, MessageStatus.read);
    expect(m.firstReadAt, odeslano.add(const Duration(minutes: 3)));
  });

  test('časy přežijí uložení a načtení', () {
    final m = receipt(receipt(moje(), 'bob', 1), 'bob', 4, read: true);
    final zpet = Message.fromJson(m.toJson());
    expect(zpet.deliveredTo, m.deliveredTo);
    expect(zpet.readBy, m.readBy);
  });

  test('starý záznam bez časů i vadné položky se načtou', () {
    final json = moje().toJson()
      ..remove('deliveredTo')
      ..['readBy'] = {'bob': 'včera', 'cyril': 1790000000000};
    final m = Message.fromJson(json);
    expect(m.deliveredTo, isEmpty);
    expect(m.readBy.keys, ['cyril']);
  });
}
