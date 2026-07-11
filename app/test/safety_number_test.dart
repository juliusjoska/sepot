import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/safety_number.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';

void main() {
  setUpAll(() async {
    await SepotCrypto.init();
  });

  Uint8List fixedKey(int seed) {
    // deterministický „privátní klíč" → veřejný přes libsignal derivaci
    final priv = Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xFF));
    return SepotCrypto.derivePublicKey(priv);
  }

  test('obě strany vidí stejné číslo (symetrie)', () {
    final a = fixedKey(1);
    final b = fixedKey(2);
    final fromA = SafetyNumber.compute(localIdentityKey: a, remoteIdentityKey: b);
    final fromB = SafetyNumber.compute(localIdentityKey: b, remoteIdentityKey: a);
    expect(fromA.display, fromB.display);
  });

  test('60 číslic, 12 bloků po 5', () {
    final n = SafetyNumber.compute(
      localIdentityKey: fixedKey(1),
      remoteIdentityKey: fixedKey(2),
    );
    expect(n.display, matches(RegExp(r'^\d{60}$')));
    expect(n.groups, hasLength(12));
    expect(n.groups.every((g) => g.length == 5), isTrue);
  });

  test('jiný pár klíčů = jiné číslo', () {
    final ab = SafetyNumber.compute(
        localIdentityKey: fixedKey(1), remoteIdentityKey: fixedKey(2));
    final ac = SafetyNumber.compute(
        localIdentityKey: fixedKey(1), remoteIdentityKey: fixedKey(3));
    expect(ab.display, isNot(ac.display));
  });

  test('QR compare: protistrany si odpovídají, cizí ne', () {
    final a = fixedKey(1);
    final b = fixedKey(2);
    final mine = SafetyNumber.compute(localIdentityKey: a, remoteIdentityKey: b);
    final theirs = SafetyNumber.compute(localIdentityKey: b, remoteIdentityKey: a);
    final stranger = SafetyNumber.compute(
        localIdentityKey: a, remoteIdentityKey: fixedKey(9));

    expect(SafetyNumber.compare(mine.scannable, theirs.scannable), isTrue);
    expect(SafetyNumber.compare(mine.scannable, stranger.scannable), isFalse);
    // vadný vstup nesmí spadnout
    expect(
      SafetyNumber.compare(mine.scannable, Uint8List.fromList([1, 2, 3])),
      isFalse,
    );
  });

  test('KAT: zafixovaný výstup — změna = breaking change pro uživatele', () {
    final n = SafetyNumber.compute(
      localIdentityKey: fixedKey(1),
      remoteIdentityKey: fixedKey(2),
    );
    // Vygenerováno libsignal 5.0.9 (iterations=5200, version=2,
    // identifier=BLAKE2b-256(pubkey)). Pokud tenhle test spadne po
    // upgradu, VŠEM uživatelům se změní safety numbers → stop ship.
    expect(
      n.display,
      '289143504470406742912626343937385761080203728630218051783783',
    );
  });
}
