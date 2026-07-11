import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/providers/identity_provider.dart';

/// Stav konverzací
class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final storage = ref.read(storageProvider);
    return storage.loadConversations();
  }

  /// Odešli zprávu — E2E šifrovaně přes relay. `replyToId` = odpověď.
  /// `contactId` může být i gid skupiny (fanout členům).
  Future<void> sendMessage(String contactId, String text,
      {String? replyToId}) async {
    final storage = ref.read(storageProvider);
    final service = ref.read(messagingServiceProvider);

    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.sendGroupText(group, text, replyToId: replyToId);
    } else {
      final contact = await _contact(contactId);
      // sendText zprávu po odeslání sám uloží (s reálným delivery stavem)
      await service.sendText(contact, text, replyToId: replyToId);
    }

    final conversations = await storage.loadConversations();
    state = AsyncData(conversations);
  }

  Future<Contact> _contact(String contactId) async {
    final contacts = await ref.read(storageProvider).loadContacts();
    final contact = contacts.where((c) => c.id == contactId).firstOrNull;
    if (contact == null) throw StateError('Contact not found');
    return contact;
  }

  /// Skupina, pokud id konverzace patří skupině (a neopustil jsem ji).
  Future<Group?> _groupOrNull(String id) async {
    final group = await ref.read(storageProvider).loadGroup(id);
    if (group == null || group.left) return null;
    return group;
  }

  /// Reakce emotikonem na zprávu (null = odebrat moji reakci).
  Future<void> reactToMessage(
      String contactId, String messageId, String? emoji) async {
    final service = ref.read(messagingServiceProvider);
    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.sendGroupReaction(group, messageId, emoji);
    } else {
      await service.sendReaction(await _contact(contactId), messageId, emoji);
    }
    state = AsyncData(await ref.read(storageProvider).loadConversations());
  }

  /// Úprava textu odeslané zprávy.
  Future<void> editMessage(
      String contactId, String messageId, String newText) async {
    final service = ref.read(messagingServiceProvider);
    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.editGroupMessage(group, messageId, newText);
    } else {
      await service.editMessage(await _contact(contactId), messageId, newText);
    }
    state = AsyncData(await ref.read(storageProvider).loadConversations());
  }

  /// Smazání zprávy pro všechny.
  Future<void> deleteMessage(String contactId, String messageId) async {
    final service = ref.read(messagingServiceProvider);
    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.deleteGroupMessage(group, messageId);
    } else {
      await service.deleteMessage(await _contact(contactId), messageId);
    }
    state = AsyncData(await ref.read(storageProvider).loadConversations());
  }

  /// Ztlumit / odtlumit konverzaci (lokální). `duration == null` = navždy.
  Future<void> setMuted(String contactId, bool muted, {Duration? duration}) async {
    final storage = ref.read(storageProvider);
    final conv = await storage.loadConversation(contactId);
    if (conv == null) return;
    conv.muted = muted;
    conv.mutedUntil = (muted && duration != null)
        ? DateTime.now().add(duration)
        : null;
    await storage.saveConversation(conv);
    state = AsyncData(await storage.loadConversations());
  }

  /// Archivovat / odarchivovat konverzaci (lokální).
  Future<void> setArchived(String contactId, bool archived) async {
    final storage = ref.read(storageProvider);
    final conv = await storage.loadConversation(contactId);
    if (conv == null) return;
    conv.archived = archived;
    await storage.saveConversation(conv);
    state = AsyncData(await storage.loadConversations());
  }

  /// Smazání zprávy jen u mě (lokálně) — protistraně se nic neposílá.
  Future<void> deleteLocalMessage(String contactId, String messageId) async {
    final storage = ref.read(storageProvider);
    final conv = await storage.loadConversation(contactId);
    if (conv == null) return;
    conv.messages.removeWhere((m) => m.id == messageId);
    await storage.saveConversation(conv);
    state = AsyncData(await storage.loadConversations());
  }

  /// Odešli přílohu (fotku/dokument) — zpracování, šifrování a upload
  /// řeší MessagingService.sendAttachment.
  Future<void> sendAttachment(
    String contactId, {
    required Uint8List bytes,
    required String fileName,
    String? mime,
  }) async {
    final storage = ref.read(storageProvider);
    final service = ref.read(messagingServiceProvider);

    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.sendGroupAttachment(
        group,
        bytes: bytes,
        fileName: fileName,
        mime: mime,
      );
    } else {
      final contact = await _contact(contactId);
      await service.sendAttachment(
        contact,
        bytes: bytes,
        fileName: fileName,
        mime: mime,
      );
    }

    final conversations = await storage.loadConversations();
    state = AsyncData(conversations);
  }

  /// Odešli hlasovou zprávu (audio příloha s délkou nahrávky).
  Future<void> sendVoiceMessage(
    String contactId, {
    required Uint8List bytes,
    required int durationMs,
    String mime = 'audio/mp4',
  }) async {
    final storage = ref.read(storageProvider);
    final service = ref.read(messagingServiceProvider);
    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.sendGroupAttachment(
        group,
        bytes: bytes,
        fileName: 'voice-message.m4a',
        mime: mime,
        durationMs: durationMs,
      );
    } else {
      await service.sendAttachment(
        await _contact(contactId),
        bytes: bytes,
        fileName: 'voice-message.m4a',
        mime: mime,
        durationMs: durationMs,
      );
    }
    state = AsyncData(await storage.loadConversations());
  }

  /// Ruční opakování downloadu blobu (stav failed).
  Future<void> retryAttachmentDownload(
      String contactId, Message message) async {
    final service = ref.read(messagingServiceProvider);
    await service.downloadAttachment(contactId, message);
    final conversations = await ref.read(storageProvider).loadConversations();
    state = AsyncData(conversations);
  }

  /// Označ konverzaci jako přečtenou
  Future<void> markAsRead(String contactId) async {
    final storage = ref.read(storageProvider);
    final identity = ref.read(identityProvider).valueOrNull;
    if (identity == null) return;

    final conv = await storage.loadConversation(contactId);
    if (conv == null) return;

    // Příchozí zprávy, které jsem právě přečetl → pošlu za ně potvrzení
    // přečtení (sendReadReceipts sám zkontroluje, jestli je funkce zapnutá).
    final justRead = conv.messages
        .where((m) => !m.isMine(identity.id) && !m.isRead)
        .map((m) => m.id)
        .toList();

    conv.markAllRead(identity.id);
    await storage.saveConversation(conv);
    state = AsyncData(await storage.loadConversations());

    // Potvrzení přečtení ve skupině v1 neposíláme (fanout N receipts
    // za každé otevření chatu; per-member matice až v2).
    if (justRead.isNotEmpty && await _groupOrNull(contactId) == null) {
      final contacts = await storage.loadContacts();
      final contact = contacts.where((c) => c.id == contactId).firstOrNull;
      if (contact != null) {
        await ref
            .read(messagingServiceProvider)
            .sendReadReceipts(contact, justRead);
      }
    }
  }

  /// Celkový počet nepřečtených zpráv
  int get totalUnread {
    final conversations = state.valueOrNull ?? [];
    final identity = ref.read(identityProvider).valueOrNull;
    if (identity == null) return 0;

    return conversations.fold(
      0,
      (sum, conv) => sum + conv.unreadCount(identity.id),
    );
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);

/// Provider pro jednu konverzaci
final conversationProvider =
    FutureProvider.family<Conversation?, String>((ref, contactId) async {
  final storage = ref.read(storageProvider);
  return storage.loadConversation(contactId);
});
