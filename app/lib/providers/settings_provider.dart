import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:sepot/core/backup/backup_service.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Služba šifrovaných záloh historie.
final backupServiceProvider = Provider<BackupService>(
    (ref) => BackupService(ref.read(storageProvider)));

/// Je nastavený nátlakový (decoy) PIN?
final hasDecoyPinProvider = FutureProvider<bool>(
    (ref) => ref.read(storageProvider).hasDecoyPin());

/// Potvrzení přečtení (read receipts). Default VYPNUTO — soukromí.
/// Je reciproční: když je vypnuté, appka je neposílá ani nezobrazuje.
class ReadReceiptsNotifier extends AsyncNotifier<bool> {
  static const key = 'read_receipts_enabled';

  @override
  Future<bool> build() async {
    final storage = ref.read(storageProvider);
    return (await storage.getSetting<bool>(key)) ?? false;
  }

  Future<void> set(bool value) async {
    await ref.read(storageProvider).setSetting(key, value);
    state = AsyncData(value);
  }
}

final readReceiptsProvider =
    AsyncNotifierProvider<ReadReceiptsNotifier, bool>(ReadReceiptsNotifier.new);

/// „píše…“ — stejná pravidla jako potvrzení přečtení: výchozí vypnuto,
/// reciproční (kdo nesdílí, nevidí).
class TypingIndicatorsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final storage = ref.read(storageProvider);
    return (await storage.getSetting<bool>(
            MessagingService.typingSettingKey)) ??
        false;
  }

  Future<void> set(bool value) async {
    await ref
        .read(storageProvider)
        .setSetting(MessagingService.typingSettingKey, value);
    state = AsyncData(value);
  }
}

final typingIndicatorsProvider =
    AsyncNotifierProvider<TypingIndicatorsNotifier, bool>(
        TypingIndicatorsNotifier.new);

/// Zabezpečení obrazovky: blok screenshotů (Android FLAG_SECURE) + skrytí
/// obsahu v přepínači appek (iOS). Default VYPNUTO — blokuje i vlastní
/// screenshoty, tak ať se uživatel rozhodne sám.
class ScreenSecurityNotifier extends AsyncNotifier<bool> {
  static const key = 'screen_security_enabled';

  @override
  Future<bool> build() async {
    final v = (await ref.read(storageProvider).getSetting<bool>(key)) ?? false;
    await _apply(v);
    return v;
  }

  Future<void> set(bool value) async {
    await ref.read(storageProvider).setSetting(key, value);
    await _apply(value);
    state = AsyncData(value);
  }

  Future<void> _apply(bool on) async {
    try {
      if (on) {
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.protectDataLeakageOn();
      } else {
        await ScreenProtector.preventScreenshotOff();
        await ScreenProtector.protectDataLeakageOff();
      }
    } catch (_) {
      // Nepodporovaná platforma / kanál — bezpečně ignoruj.
    }
  }
}

final screenSecurityProvider =
    AsyncNotifierProvider<ScreenSecurityNotifier, bool>(
        ScreenSecurityNotifier.new);

/// Automatický zámek: po kolika sekundách na pozadí se appka zamkne.
/// `0` = nikdy. Do 0.3.0 dlaždice tvrdila „5 minut", ale nezamykalo se
/// vůbec (jen studený start) — což je horší než žádná funkce.
///
/// Hodnota žije v šifrované DB, takže se čte jen s odemčeným úložištěm.
class AutoLockNotifier extends AsyncNotifier<int> {
  static const key = 'auto_lock_seconds';
  static const vychozi = 300;

  /// Nabídka v UI (sekundy). Popisky skládá obrazovka z lokalizace
  /// (settingsAutoLockNever/1min/5min/15min) — provider texty nemá.
  static const moznostiSekundy = [0, 60, 300, 900];

  @override
  Future<int> build() async {
    final storage = ref.read(storageProvider);
    if (!storage.isUnlocked) return vychozi;
    return (await storage.getSetting<int>(key)) ?? vychozi;
  }

  Future<void> set(int seconds) async {
    await ref.read(storageProvider).setSetting(key, seconds);
    state = AsyncData(seconds);
  }
}

final autoLockProvider =
    AsyncNotifierProvider<AutoLockNotifier, int>(AutoLockNotifier.new);

/// Routování přes Tor (SOCKS5/Orbot na `.onion`). Default VYPNUTO —
/// přímé WSS je rychlejší a nevyžaduje Orbot. Zapnutí skryje IP klienta
/// před relayem. Hodnota žije v šifrované DB.
class TorNotifier extends AsyncNotifier<bool> {
  static const key = 'tor_enabled';

  @override
  Future<bool> build() async {
    final storage = ref.read(storageProvider);
    if (!storage.isUnlocked) return false;
    return (await storage.getSetting<bool>(key)) ?? false;
  }

  Future<void> set(bool value) async {
    // Uloží volbu a přestaví běžící spojení na .onion / zpět.
    await ref.read(messagingServiceProvider).setTorEnabled(value);
    state = AsyncData(value);
  }
}

final torProvider = AsyncNotifierProvider<TorNotifier, bool>(TorNotifier.new);
