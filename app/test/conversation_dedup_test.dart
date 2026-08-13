import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/message.dart';

/// Id zprávy nese odesílatel, takže tatáž zpráva může dorazit dvakrát:
/// odesílatel ji po výpadku spojení pošle znovu (fronta odchozích) nebo ji
/// relay doručí opakovaně, než dorazí ACK. Ani v jednom případě nesmí
/// vzniknout druhá bublina.
void main() {
  Message zprava(String id, {String text = 'ahoj'}) => Message(
        id: id,
        senderId: 'alice',
        recipientId: 'bob',
        type: MessageType.text,
        content: text,
        timestamp: DateTime.parse('2026-08-13T09:00:00.000'),
      );

  test('zpráva se stejným id se podruhé nepřidá', () {
    final c = Conversation(contactId: 'bob');

    expect(c.addMessage(zprava('m1')), isTrue, reason: 'první doručení');
    expect(c.addMessage(zprava('m1')), isFalse, reason: 'opakované doručení');
    expect(c.messages.length, 1);
  });

  test('dedup se řídí id, ne obsahem — stejný text jinou zprávou projde', () {
    final c = Conversation(contactId: 'bob');

    expect(c.addMessage(zprava('m1', text: 'ahoj')), isTrue);
    expect(c.addMessage(zprava('m2', text: 'ahoj')), isTrue);
    expect(c.messages.length, 2);
  });

  test('duplicita nechá původní zprávu být', () {
    final c = Conversation(contactId: 'bob');
    c.addMessage(zprava('m1', text: 'původní'));

    c.addMessage(zprava('m1', text: 'přepsaný'));

    expect(c.messages.single.content, 'původní');
  });
}
