import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/models/message.dart';

void main() {
  test('reakce/edit/delete přežijí JSON roundtrip', () {
    final m = Message.text(senderId: 'me', recipientId: 'you', content: 'ahoj')
        .copyWith(
      reactions: {'FP1': '👍', 'FP2': '❤️'},
      editedAt: DateTime.parse('2026-07-06T20:00:00.000'),
    );
    final back =
        Message.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
    expect(back.reactions, {'FP1': '👍', 'FP2': '❤️'});
    expect(back.editedAt, isNotNull);
    expect(back.isDeleted, isFalse);
  });

  test('smazaná zpráva: isDeleted + prázdný obsah', () {
    final m = Message.text(senderId: 'me', recipientId: 'you', content: 'x')
        .copyWith(isDeleted: true, content: '', reactions: const {});
    final back =
        Message.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
    expect(back.isDeleted, isTrue);
    expect(back.content, '');
  });

  test('reply nese replyToId', () {
    final m = Message.text(
        senderId: 'me', recipientId: 'you', content: 'odpoved', replyToId: 'abc');
    final back =
        Message.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
    expect(back.replyToId, 'abc');
  });
}
