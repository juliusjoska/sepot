// ignore_for_file: avoid_print — výstup měření je celý smysl nástroje
//
// Měření řešiče PoW registrace na cílovém stroji:
//   dart compile exe tool/pow_bench.dart -o pow_bench
//   ./pow_bench               rychlost hashování (pokusy/s) a odhad časů
//   ./pow_bench e2e 20 30     30 náhodných výzev s 20 bity přes solveRegisterPow
//                             (isolate po dávkách, jak to dělá appka): průměr, p50, p95, max
import 'dart:math';
import 'dart:typed_data';

import 'package:sepot/core/network/register_pow.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'e2e') {
    await _e2e(int.parse(args[1]), int.parse(args[2]));
    return;
  }
  final attempts = args.isEmpty ? 1 << 21 : int.parse(args.first);
  final searcher = PowSearcher(powPrefix(Uint8List(42), Uint8List(33)));
  searcher.search(64, 0, 1 << 16); // zahřátí
  final sw = Stopwatch()..start();
  searcher.search(64, 0, attempts);
  final perSec = attempts / (sw.elapsedMicroseconds / 1e6);
  print('pokusy/s: ${perSec.toStringAsFixed(0)}');
  for (final bits in [16, 17, 18, 19, 20, 21, 22]) {
    final mean = (1 << bits) / perSec;
    // počet pokusů je geometrický: p95 ≈ 3× průměr
    print(
      'bits $bits: průměr ${mean.toStringAsFixed(2)} s, '
      'p95 ${(mean * 3).toStringAsFixed(2)} s',
    );
  }
}

Future<void> _e2e(int bits, int runs) async {
  final rng = Random.secure();
  Uint8List random(int n) =>
      Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  final times = <double>[];
  for (var i = 0; i < runs; i++) {
    final challenge = RegisterPowChallenge(
      token: random(42),
      bits: bits,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final sw = Stopwatch()..start();
    await solveRegisterPow(challenge, random(33));
    times.add(sw.elapsedMilliseconds / 1000);
  }
  times.sort();
  double at(double q) => times[((times.length - 1) * q).round()];
  final mean = times.reduce((a, b) => a + b) / times.length;
  print(
    'bits $bits, $runs výzev: průměr ${mean.toStringAsFixed(2)} s, '
    'p50 ${at(0.5).toStringAsFixed(2)} s, p95 ${at(0.95).toStringAsFixed(2)} s, '
    'max ${times.last.toStringAsFixed(2)} s',
  );
}
