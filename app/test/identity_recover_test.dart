import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/mnemonic.dart';

// Obnova účtu stojí na reverzibilitě mnemonicu: 24 slov -> týž privátní
// klíč. Plnou identitu (LocalIdentity.create/recover) nejde testovat v čistém
// Dart VM — libsignal je native. Tady ověřujeme to podstatné bez native.
void main() {
  test('mnemonic round-trip je stabilní (základ obnovy účtu)', () {
    final key = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff));
    final words = SepotMnemonic.encode(key);
    expect(words.length, 24);
    expect(SepotMnemonic.isValid(words), isTrue);

    final decoded = SepotMnemonic.decode(words);
    // deserialize -> serialize stabilní: obnova vždy vrátí identická slova/klíč
    expect(SepotMnemonic.encode(decoded), words);
    expect(SepotMnemonic.decode(SepotMnemonic.encode(decoded)), decoded);
  });

  test('neplatná fráze se pozná', () {
    final words = SepotMnemonic.encode(Uint8List.fromList(List.filled(32, 0x11)));
    expect(SepotMnemonic.isValid(words.sublist(0, 23)), isFalse); // málo slov
    final broken = [...words]..[0] = 'zzzzzz';
    expect(SepotMnemonic.isValid(broken), isFalse); // neznámé slovo
  });
}
