import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/push/push_service.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Push vrstva nad messagingem.
final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.read(messagingServiceProvider));
});

/// Zaregistruje push callbacky, jakmile messaging běží. Push se sám
/// NEzapíná — jen připraví handlery. Pokud už uživatel dřív distributora
/// zvolil, obnoví registraci (endpoint se mohl změnit; relay se re-registruje
/// po AUTH). Watchovat z chat listu vedle messagingStartProvider.
final pushInitProvider = FutureProvider<void>((ref) async {
  await ref.watch(messagingStartProvider.future);
  final push = ref.read(pushServiceProvider);
  // Obnoví uložený režim (off/UnifiedPush/FCM) — endpoint/token se
  // re-registruje u relaye po každém startu.
  await push.restoreMode();
});

/// Stav budíčků pro chat list. Bez funkčního pushe appka na pozadí spí a
/// zprávy dorazí, až ji uživatel otevře — o tom má vědět dřív, než mu
/// někdo vyčte, že neodpovídá.
enum PushHealth {
  /// Budíčky nastavené a bez chyby.
  ok,

  /// Push vůbec nezapnutý (výchozí stav po instalaci).
  off,

  /// Distributor registraci odmítl — zapnuto, ale nefunguje.
  failed,
}

final pushHealthProvider = FutureProvider<PushHealth>((ref) async {
  await ref.watch(pushInitProvider.future);
  final push = ref.read(pushServiceProvider);
  if (await push.registrationFailed()) return PushHealth.failed;
  return await push.currentMode() == 'off' ? PushHealth.off : PushHealth.ok;
});

/// Skryl si uživatel upozornění na chat listu? Rozhodnutí se respektuje —
/// připomínat donekonečna by bylo otravné.
final pushHintDismissedProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(storageProvider);
  return await storage.getSetting<bool>('push_hint_dismissed') ?? false;
});
