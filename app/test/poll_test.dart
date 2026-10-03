import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/models/poll.dart';

/// Anketa přichází od protistrany — vadná data nesmí nic rozbít a hlas
/// nesmí jít mimo nabídnuté možnosti.
void main() {
  const poll = Poll(
    question: 'Kdy vyrazíme?',
    options: ['Pátek', 'Sobota', 'Neděle'],
  );

  test('drát tam a zpět zachová otázku i možnosti', () {
    final back = Poll.fromWire(poll.toWire())!;
    expect(back.question, poll.question);
    expect(back.options, poll.options);
    expect(back.multi, isFalse);
  });

  test('vadná anketa z drátu = null (ukáže se záložní text)', () {
    expect(Poll.fromWire(null), isNull);
    expect(Poll.fromWire({'q': 'Jen jedna?', 'o': ['a']}), isNull);
    expect(Poll.fromWire({'q': '', 'o': ['a', 'b']}), isNull);
    expect(Poll.fromWire({'q': 'x', 'o': ['a', 42]}), isNull);
    expect(
        Poll.fromWire({'q': 'x', 'o': List.filled(Poll.maxOptions + 1, 'a')}),
        isNull);
    expect(
        Poll.fromWire({'q': 'x' * (Poll.maxQuestionLength + 1), 'o': ['a', 'b']}),
        isNull);
  });

  test('hlas mimo nabídku se zahodí', () {
    final p = poll.withVote('bob', [7, -1]);
    expect(p.votes, isEmpty);
  });

  test('jedna volba: platí jen první index', () {
    final p = poll.withVote('bob', [2, 0]);
    expect(p.votes['bob'], [0]);
  });

  test('více voleb: duplicity se sloučí', () {
    const multi = Poll(question: 'Co vezmeme?', options: ['a', 'b', 'c'], multi: true);
    final p = multi.withVote('bob', [2, 0, 2]);
    expect(p.votes['bob'], [0, 2]);
    expect(p.countFor(2), 1);
  });

  test('nový hlas přepíše starý, prázdný ho zruší', () {
    var p = poll.withVote('bob', [0]).withVote('cyril', [0]);
    expect(p.countFor(0), 2);
    p = p.withVote('bob', [1]);
    expect(p.countFor(0), 1);
    expect(p.countFor(1), 1);
    p = p.withVote('bob', const []);
    expect(p.voterCount, 1);
  });

  test('hlasy přežijí uložení zprávy', () {
    final msg = Message.text(
      senderId: 'ja',
      recipientId: 'chata',
      content: 'Anketa: Kdy vyrazíme?',
      poll: poll.withVote('bob', [1]),
    );
    final back = Message.fromJson(msg.toJson());
    expect(back.poll?.question, poll.question);
    expect(back.poll?.votes['bob'], [1]);
  });
}
