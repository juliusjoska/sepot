import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/services/messaging_service.dart';

/// Čas zprávy musí pocházet od odesílatele, ne z okamžiku doručení.
/// Regrese: bez `ts` na drátě dostal každý příjemce vlastní `DateTime.now()`,
/// takže po vyzvednutí offline fronty uskočila celá konverzace na „teď"
/// a každý člen skupiny viděl u téže zprávy jiný čas.
void main() {
  test('čas odesílatele z drátu se použije beze změny', () {
    final odeslano = DateTime(2026, 8, 10, 14, 30);
    final t = MessagingService.wireSentAt(odeslano.millisecondsSinceEpoch);
    expect(t, odeslano);
  });

  test('starý klient bez ts → fallback na čas doručení', () {
    final pred = DateTime.now();
    final t = MessagingService.wireSentAt(null);
    expect(t.isBefore(pred.subtract(const Duration(seconds: 5))), isFalse);
  });

  test('netypové ts (string z drátu) → fallback, nespadne', () {
    final pred = DateTime.now();
    final t = MessagingService.wireSentAt('2026-08-10T14:30:00Z');
    expect(t.isBefore(pred.subtract(const Duration(seconds: 5))), isFalse);
  });

  test('rozejité hodiny v toleranci se přijmou', () {
    // Přes drát jde epocha v ms, takže mikrosekundy z DateTime.now() padnou
    // pod stůl — porovnáváme na milisekundy, ne na identitu objektu.
    final skoroTed = DateTime.now().add(const Duration(minutes: 3));
    final t = MessagingService.wireSentAt(skoroTed.millisecondsSinceEpoch);
    expect(t.millisecondsSinceEpoch, skoroTed.millisecondsSinceEpoch);
  });

  test('čas z budoucnosti nad strop → čas doručení', () {
    final budoucnost = DateTime.now().add(const Duration(days: 365));
    final t = MessagingService.wireSentAt(budoucnost.millisecondsSinceEpoch);
    expect(t.isBefore(budoucnost), isTrue);
  });

  test('absurdně starý čas → čas doručení', () {
    final t = MessagingService.wireSentAt(
      DateTime(1999).millisecondsSinceEpoch,
    );
    expect(t.year, greaterThan(2020));
  });

  test('pořadí zpráv drží čas odeslání, ne pořadí doručení', () {
    // Fronta se vylije naráz, ale starší zpráva musí zůstat starší.
    final prvni = DateTime(2026, 8, 10, 9, 0);
    final druha = DateTime(2026, 8, 10, 9, 5);
    final a = MessagingService.wireSentAt(prvni.millisecondsSinceEpoch);
    final b = MessagingService.wireSentAt(druha.millisecondsSinceEpoch);
    expect(a.isBefore(b), isTrue);
  });
}
