import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/dek_wrap.dart';

/// S9: PIN musí být klíčem k DEK, ne hashem na porovnání. Testy běží
/// na OWASP floor parametrech (rychlejší, ale pořád reálné krypto).
void main() {
  final rng = Random.secure();

  Uint8List randomDek() =>
      Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));

  Future<String> wrapFloor(Uint8List dek, String pin) => DekWrap.wrap(
        dek: dek,
        pin: pin,
        memoryKiB: DekWrap.floorMemoryKiB,
        iterations: DekWrap.floorIterations,
      );

  test('wrap → unwrap se správným PINem vrátí původní DEK', () async {
    final dek = randomDek();
    final wrapped = await wrapFloor(dek, '123456');

    final unwrapped = await DekWrap.unwrap(wrapped: wrapped, pin: '123456');
    expect(unwrapped, dek);
  });

  test('wrap blob neobsahuje DEK ani PIN v čitelné podobě', () async {
    final dek = randomDek();
    final wrapped = await wrapFloor(dek, '123456');

    expect(wrapped, startsWith('sepot-dek-v1:'));
    expect(wrapped.contains('123456'), isFalse);
    // ciphertext části nesmí být DEK samotný
    expect(wrapped.contains(String.fromCharCodes(dek)), isFalse);
  });

  test('špatný PIN → WrongPinException (GCM tag nesedí)', () async {
    final wrapped = await wrapFloor(randomDek(), '123456');

    await expectLater(
      DekWrap.unwrap(wrapped: wrapped, pin: '654321'),
      throwsA(isA<WrongPinException>()),
    );
  });

  test('zmanipulovaný ciphertext → WrongPinException', () async {
    final wrapped = await wrapFloor(randomDek(), '123456');
    final parts = wrapped.split(':');
    // přepiš ciphertext (index 6) validním base64 jiného obsahu
    parts[6] = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    final tampered = parts.join(':');

    await expectLater(
      DekWrap.unwrap(wrapped: tampered, pin: '123456'),
      throwsA(isA<WrongPinException>()),
    );
  });

  test('parametry pod OWASP floor se odmítnou při wrap i unwrap', () async {
    // wrap: slabé parametry nesmí vůbec vzniknout
    await expectLater(
      DekWrap.wrap(dek: randomDek(), pin: '123456', memoryKiB: 1024),
      throwsA(isA<StateError>()),
    );

    // unwrap: podvržený blob se slabými parametry nesmí ani začít derivovat
    final weakBlob = [
      'sepot-dek-v1', '1024', '1', '1',
      'AAAAAAAAAAAAAAAAAAAAAA==', 'AAAAAAAAAAAAAAAA',
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', 'AAAAAAAAAAAAAAAAAAAAAA==',
    ].join(':');
    await expectLater(
      DekWrap.unwrap(wrapped: weakBlob, pin: '123456'),
      throwsA(isA<StateError>()),
    );
  });

  test('neznámý formát/verze → FormatException', () async {
    await expectLater(
      DekWrap.unwrap(wrapped: 'garbage', pin: '123456'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      DekWrap.unwrap(wrapped: 'sepot-dek-v99:a:b:c:d:e:f:g', pin: '123456'),
      throwsA(isA<FormatException>()),
    );
  });

  test('DEK jiné délky než 32 B se odmítne', () async {
    await expectLater(
      DekWrap.wrap(dek: Uint8List(16), pin: '123456'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
