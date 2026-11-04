/// Proof-of-work při registraci na relayi (`GET /v1/register/challenge`).
///
/// Proč: registrace stojí relay zápis do DB a limit per IP nejde utáhnout
/// (za CGNAT mobilního operátora sdílí jednu IPv4 stovky lidí). Výpočet
/// v telefonu zdraží hromadné zakládání účtů z mnoha adres a relay za něj
/// dává volnější limit per IP.
///
/// Úloha: najít `counter`, pro který má
/// `SHA-256("sepot-register-pow-v1" ‖ výzva ‖ identity_key ‖ counter_be64)`
/// aspoň `bits` úvodních nulových bitů. Výzva je bezstavový token relaye
/// (HMAC); vazba na identity_key brání tomu, aby se jedno řešení použilo
/// pro jiný účet. Stejné testovací vektory má relay (rust/sepot-relay/src/pow.rs).
///
/// SHA-256 je tu napsaná ručně kvůli rychlosti: prefix je pevný, takže se
/// jednou spočítá stav po plných blocích a pro každý pokus se komprimuje
/// jen poslední blok s čítačem, bez alokací. Obecná knihovna by pokaždé
/// hashovala celou zprávu (2 bloky). Správnost hlídají testy proti
/// `package:cryptography` a vektory relaye; rychlost `tool/pow_bench.dart`.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Doménové oddělení — hash nejde zaměnit s jiným použitím SHA-256.
final Uint8List powDomain = ascii.encode('sepot-register-pow-v1');

/// Výzva od relaye.
class RegisterPowChallenge {
  RegisterPowChallenge({
    required this.token,
    required this.bits,
    required this.expiresAt,
  });

  /// `{"challenge": "<base64url>", "bits": N, "expires_in": <s>, …}`.
  /// Platnost se počítá od přijetí podle `expires_in`, ne podle absolutního
  /// `expires_at` — hodiny telefonu bývají o minuty mimo. Rezerva 5 s kryje
  /// cestu odpovědi a odeslání registrace.
  factory RegisterPowChallenge.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) {
    final raw = json['challenge'] as String;
    final ttl = (json['expires_in'] as int) - 5;
    return RegisterPowChallenge(
      token: base64Url.decode(base64Url.normalize(raw)),
      bits: json['bits'] as int,
      expiresAt: (receivedAt ?? DateTime.now().toUtc()).add(
        Duration(seconds: ttl < 1 ? 1 : ttl),
      ),
    );
  }

  final Uint8List token;
  final int bits;
  final DateTime expiresAt;

  /// Podoba tokenu v hlavičce `X-Sepot-Pow` (base64url bez paddingu).
  String get tokenB64 => base64Url.encode(token).replaceAll('=', '');
}

/// Hodnota hlavičky `X-Sepot-Pow: <výzva>.<counter>`.
String powHeader(RegisterPowChallenge challenge, int counter) =>
    '${challenge.tokenB64}.$counter';

/// Výpočet nestihl platnost výzvy (pomalé zařízení / app na pozadí).
class PowExpiredError implements Exception {
  const PowExpiredError();
}

const _mask = 0xffffffff;

final _k = Uint32List.fromList(const <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
]);

const _iv = <int>[
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
];

int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & _mask;

/// Jedna komprese SHA-256: `state` (8 slov) se přepíše výsledkem.
/// `w` má 64 slov, prvních 16 je blok zprávy, zbytek je pracovní místo.
void _compress(Uint32List state, Uint32List w) {
  for (var t = 16; t < 64; t++) {
    final w15 = w[t - 15];
    final w2 = w[t - 2];
    final s0 = _rotr(w15, 7) ^ _rotr(w15, 18) ^ (w15 >>> 3);
    final s1 = _rotr(w2, 17) ^ _rotr(w2, 19) ^ (w2 >>> 10);
    w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _mask;
  }
  var a = state[0], b = state[1], c = state[2], d = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  for (var t = 0; t < 64; t++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ (~e & g);
    final t1 = (h + s1 + ch + _k[t] + w[t]) & _mask;
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (s0 + maj) & _mask;
    h = g;
    g = f;
    f = e;
    e = (d + t1) & _mask;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & _mask;
  }
  state[0] = (state[0] + a) & _mask;
  state[1] = (state[1] + b) & _mask;
  state[2] = (state[2] + c) & _mask;
  state[3] = (state[3] + d) & _mask;
  state[4] = (state[4] + e) & _mask;
  state[5] = (state[5] + f) & _mask;
  state[6] = (state[6] + g) & _mask;
  state[7] = (state[7] + h) & _mask;
}

/// Přesný počet úvodních nul 32bitového slova (bez floatů).
int _clz32(int x) {
  if (x == 0) return 32;
  var n = 0;
  if (x & 0xffff0000 == 0) {
    n += 16;
    x <<= 16;
  }
  if (x & 0xff000000 == 0) {
    n += 8;
    x <<= 8;
  }
  if (x & 0xf0000000 == 0) {
    n += 4;
    x <<= 4;
  }
  if (x & 0xc0000000 == 0) {
    n += 2;
    x <<= 2;
  }
  if (x & 0x80000000 == 0) n += 1;
  return n;
}

