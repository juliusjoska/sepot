import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/calls/call_controller.dart';
import 'package:sepot/core/network/relay_client.dart';
import 'package:sepot/core/push/push_notifier.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Jediná instance messaging služby (krypto + relay + storage).
final messagingServiceProvider = Provider<MessagingService>((ref) {
  final service = MessagingService(storage: ref.read(storageProvider));
  ref.onDispose(service.stop);
  return service;
});

/// Kdo právě píše: konverzace → otisky pisatelů. Prázdné, když je
/// „píše…“ vypnuté (služba pak nic nepřijímá).
final typingProvider = StreamProvider<Map<String, Set<String>>>((ref) async* {
  final tracker = ref.watch(messagingServiceProvider).typing;
  yield tracker.current;
  yield* tracker.changes;
});

/// Profilová fotka člověka podle otisku (null = iniciály). Přepočítá se,
/// když se změní kontakty — tam dorazí nový odkaz i stažení fotky.
final avatarProvider =
    FutureProvider.family<Uint8List?, String>((ref, fingerprint) async {
  final service = ref.watch(messagingServiceProvider);
  final me = ref.watch(identityProvider).valueOrNull;
  final contacts = ref.watch(contactsProvider).valueOrNull ?? const [];
  if (!service.isStarted) return null;
  final avatar = fingerprint == me?.id
      ? service.myAvatar
      : contacts.where((c) => c.id == fingerprint).firstOrNull?.avatar;
  return avatar == null ? null : service.loadAvatar(avatar);
});

/// Nastartuje službu, jakmile existuje identita. Watchovat z první
/// obrazovky po odemčení (chat list) — do té doby se nic nespojuje.
/// Předpokládá odemčený storage — na /chats se jde vždy až po unlocku.
final messagingStartProvider = FutureProvider<void>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  if (identity == null) return;

  // Po auto-locku se tenhle provider eager-rebuildne (drží ho pushInitProvider)
  // ještě NAD zamčeným storage → service.start() by spadl na „Storage is
  // locked" a provider by uvázl v AsyncError (žádný příjem/odeslání až do
  // killu procesu). Nad zamčeným storage tiše nic nestartuj; po odemčení
  // se provider invaliduje (viz unlock cesty) a spustí start znovu.
  final storage = ref.read(storageProvider);
  if (!storage.isUnlocked) return;
  // Nátlaková relace: žádná síť. Messaging by se registroval skutečným
  // identity klíčem (409 každých 30 s = důkaz pro pozorovatele sítě).
  if (storage.isDecoyMode) return;

  final service = ref.read(messagingServiceProvider);
  if (service.isStarted) return;

  service.onUpdate = () {
    ref.invalidate(conversationsProvider);
    // celá family — jinak se otevřená konverzace nedozví o nové zprávě
    // ani o změně stavu přílohy
    ref.invalidate(conversationProvider);
    ref.invalidate(contactsProvider);
    // příchozí ginv/gleave/gmeta mění skupiny
    ref.invalidate(groupsProvider);
  };

  // Appka běží, ale není v popředí (jiná appka / zhasnutý displej se
  // živým procesem) → systémová notifikace. Jen jméno, žádný obsah.
  // Ztlumená konverzace notifikaci potlačí (unread badge běží dál),
  // zmínka mě ve skupině projde i tak.
  service.onMessageReceived = (contact, message, convId) async {
    final visible = WidgetsBinding.instance.lifecycleState ==
        AppLifecycleState.resumed;
    if (visible) return;
    final conv = await ref.read(storageProvider).loadConversation(convId);
    final mentionedMe = message.mentions.contains(identity.id);
    if (conv?.isMuted == true && !mentionedMe) return;
    PushNotifier.showMessageNotification(contact.displayName);
  };

  service.onCallSignal = (contact, signal) =>
      ref.read(callProvider.notifier).onSignal(contact, signal);

  await service.start(identity);
});

/// Stav připojení k relayi pro UI indikátor.
final relayConnectionProvider = StreamProvider<RelayConnectionState>((ref) {
  ref.watch(messagingStartProvider);
  final service = ref.read(messagingServiceProvider);
  return service.connectionStream ?? const Stream.empty();
});
