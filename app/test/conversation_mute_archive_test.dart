import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/models/conversation.dart';

void main() {
  test('mute/archive přežijí JSON roundtrip', () {
    final c = Conversation(
      contactId: 'X',
      muted: true,
      mutedUntil: DateTime.parse('2026-07-09T10:00:00.000'),
      archived: true,
    );
    final back =
        Conversation.fromJson(jsonRoundtrip(c.toJson()));
    expect(back.muted, isTrue);
    expect(back.mutedUntil, DateTime.parse('2026-07-09T10:00:00.000'));
    expect(back.archived, isTrue);
  });

  test('legacy JSON bez nových klíčů projde s defaulty', () {
    final legacy = {
      'contactId': 'Y',
      'messages': <dynamic>[],
      'lastActivity': '2026-07-08T10:00:00.000',
      'disappearAfterSeconds': null,
    };
    final c = Conversation.fromJson(legacy);
    expect(c.muted, isFalse);
    expect(c.archived, isFalse);
    expect(c.mutedUntil, isNull);
    expect(c.isMuted, isFalse);
  });

  test('isMuted: dočasné ztlumení vyprší', () {
    final past = Conversation(
        contactId: 'Z',
        muted: true,
        mutedUntil: DateTime.now().subtract(const Duration(hours: 1)));
    expect(past.isMuted, isFalse); // vypršelo
    final future = Conversation(
        contactId: 'Z',
        muted: true,
        mutedUntil: DateTime.now().add(const Duration(hours: 1)));
    expect(future.isMuted, isTrue);
    final forever = Conversation(contactId: 'Z', muted: true);
    expect(forever.isMuted, isTrue);
  });
}

Map<String, dynamic> jsonRoundtrip(Map<String, dynamic> m) =>
    Map<String, dynamic>.from(m);
