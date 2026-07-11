import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/chat_list/chat_list_tile.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/push_provider.dart';
import 'package:sepot/widgets/e2e_badge.dart';

/// Hlavní obrazovka — seznam konverzací
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nastartuje krypto + spojení s relayem (idempotentní)
    ref.watch(messagingStartProvider);
    // Zaregistruje push callbacky (po startu messagingu) — obnoví registraci,
    // pokud už distributor byl dřív vybraný. Push zapíná uživatel v nastavení.
    ref.watch(pushInitProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.commonAppName,
          style: const TextStyle(
            fontFamily: kFontSans,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              // TODO: Implementovat vyhledávání
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: conversationsAsync.when(
        data: (conversations) {
          final active = conversations.where((c) => !c.archived).toList();
          final archived = conversations.where((c) => c.archived).toList();
          if (active.isEmpty && archived.isEmpty) {
            return _buildEmptyState(context);
          }
          final hasArchive = archived.isNotEmpty;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: active.length + (hasArchive ? 1 : 0),
            itemBuilder: (context, index) {
              if (hasArchive && index == 0) {
                return ListTile(
                  leading: const Icon(Icons.archive_outlined,
                      color: SepotColors.textMuted),
                  title: Text(context.l10n.chatListArchivedCount(archived.length),
                      style: const TextStyle(color: SepotColors.textSecondary)),
                  onTap: () => context.push('/archived'),
                );
              }
              final conv = active[index - (hasArchive ? 1 : 0)];
              final group = groupsAsync.valueOrNull
                  ?.where((g) => g.id == conv.contactId)
                  .firstOrNull;
              final contact = contactsAsync.valueOrNull
                  ?.where((c) => c.publicIdentity.id == conv.contactId)
                  .firstOrNull;
              final myId = identityAsync.valueOrNull?.id ?? '';
              final name = group?.name ??
                  contact?.displayName ??
                  context.l10n.commonUnknownContact;

              return ChatListTile(
                conversation: conv,
                contactName: name,
                myId: myId,
                isGroup: group != null,
                onTap: () => context.push('/conversation/${conv.contactId}'),
                onLongPress: () => _showChatActions(context, ref, conv, name),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: SepotColors.ember),
        ),
        error: (e, _) =>
            Center(child: Text(describeError(context.l10n, e))),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/contacts'),
        child: const Icon(Icons.chat_bubble_outline_rounded),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SepotColors.ember.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: SepotColors.ember,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.chatListEmptyTitle,
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: SepotColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chatListEmptySubtitle,
              style: const TextStyle(color: SepotColors.textSecondary),
            ),
            const SizedBox(height: 32),
            const E2EBadge(),
          ],
        ),
      ),
    );
  }

  /// Akce nad konverzací (long-press): ztlumit / archivovat.
  void _showChatActions(
      BuildContext context, WidgetRef ref, Conversation conv, String name) {
    final notifier = ref.read(conversationsProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SepotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(conv.isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined),
              title: Text(conv.isMuted
                  ? context.l10n.chatListUnmute
                  : context.l10n.chatListMute),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setMuted(conv.contactId, !conv.isMuted);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(context.l10n.chatListArchive),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setArchived(conv.contactId, true);
              },
            ),
          ],
        ),
      ),
    );
  }
}
