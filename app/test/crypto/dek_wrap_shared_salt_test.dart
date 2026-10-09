import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/dek_wrap.dart';

/// Skutečný a nátlakový blob se sdílenou solí se zkouší jednou derivací:
/// který PIN padl, nejde poznat z času odemčení.
void main() {
  final real = Uint8List.fromList(List.generate(32, (i) => i));
  final decoy = Uint8List.fromList(List.generate(32, (i) => 255 - i));
  // Nejslabší povolené parametry — test nemá čekat na 64 MiB derivaci.
  const m = DekWrap.floorMemoryKiB;
  const t = DekWrap.floorIterations;

  test('sdílená sůl: oba PINy se najdou, špatný PIN padne', () async {
    final wReal = await DekWrap.wrap(
        dek: real, pin: '111111', memoryKiB: m, iterations: t);
    final salt = DekWrap.saltOf(wReal);
    final wDecoy = await DekWrap.wrap(
        dek: decoy, pin: '222222', memoryKiB: m, iterations: t, salt: salt);
    expect(DekWrap.saltOf(wDecoy), salt);

    final (i1, d1) = await DekWrap.unwrapFirstMatching(
        wrapped: [wReal, wDecoy], pin: '111111');
    expect(i1, 0);
    expect(d1, real);

    final (i2, d2) = await DekWrap.unwrapFirstMatching(
        wrapped: [wReal, wDecoy], pin: '222222');
    expect(i2, 1);
    expect(d2, decoy);

    await expectLater(
      DekWrap.unwrapFirstMatching(wrapped: [wReal, wDecoy], pin: '333333'),
      throwsA(isA<WrongPinException>()),
    );
  });

  test('různé soli (starší instalace) fungují dál', () async {
    final wReal = await DekWrap.wrap(
        dek: real, pin: '111111', memoryKiB: m, iterations: t);
    final wDecoy = await DekWrap.wrap(
        dek: decoy, pin: '222222', memoryKiB: m, iterations: t);
    final (i, d) = await DekWrap.unwrapFirstMatching(
        wrapped: [wReal, wDecoy], pin: '222222');
    expect(i, 1);
    expect(d, decoy);
  });
}
