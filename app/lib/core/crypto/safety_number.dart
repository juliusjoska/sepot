/// Safety number — vizuální ověření kontaktu.
///
/// Používá libsignal `Fingerprint` (NumericFingerprintGenerator), žádný
/// vlastní výpočet: iterovaný SHA-512 (5200 iterací jako Signal) nad
/// (verze ‖ identifikátor ‖ identity klíč) pro obě strany, zobrazení
/// 60 dekadických číslic (12 bloků po 5). Menší polovina jde první,
/// takže OBĚ strany vidí stejné číslo.
///
/// Stabilní identifikátor strany = BLAKE2b-256 fingerprint jejího
/// identity klíče (deterministický z klíče — žádný telefon, e-mail ani
/// server handle, přesně v duchu „identita = klíč").
///
/// QR ověření: [scannable] bajty do QR; sken protistrany se porovná přes
/// [SafetyNumber.compare] (libsignal kontroluje křížem local↔remote).
library;

import 'dart:typed_data';

import 'package:libsignal/libsignal.dart' as signal;
import 'package:sepot/models/identity.dart';

class SafetyNumber {
  SafetyNumber._(this.display, this.scannable);

  /// Iterace hashe jako Signal (bezpečnostní parametr — NEměnit,
  /// změna = všem se změní safety numbers).
  static const int iterations = 5200;

  /// Verze scannable formátu (libsignal proto).
  static const int version = 2;

  /// 60 číslic bez mezer.
  final String display;

  /// Binární encoding pro QR + [compare].
  final Uint8List scannable;

  /// Spočítá safety number páru identity klíčů (33 B serializované).
  factory SafetyNumber.compute({
    required Uint8List localIdentityKey,
    required Uint8List remoteIdentityKey,
  }) {
    final fp = signal.Fingerprint(
      iterations: iterations,
      version: version,
      localIdentifier: SepotFingerprint.ofPublicKey(localIdentityKey).bytes,
      localPublicKey: localIdentityKey,
      remoteIdentifier: SepotFingerprint.ofPublicKey(remoteIdentityKey).bytes,
      remotePublicKey: remoteIdentityKey,
    );
    return SafetyNumber._(fp.displayString(), fp.scannableEncoding());
  }

  /// 12 bloků po 5 číslicích pro zobrazení.
  List<String> get groups => [
        for (var i = 0; i < display.length; i += 5)
          display.substring(i, i + 5),
      ];

  /// Porovná můj scannable s naskenovaným od protistrany. True = klíče
  /// si křížem odpovídají (žádný MITM), false = NESHODA.
  static bool compare(Uint8List mine, Uint8List scanned) {
    try {
      return signal.fingerprintCompare(fingerprint1: mine, fingerprint2: scanned);
    } on Object {
      // vadný/cizí QR formát = neshoda, ne pád
      return false;
    }
  }
}
