import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/utils/externi_obrazovka.dart';
import 'package:sepot/providers/settings_provider.dart';

void main() {
  bool zamknout(int nastaveni, int sekund, {bool externi = false}) =>
      AutoLockNotifier.maZamknout(
        nastaveni: nastaveni,
        pryc: Duration(seconds: sekund),
        kvuliExterniObrazovce: externi,
      );

  test('immediate lock fires the moment the app leaves the foreground', () {
    expect(zamknout(AutoLockNotifier.okamzite, 0), isTrue);
  });

  test('immediate lock tolerates the photo picker, but not forever', () {
    expect(zamknout(AutoLockNotifier.okamzite, 0, externi: true), isFalse);
    expect(zamknout(AutoLockNotifier.okamzite, 120, externi: true), isFalse);
    expect(
      zamknout(AutoLockNotifier.okamzite,
          AutoLockNotifier.limitExterniObrazovky, externi: true),
      isTrue,
    );
  });

  test('timed lock keeps its interval', () {
    expect(zamknout(300, 0), isFalse);
    expect(zamknout(300, 299), isFalse);
    expect(zamknout(300, 300), isTrue);
    expect(zamknout(60, 61, externi: true), isTrue);
  });

  test('never means never', () {
    expect(zamknout(0, 86400), isFalse);
  });

  test('menu offers immediate first and keeps never', () {
    expect(AutoLockNotifier.moznostiSekundy.first, AutoLockNotifier.okamzite);
    expect(AutoLockNotifier.moznostiSekundy, contains(0));
  });

  test('external screen flag covers the call and clears after errors', () async {
    final hotovo = Completer<void>();
    final vyber = ExterniObrazovka.behem(() => hotovo.future);
    expect(ExterniObrazovka.otevrena, isTrue);
    hotovo.complete();
    await vyber;
    expect(ExterniObrazovka.otevrena, isFalse);

    await expectLater(
      ExterniObrazovka.behem<void>(() async => throw StateError('picker')),
      throwsStateError,
    );
    expect(ExterniObrazovka.otevrena, isFalse);
  });
}
