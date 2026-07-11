/// Obnova identity přes mnemonic — BIP39 wordlist jako REVERZIBILNÍ
/// ENKÓDOVÁNÍ 32B privátního identity klíče.
///
/// Žádné KDF, žádný seed: 24 slov je přímý zápis bajtů klíče + checksum.
/// `decode(encode(klic)) == klic` platí bit po bitu — hlídají to KAT testy.
///
/// DŮLEŽITÉ: enkóduje se SERIALIZOVANÝ privátní klíč (výstup fasády
/// SepotCrypto, už clampnutý pro Curve25519). Díky tomu je
/// deserialize→serialize stabilní a mnemonic vždy obnoví identický klíč.
library;

import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart' show hex;
import 'package:sepot/core/errors.dart';

class SepotMnemonic {
  SepotMnemonic._();

  /// 32 B entropie = 24 slov BIP39 (256 bitů + 8bit checksum).
  static const int wordCount = 24;
  static const int keyLength = 32;

  /// Serializovaný privátní klíč (32 B) → 24 slov.
  static List<String> encode(Uint8List privateKey) {
    if (privateKey.length != keyLength) {
      throw ArgumentError.value(
        privateKey.length,
        'privateKey',
        'Expected $keyLength bytes of serialized private key',
      );
    }
    return bip39.entropyToMnemonic(hex.encode(privateKey)).split(' ');
  }

  /// 24 slov → 32 B privátního klíče.
  ///
  /// Vyhodí [MnemonicWordCountError] při špatném počtu slov a
  /// [MnemonicInvalidError] při neznámém slovu nebo nesedícím checksumu
  /// (překlep uživatele) — UI je překládá přes describeError.
  static Uint8List decode(List<String> words) {
    final normalized = _normalize(words);
    if (normalized.length != wordCount) {
      throw MnemonicWordCountError(normalized.length, wordCount);
    }
    final String entropyHex;
    try {
      entropyHex = bip39.mnemonicToEntropy(normalized.join(' '));
    } on ArgumentError catch (e) {
      // bip39 hlásí neznámé slovo / špatný checksum přes ArgumentError a
      // StateError — pro UI sjednocujeme na typovanou chybu
      throw MnemonicInvalidError('${e.message}');
    } on StateError catch (e) {
      throw MnemonicInvalidError(e.message);
    }
    return Uint8List.fromList(hex.decode(entropyHex));
  }

  /// Rychlá validace pro UI (živá kontrola při zadávání).
  static bool isValid(List<String> words) {
    final normalized = _normalize(words);
    if (normalized.length != wordCount) return false;
    return bip39.validateMnemonic(normalized.join(' '));
  }

  static List<String> _normalize(List<String> words) => words
      .expand((w) => w.trim().toLowerCase().split(RegExp(r'\s+')))
      .where((w) => w.isNotEmpty)
      .toList();
}