/// Prefix zprávy: doména ‖ výzva ‖ identity_key.
Uint8List powPrefix(Uint8List token, Uint8List identityKey) =>
    Uint8List.fromList([...powDomain, ...token, ...identityKey]);

/// Hledač nad pevným prefixem. Drží stav po plných blocích prefixu a šablonu
/// posledního bloku (zbytek prefixu ‖ čítač ‖ padding).
class PowSearcher {
  PowSearcher(Uint8List prefix) : _tailLen = prefix.length % 64 {
    // Čítač (8 B) + 0x80 + délka (8 B) se musí vejít do posledního bloku.
    if (_tailLen + 8 + 1 + 8 > 64) {
      throw ArgumentError(
        'prefix ${prefix.length} B se nevejde do jednoho bloku',
      );
    }
    final w = Uint32List(64);
    final fullBlocks = prefix.length ~/ 64;
    for (var blk = 0; blk < fullBlocks; blk++) {
      final view = ByteData.sublistView(prefix, blk * 64, blk * 64 + 64);
      for (var i = 0; i < 16; i++) {
        w[i] = view.getUint32(i * 4);
      }
      _compress(_midstate, w);
    }
    final totalBits = (prefix.length + 8) * 8;
    _template.setRange(0, _tailLen, prefix, fullBlocks * 64);
    _template[_tailLen + 8] = 0x80;
    final tv = ByteData.sublistView(_template);
    tv.setUint32(56, totalBits ~/ 0x100000000);
    tv.setUint32(60, totalBits & _mask);
    for (var i = 0; i < 16; i++) {
      _templateWords[i] = tv.getUint32(i * 4);
    }
    _firstCounterWord = _tailLen >> 2;
    _lastCounterWord = (_tailLen + 7) >> 2;
  }

  final int _tailLen;
  final _midstate = Uint32List.fromList(_iv);
  final _template = Uint8List(64);
  final _templateWords = Uint32List(16);
  late final int _firstCounterWord;
  late final int _lastCounterWord;

  final _w = Uint32List(64);
  final _state = Uint32List(8);

  /// Digest (32 B) pro daný čítač — pro testy a ověření.
  Uint8List digest(int counter) {
    _run(counter);
    final out = ByteData(32);
    for (var i = 0; i < 8; i++) {
      out.setUint32(i * 4, _state[i]);
    }
    return out.buffer.asUint8List();
  }

  /// Počet úvodních nulových bitů hashe pro daný čítač.
  int zeroBits(int counter) {
    _run(counter);
    var bits = 0;
    for (final word in _state) {
      final z = _clz32(word);
      bits += z;
      if (z < 32) break;
    }
    return bits;
  }

  void _run(int counter) {
    final tv = ByteData.sublistView(_template);
    tv.setUint32(_tailLen, counter ~/ 0x100000000);
    tv.setUint32(_tailLen + 4, counter & _mask);
    _w.setRange(0, 16, _templateWords);
    for (var i = _firstCounterWord; i <= _lastCounterWord && i < 16; i++) {
      _w[i] = tv.getUint32(i * 4);
    }
    _state.setAll(0, _midstate);
    _compress(_state, _w);
  }

  /// Nejmenší čítač v `[start, start + count)` s aspoň `bits` nulami, jinak null.
  int? search(int bits, int start, int count) {
    final end = start + count;
    for (var c = start; c < end; c++) {
      if (zeroBits(c) >= bits) return c;
    }
    return null;
  }
}

/// Kolik pokusů proběhne v jednom isolate — 0,1–0,4 s (0,3–1,2 M pokusů/s), aby šel
/// hlásit postup a hlídat platnost výzvy, a režie spuštění isolate (~ms)
/// zůstala pod 2 %.
const powChunk = 1 << 17;

/// Najde řešení výzvy mimo UI vlákno. `onProgress` dostává odhad 0..1
/// (pravděpodobnost, že by se řešení už našlo — počet pokusů je náhodný,
/// průměr 2^bits). Po vypršení výzvy hodí [PowExpiredError].
Future<int> solveRegisterPow(
  RegisterPowChallenge challenge,
  Uint8List identityKey, {
  void Function(double progress)? onProgress,
  DateTime Function() now = _utcNow,
}) async {
  final prefix = powPrefix(challenge.token, identityKey);
  final bits = challenge.bits;
  final expected = math.pow(2, bits).toDouble();
  var start = 0;
  while (true) {
    if (!now().isBefore(challenge.expiresAt)) throw const PowExpiredError();
    final from = start;
    final found = await Isolate.run(
      () => PowSearcher(prefix).search(bits, from, powChunk),
    );
    if (found != null) {
      onProgress?.call(1);
      return found;
    }
    start += powChunk;
    onProgress?.call(1 - math.exp(-start / expected));
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
