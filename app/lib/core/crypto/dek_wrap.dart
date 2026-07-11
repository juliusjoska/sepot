/// Argon2id wrap databázového klíče (DEK) za PIN.
///
/// Schéma:
///   unlockKey  = Argon2id(PIN, salt)
///   wrappedDek = AES-256-GCM(dek, unlockKey)
///
/// PIN se NIKDE neukládá ani nehashuje na porovnání — „ověření PINu" je
/// úspěšné rozbalení DEK (GCM auth tag). Špatný PIN = nečitelná DB.
///
/// Argon2id parametry jsou součástí blobu, takže budoucí rekalibrace
/// nerozbije stará data. Při wrap i unwrap se vynucuje dolní mez
/// (OWASP floor): m ≥ 19 MiB, t ≥ 2 — slabší
/// parametry se odmítnou (žádný tichý downgrade).
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// GCM auth tag nesedí — špatný PIN, nebo poškozený/podvržený blob.
/// (AES-GCM tyhle dva případy principiálně nerozliší.)
class WrongPinException implements Exception {
  const WrongPinException();

  @override
  String toString() => 'WrongPinException: wrong PIN or corrupted blob';
}

class DekWrap {
  DekWrap._();

  /// Výchozí parametry (m=64MiB, t=3, p=1).
  /// Řádově ~2–3 s čistým Dartem na středně výkonném zařízení.
  static const int defaultMemoryKiB = 64 * 1024;
  static const int defaultIterations = 3;
  static const int defaultParallelism = 1;

  /// Dolní bezpečnostní mez (OWASP) — pod ni kalibrace NIKDY nesmí.
  static const int floorMemoryKiB = 19 * 1024;
  static const int floorIterations = 2;

  static const String _version = 'sepot-dek-v1';

  /// Zabal 32B DEK za PIN. Výstup je samopopisný string pro keystore:
  /// `sepot-dek-v1:<mKiB>:<t>:<p>:<b64 salt>:<b64 nonce>:<b64 ct>:<b64 tag>`
  static Future<String> wrap({
    required Uint8List dek,
    required String pin,
    int memoryKiB = defaultMemoryKiB,
    int iterations = defaultIterations,
    int parallelism = defaultParallelism,
  }) async {
    if (dek.length != 32) {
      throw ArgumentError.value(dek.length, 'dek', 'DEK must be 32 bytes');
    }
    _enforceFloor(memoryKiB, iterations);

    final salt = _randomBytes(16);
    final unlockKey = await _deriveUnlockKey(
      pin: pin,
      salt: salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );

    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      dek,
      secretKey: SecretKey(unlockKey),
      nonce: _randomBytes(12),
    );

    return [
      _version,
      '$memoryKiB',
      '$iterations',
      '$parallelism',
      base64Encode(salt),
      base64Encode(box.nonce),
      base64Encode(box.cipherText),
      base64Encode(box.mac.bytes),
    ].join(':');
  }

  /// Rozbal DEK. Na špatném PINu (nebo poškozeném blobu) vyhodí
  /// [WrongPinException]; na neplatném formátu [FormatException].
  static Future<Uint8List> unwrap({
    required String wrapped,
    required String pin,
  }) async {
    final parts = wrapped.split(':');
    if (parts.length != 8 || parts[0] != _version) {
      throw FormatException('Unknown wrapped DEK format', wrapped);
    }
    final memoryKiB = int.parse(parts[1]);
    final iterations = int.parse(parts[2]);
    final parallelism = int.parse(parts[3]);
    // Floor PŘED odvozením — podvržený blob se slabými parametry
    // nesmí projít, ani kdyby měl platný tag
    _enforceFloor(memoryKiB, iterations);

    final salt = base64Decode(parts[4]);
    final nonce = base64Decode(parts[5]);
    final cipherText = base64Decode(parts[6]);
    final mac = base64Decode(parts[7]);

    final unlockKey = await _deriveUnlockKey(
      pin: pin,
      salt: salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );

    final aes = AesGcm.with256bits();
    try {
      final dek = await aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(unlockKey),
      );
      return Uint8List.fromList(dek);
    } on SecretBoxAuthenticationError {
      throw const WrongPinException();
    }
  }

  static void _enforceFloor(int memoryKiB, int iterations) {
    if (memoryKiB < floorMemoryKiB || iterations < floorIterations) {
      throw StateError(
        'Argon2id parameters below security floor '
        '(m=${memoryKiB}KiB t=$iterations, floor m=${floorMemoryKiB}KiB '
        't=$floorIterations)',
      );
    }
  }

  /// Argon2id běží v samostatném isolate — 64 MiB memory-hard výpočet
  /// by jinak na sekundy zmrazil UI.
  static Future<Uint8List> _deriveUnlockKey({
    required String pin,
    required Uint8List salt,
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) {
    return Isolate.run(() async {
      final algo = DartArgon2id(
        memory: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: 32,
      );
      final key = await algo.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );
      return Uint8List.fromList(await key.extractBytes());
    });
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
