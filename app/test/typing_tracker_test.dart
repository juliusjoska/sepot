import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/services/typing_tracker.dart';

/// „píše…“ nemá zprávu „dopsal jsem“ — indikátor musí sám vyhasnout,
/// jinak by po ztraceném spojení svítil navždy.
void main() {
  late DateTime now;
  late TypingTracker tracker;

  setUp(() {
    now = DateTime(2026, 9, 29, 12);
    tracker = TypingTracker(clock: () => now);
  });

  tearDown(() => tracker.dispose());

  test('pisatel se ukáže v dané konverzaci', () {
    tracker.mark('chat-a', 'alice');
    expect(tracker.current, {
      'chat-a': {'alice'},
    });
  });

  test('bez dalšího „píšu“ indikátor vyprší', () {
    tracker.mark('chat-a', 'alice');
    now = now.add(TypingTracker.showFor + const Duration(milliseconds: 1));
    expect(tracker.current, isEmpty);
    tracker.prune();
    expect(tracker.current, isEmpty);
  });

  test('opakované „píšu“ prodlužuje', () {
    tracker.mark('chat-a', 'alice');
    now = now.add(const Duration(seconds: 4));
    tracker.mark('chat-a', 'alice');
    now = now.add(const Duration(seconds: 4));
    expect(tracker.current['chat-a'], {'alice'});
  });

  test('příchozí zpráva indikátor hned zhasne', () {
    tracker
      ..mark('skupina', 'alice')
      ..mark('skupina', 'tomas')
      ..clear('skupina', 'alice');
    expect(tracker.current, {
      'skupina': {'tomas'},
    });
  });

  test('změny se hlásí posluchačům', () async {
    final events = <Map<String, Set<String>>>[];
    final sub = tracker.changes.listen(events.add);
    tracker
      ..mark('chat-a', 'alice')
      ..clear('chat-a', 'alice');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events, [
      {
        'chat-a': {'alice'},
      },
      <String, Set<String>>{},
    ]);
  });
}
