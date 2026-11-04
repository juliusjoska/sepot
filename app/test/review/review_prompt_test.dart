import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/review/review_prompt.dart';

void main() {
  late Map<String, int> store;
  late DateTime now;
  late bool enabled;

  ReviewPrompt prompt() => ReviewPrompt(
        read: (k) async => store[k],
        write: (k, v) async => store[k] = v,
        enabled: () => enabled,
        clock: () => now,
      );

  Future<void> send(ReviewPrompt p, int n) async {
    for (var i = 0; i < n; i++) {
      await p.noteMessageSent();
    }
  }

  setUp(() {
    store = {};
    now = DateTime(2026, 11, 1, 12);
    enabled = true;
  });

  test('první spuštění se jen zapíše, neptá se', () async {
    final p = prompt();
    await send(p, 50);
    expect(await p.shouldAsk(), isFalse);
    expect(store[ReviewPrompt.firstUseKey], isNotNull);
  });

  test('po 3 dnech a 20 zprávách se zeptá', () async {
    final p = prompt();
    await p.shouldAsk();
    await send(p, ReviewPrompt.minSentMessages);
    now = now.add(const Duration(days: ReviewPrompt.minDaysInUse));
    expect(await p.shouldAsk(), isTrue);
  });

  test('málo zpráv nebo brzy po instalaci = neptat', () async {
    final p = prompt();
    await p.shouldAsk();
    await send(p, ReviewPrompt.minSentMessages - 1);
    now = now.add(const Duration(days: 30));
    expect(await p.shouldAsk(), isFalse);

    store.clear();
    now = DateTime(2026, 11, 1, 12);
    await p.shouldAsk();
    await send(p, ReviewPrompt.minSentMessages);
    now = now.add(const Duration(days: ReviewPrompt.minDaysInUse - 1));
    expect(await p.shouldAsk(), isFalse);
  });

  test('po dotazu pauza 120 dní, nejvýš třikrát', () async {
    final p = prompt();
    await p.shouldAsk();
    await send(p, ReviewPrompt.minSentMessages);
    now = now.add(const Duration(days: ReviewPrompt.minDaysInUse));

    for (var i = 0; i < ReviewPrompt.maxAsks; i++) {
      expect(await p.shouldAsk(), isTrue, reason: 'dotaz ${i + 1}');
      await p.markAsked();
      now = now.add(const Duration(days: ReviewPrompt.daysBetweenAsks - 1));
      expect(await p.shouldAsk(), isFalse, reason: 'pauza po ${i + 1}');
      now = now.add(const Duration(days: 1));
    }
    expect(await p.shouldAsk(), isFalse, reason: 'strop dotazů');
  });

  test('nátlakový režim nic nepočítá ani se neptá', () async {
    final p = prompt();
    await p.shouldAsk();
    await send(p, ReviewPrompt.minSentMessages);
    now = now.add(const Duration(days: 10));
    enabled = false;
    expect(await p.shouldAsk(), isFalse);
    await p.noteMessageSent();
    expect(store[ReviewPrompt.sentCountKey], ReviewPrompt.minSentMessages);
  });
}
