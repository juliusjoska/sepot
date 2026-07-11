import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/push/push_service.dart';
import 'package:sepot/providers/messaging_provider.dart';

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
