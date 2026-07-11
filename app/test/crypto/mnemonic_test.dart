import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/mnemonic.dart';
import 'package:sepot/core/errors.dart';

/// KAT vektory z oficiální BIP39 test suite (Trezor) pro 256bit entropii.
/// Review-crypto F-3: mnemonic je REVERZIBILNÍ ENKÓDOVÁNÍ klíče — known-answer
/// testy jsou povinné v CI napříč Dart i Rust.
const _katVectors = <String, String>{
  '00000000000000000000000000000000'
          '00000000000000000000000000000000':
      'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon abandon abandon art',
  '7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f'
          '7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f':
      'legal winner thank year wave sausage worth useful legal winner '
          'thank year wave sausage worth useful legal winner thank year '
          'wave sausage worth title',
  '80808080808080808080808080808080'
          '80808080808080808080808080808080':
      'letter advice cage absurd amount doctor acoustic avoid letter '
          'advice cage absurd amount doctor acoustic avoid letter advice '
          'cage absurd amount doctor acoustic bless',
  'ffffffffffffffffffffffffffffffff'
          'ffffffffffffffffffffffffffffffff':
      'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo '
          'zoo zoo zoo zoo zoo zoo zoo vote',
};

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('SepotMnemonic KAT (oficiální BIP39 vektory)', () {
    _katVectors.forEach((entropyHex, expectedMnemonic) {
      test('entropy ${entropyHex.substring(0, 8)}… → známých 24 slov', () {
        final words = SepotMnemonic.encode(_hexToBytes(entropyHex));
        expect(words.join(' '), expectedMnemonic);
        expect(words, hasLength(SepotMnemonic.wordCount));
      });

      test('mnemonic ${expectedMnemonic.substring(0, 12)}… → přesná entropie',
          () {
        final decoded = SepotMnemonic.decode(expectedMnemonic.split(' '));
        expect(decoded, _hexToBytes(entropyHex));
      });
    });
  });

  group('SepotMnemonic roundtrip', () {
    test('decode(encode(k)) == k pro 100 náhodných klíčů', () {
      final rng = Random.secure();
      for (var i = 0; i < 100; i++) {
        final key = Uint8List.fromList(
          List.generate(32, (_) => rng.nextInt(256)),
        );
        expect(SepotMnemonic.decode(SepotMnemonic.encode(key)), key);
      }
    });

    test('normalizace: velká písmena a mezery navíc nevadí', () {
      final key = Uint8List(32);
      final words = SepotMnemonic.encode(key);
      final messy = words
          .map((w) => '  ${w.toUpperCase()}  ')
          .toList();
      expect(SepotMnemonic.decode(messy), key);
    });
  });

  group('SepotMnemonic chyby', () {
    final valid = SepotMnemonic.encode(Uint8List(32));

    test('špatný počet slov → MnemonicWordCountError', () {
      expect(
        () => SepotMnemonic.decode(valid.sublist(0, 23)),
        throwsA(isA<MnemonicWordCountError>()),
      );
    });

    test('neznámé slovo → MnemonicInvalidError', () {
      final broken = [...valid]..[0] = 'xylofon';
      expect(() => SepotMnemonic.decode(broken),
          throwsA(isA<MnemonicInvalidError>()));
    });

    test('rozbitý checksum (prohozená slova) → MnemonicInvalidError', () {
      // poslední slovo nese checksum — výměna prvních dvou RŮZNÝCH slov
      // checksum rozbije
      final words = SepotMnemonic.encode(
        Uint8List.fromList(List.generate(32, (i) => i * 7 % 256)),
      );
      final swapped = [...words];
      final j = swapped.indexWhere((w) => w != swapped[0]);
      swapped[0] = words[j];
      swapped[j] = words[0];
      expect(() => SepotMnemonic.decode(swapped),
          throwsA(isA<MnemonicInvalidError>()));
    });

    test('isValid odmítne nevalidní a přijme validní', () {
      expect(SepotMnemonic.isValid(valid), isTrue);
      expect(SepotMnemonic.isValid(valid.sublist(0, 12)), isFalse);
    });

    test('encode odmítne jinou délku než 32 B', () {
      expect(() => SepotMnemonic.encode(Uint8List(16)), throwsArgumentError);
      expect(() => SepotMnemonic.encode(Uint8List(64)), throwsArgumentError);
    });
  });
}
