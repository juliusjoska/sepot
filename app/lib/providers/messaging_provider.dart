import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Nastartuje službu, jakmile existuje identita. Watchovat z první
/// obrazovky po odemčení (chat list) — do té doby se nic nespojuje.
/// Předpokládá odemčený storage — na /chats se jde vždy až po unlocku.
final messagingStartProvider = FutureProvider<void>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  if (identity == null) return;

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
  // Ztlumená konverzace notifikaci potlačí (unread badge běží dál).
  service.onMessageReceived = (contact, message) async {
    final visible = WidgetsBinding.instance.lifecycleState ==
        AppLifecycleState.resumed;
    if (visible) return;
    final conv = await ref.read(storageProvider).loadConversation(contact.id);
    if (conv?.isMuted == true) return;
    PushNotifier.showMessageNotification(contact.displayName);
  };

  await service.start(identity);
});

/// Stav připojení k relayi pro UI indikátor.
final relayConnectionProvider = StreamProvider<RelayConnectionState>((ref) {
  ref.watch(messagingStartProvider);
  final service = ref.read(messagingServiceProvider);
  return service.connectionStream ?? const Stream.empty();
});
