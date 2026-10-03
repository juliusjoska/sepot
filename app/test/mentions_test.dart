import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/message.dart';

/// Zmínky přicházejí od cizích klientů — vadný tvar nesmí rozbít zprávu
/// a počet je shora omezený.
void main() {
  test('platné zmínky projdou', () {
    expect(mentionsFromWire(['aa11', 'bb22']), ['aa11', 'bb22']);
  });

  test('ne-seznam a ne-řetězce se zahodí', () {
    expect(mentionsFromWire('aa11'), isEmpty);
    expect(mentionsFromWire(null), isEmpty);
    expect(mentionsFromWire(['aa11', 42, null, {'x': 1}]), ['aa11']);
  });

  test('počet je omezený stropem členů skupiny', () {
    final many = List.generate(Group.maxMembers + 50, (i) => 'fp$i');
    expect(mentionsFromWire(many), hasLength(Group.maxMembers));
  });

  test('zmínky přežijí uložení a načtení zprávy', () {
    final m = Message.text(
      senderId: 'me',
      recipientId: 'gid',
      content: 'ahoj @Alice',
      mentions: const ['alice-fp'],
    );
    expect(Message.fromJson(m.toJson()).mentions, ['alice-fp']);
  });

  test('zpráva bez zmínek je neukládá', () {
    final m = Message.text(senderId: 'me', recipientId: 'x', content: 'a');
    expect(m.toJson().containsKey('mentions'), isFalse);
    expect(Message.fromJson(m.toJson()).mentions, isEmpty);
  });
}
