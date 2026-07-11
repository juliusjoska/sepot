import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Ruční volba jazyka aplikace. `null` = řídit se systémem.
///
/// Hodnota žije v OS keystore (NE v SQLCipher DB) — PIN lock a onboarding
/// se zobrazují před odemčením úložiště a musí už být ve zvoleném jazyce.
/// Jazyk není citlivý údaj; keystore je tu jen kvůli dostupnosti před
/// unlockem (stejný vzor jako režim pushů v PushBootstrap).
class LocaleNotifier extends AsyncNotifier<Locale?> {
  static const _key = 'app_locale';

  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<Locale?> build() => readStored();

  /// Přečte uloženou volbu i bez Riverpodu — pro headless start (push
  /// budíček skládá notifikaci před postavením widget tree).
  static Future<Locale?> readStored() async {
    try {
      final code = await _store.read(key: _key);
      return (code == null || code.isEmpty) ? null : Locale(code);
    } catch (_) {
      // Keystore nedostupný (např. těsně po restartu) → systémový jazyk.
      return null;
    }
  }

  /// Nastaví jazyk aplikace; `null` vrátí řízení systému.
  Future<void> set(Locale? locale) async {
    if (locale == null) {
      await _store.delete(key: _key);
    } else {
      await _store.write(key: _key, value: locale.languageCode);
    }
    state = AsyncData(locale);
  }
}

final localeProvider =
    AsyncNotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);
