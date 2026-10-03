import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/models/poll.dart';
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
      {String? replyToId, List<String> mentions = const []}) async {
    if (isNotes(contactId)) {
      return _addNote((me) => Message.text(
            senderId: me,
            recipientId: me,
            content: text,
            replyToId: replyToId,
            status: MessageStatus.sent,
          ));
    }
    final storage = ref.read(storageProvider);
    final service = ref.read(messagingServiceProvider);

    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.sendGroupText(group, text,
          replyToId: replyToId, mentions: mentions);
    } else {
      final contact = await _contact(contactId);
      // sendText zprávu po odeslání sám uloží (s reálným delivery stavem)
      await service.sendText(contact, text, replyToId: replyToId);
    }

    final conversations = await storage.loadConversations();
    state = AsyncData(conversations);
  }

  /// Pošle anketu. [fallback] je text, který uvidí starší verze appky
  /// (skládá ho UI, protože zná jazyk uživatele).
  Future<void> sendPoll(String convId, Poll poll, String fallback) async {
    final service = ref.read(messagingServiceProvider);
    final group = await _groupOrNull(convId);
    if (group != null) {
      await service.sendGroupText(group, fallback, poll: poll);
    } else {
      await service.sendText(await _contact(convId), fallback, poll: poll);
    }
    state = AsyncData(await ref.read(storageProvider).loadConversations());
  }

  /// Hlas v anketě (prázdná volba = zrušit).
  Future<void> votePoll(String convId, String pollId, List<int> choice) async {
    final service = ref.read(messagingServiceProvider);
    final group = await _groupOrNull(convId);
    await service.votePoll(
      convId,
      pollId,
      choice,
      group: group,
      contact: group == null ? await _contact(convId) : null,
    );
  }

  static bool isNotes(String id) => id == AppConstants.notesConversationId;

  /// Poznámka pro sebe: jen šifrované úložiště v telefonu, nic do sítě.
  Future<void> _addNote(Message Function(String myId) build) async {
    final identity = ref.read(identityProvider).valueOrNull;
    if (identity == null) return;
    final storage = ref.read(storageProvider);
    await storage.addMessage(
        AppConstants.notesConversationId, build(identity.id));
    state = AsyncData(await storage.loadConversations());
  }

  /// Otevře poznámky; prázdné je založí, aby byly vidět i v seznamu chatů.
  Future<void> ensureNotes() async {
    final storage = ref.read(storageProvider);
    await storage.ensureConversation(AppConstants.notesConversationId);
    state = AsyncData(await storage.loadConversations());
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
    if (isNotes(contactId)) {
      final storage = ref.read(storageProvider);
      final conv = await storage.loadConversation(contactId);
      final old = conv?.messages.where((m) => m.id == messageId).firstOrNull;
      if (conv == null || old == null) return;
      conv.updateMessage(
          old.copyWith(content: newText, editedAt: DateTime.now()));
      await storage.saveConversation(conv);
      state = AsyncData(await storage.loadConversations());
      return;
    }
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

  /// Připnout / odepnout konverzaci (lokální). Archivovaná se připnutím
  /// vrací mezi aktivní — připnutý chat v archivu by nikdo neviděl.
  Future<void> setPinned(String contactId, bool pinned) async {
    final storage = ref.read(storageProvider);
    final conv = await storage.loadConversation(contactId);
    if (conv == null) return;
    conv.pinned = pinned;
    if (pinned) conv.archived = false;
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
    String? caption,
  }) async {
    final storage = ref.read(storageProvider);
    final service = ref.read(messagingServiceProvider);

    if (isNotes(contactId)) {
      final meta = await service.prepareNoteAttachment(
          bytes: bytes, fileName: fileName, mime: mime);
      return _addNote((me) => Message.attachment(
            senderId: me,
            recipientId: me,
            attachment: meta,
            caption: caption,
            status: MessageStatus.sent,
          ));
    }

    final group = await _groupOrNull(contactId);
    if (group != null) {
      await service.sendGroupAttachment(
        group,
        bytes: bytes,
        fileName: fileName,
        mime: mime,
        caption: caption,
      );
    } else {
      final contact = await _contact(contactId);
      await service.sendAttachment(
        contact,
        bytes: bytes,
        fileName: fileName,
        mime: mime,
        caption: caption,
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
    if (isNotes(contactId)) {
      final meta = await service.prepareNoteAttachment(
          bytes: bytes,
          fileName: 'voice-message.m4a',
          mime: mime,
          durationMs: durationMs);
      return _addNote((me) => Message.attachment(
            senderId: me,
            recipientId: me,
            attachment: meta,
            status: MessageStatus.sent,
          ));
    }
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

  /// Přepošle zprávu do jiné konverzace (kontakt i skupina). Příloha se
  /// dešifruje a odešle znovu s novým klíčem: odkaz na původní blob by
  /// vypršel s ním (relay drží bloby 30 dní) a cíl by ho neměl čím otevřít.
  Future<void> forwardMessage(Message message, String targetId) async {
    final meta = message.attachment;
    if (meta == null) {
      await sendMessage(targetId, message.content ?? '');
      return;
    }
    final bytes = await ref
        .read(messagingServiceProvider)
        .loadDecryptedAttachment(message);
    if (bytes == null) throw const AttachmentUnavailableError();
    if (meta.mime.startsWith('audio/') && meta.durationMs != null) {
      await sendVoiceMessage(targetId,
          bytes: bytes, durationMs: meta.durationMs!, mime: meta.mime);
      return;
    }
    await sendAttachment(
      targetId,
      bytes: bytes,
      fileName: meta.name ?? 'attachment',
      mime: meta.mime,
      caption: message.content,
    );
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
        .toList();

    conv.markAllRead(identity.id);
    await storage.saveConversation(conv);
    state = AsyncData(await storage.loadConversations());

    if (justRead.isEmpty) return;
    // Ve skupině dostane potvrzení jen autor dané zprávy — ne celý roster.
    // Otevření chatu tak stojí tolik obálek, kolik lidí mezitím psalo.
    final group = await _groupOrNull(contactId);
    final byAuthor = <String, List<String>>{};
    for (final m in justRead) {
      byAuthor.putIfAbsent(m.senderId, () => []).add(m.id);
    }
    final contacts = await storage.loadContacts();
    final service = ref.read(messagingServiceProvider);
    for (final MapEntry(key: author, value: ids) in byAuthor.entries) {
      final contact = contacts.where((c) => c.id == author).firstOrNull;
      if (contact == null) continue;
      await service.sendReadReceipts(contact, ids, gid: group?.id);
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
