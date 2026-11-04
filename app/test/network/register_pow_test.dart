import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/network/register_pow.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _counterBe(int counter) {
  final d = ByteData(8)
    ..setUint32(0, counter ~/ 0x100000000)
    ..setUint32(4, counter & 0xffffffff);
  return d.buffer.asUint8List();
}

void main() {
  // Stejné vektory jako relay (rust/sepot-relay/src/pow.rs,
  // vektory_kompatibilni_s_klientem), spočítané nezávisle i Pythonem hashlib.
  final token = Uint8List.fromList(List.generate(42, (i) => i));
  final identityKey = Uint8List.fromList(List.filled(33, 5));
  final prefix = powPrefix(token, identityKey);

  group('vektory sdílené s relayem', () {
    test('digest pro čítač 0 a velký čítač', () {
      final s = PowSearcher(prefix);
      expect(
        _hex(s.digest(0)),
        'ab9d9008c6ad674271da019b142f25cba7045107da67ad0938fd90a3d096d90a',
      );
      expect(
        _hex(s.digest(0x0123456789abcdef)),
        '3fc46d7b70b5c23fef86d979503e03a723929f31e52d2c49e84349e07cfe7d46',
      );
    });

    test('nejmenší řešení pro 16 bitů', () {
      expect(PowSearcher(prefix).search(16, 0, 1 << 20), 145733);
    });
  });

  test('ruční SHA-256 se shoduje s package:cryptography', () async {
    final s = PowSearcher(prefix);
    final sha = Sha256();
    for (final c in [0, 1, 255, 65536, 0xffffffff, 0x100000000, 99999999999]) {
      final ref = await sha.hash([...prefix, ..._counterBe(c)]);
      expect(_hex(s.digest(c)), _hex(ref.bytes), reason: 'čítač $c');
    }
  });

  test('počet nulových bitů odpovídá digestu', () {
    final s = PowSearcher(prefix);
    final c = s.search(12, 0, 1 << 20)!;
    final d = s.digest(c);
    expect(d[0], 0);
    expect(d[1] >> 4, 0);
    expect(s.zeroBits(c), greaterThanOrEqualTo(12));
  });

  test('prefix, který se nevejde do posledního bloku, se odmítne', () {
    expect(() => PowSearcher(Uint8List(60)), throwsArgumentError);
  });

  group('solveRegisterPow', () {
    RegisterPowChallenge challenge(int bits, {int expiresIn = 120}) =>
        RegisterPowChallenge.fromJson({
          'challenge':
              'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygp',
          'bits': bits,
          'expires_in': expiresIn,
        });

    test('výzva z JSON: base64url bez paddingu a relativní platnost', () {
      final now = DateTime.utc(2026, 10, 23, 12);
      final ch = RegisterPowChallenge.fromJson({
        'challenge': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygp',
        'bits': 18,
        'expires_in': 120,
        'expires_at': 1, // absolutní čas se ignoruje (hodiny telefonu)
      }, receivedAt: now);
      expect(ch.token, token);
      expect(ch.bits, 18);
      expect(ch.expiresAt, now.add(const Duration(seconds: 115)));
      expect(
        powHeader(ch, 7),
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygp.7',
      );
    });

    test('v isolate najde stejné řešení jako synchronní hledání', () async {
      final progress = <double>[];
      final counter = await solveRegisterPow(
        challenge(16),
        identityKey,
        onProgress: progress.add,
      );
      expect(counter, 145733);
      expect(progress.last, 1);
      // 145733 > powChunk → aspoň jeden průběžný odhad pod 1
      expect(progress.first, inExclusiveRange(0, 1));
    });

    test('prošlá výzva skončí PowExpiredError', () async {
      final ch = challenge(30, expiresIn: 6);
      var calls = 0;
      // první kontrola ještě v platnosti, druhá po ní
      DateTime clock() =>
          ch.expiresAt.add(Duration(seconds: calls++ == 0 ? -1 : 1));
      await expectLater(
        solveRegisterPow(ch, identityKey, now: clock),
        throwsA(isA<PowExpiredError>()),
      );
    });
  });
}
