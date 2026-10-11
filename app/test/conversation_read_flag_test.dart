import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/message.dart';

/// Read state only moves forward. Updates that carry an older copy of the
/// message (attachment download finishing, delivery status) must not flip a
/// message the user has already read back to unread.
void main() {
  Message zprava({bool isRead = false}) => Message(
    id: 'm1',
    senderId: 'alice',
    recipientId: 'bob',
    type: MessageType.text,
    content: 'hi',
    timestamp: DateTime.parse('2026-10-10T09:00:00.000'),
    isRead: isRead,
  );

  test('stale unread copy does not undo a read message', () {
    final c = Conversation(contactId: 'alice')..addMessage(zprava());
    c.markAllRead('bob');

    c.updateMessage(zprava().copyWith(content: 'hi (edited)'));

    expect(c.messages.single.isRead, isTrue);
    expect(c.messages.single.content, 'hi (edited)');
    expect(c.unreadCount('bob'), 0);
  });

  test('update can still mark an unread message as read', () {
    final c = Conversation(contactId: 'alice')..addMessage(zprava());

    c.updateMessage(zprava(isRead: true));

    expect(c.unreadCount('bob'), 0);
  });
}
