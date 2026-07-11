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

/// Archivované konverzace — stejné dlaždice, long-press nabídne odarchivovat.
class ArchivedChatsScreen extends ConsumerWidget {
  const ArchivedChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final myId = ref.watch(identityProvider).valueOrNull?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.archiveTitle)),
      body: conversationsAsync.when(
        data: (conversations) {
          final archived = conversations.where((c) => c.archived).toList();
          if (archived.isEmpty) {
            return Center(
              child: Text(context.l10n.archiveEmpty,
                  style: const TextStyle(color: SepotColors.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: archived.length,
            itemBuilder: (context, index) {
              final conv = archived[index];
              final group = groupsAsync.valueOrNull
                  ?.where((g) => g.id == conv.contactId)
                  .firstOrNull;
              final contact = contactsAsync.valueOrNull
                  ?.where((c) => c.publicIdentity.id == conv.contactId)
                  .firstOrNull;
              final name = group?.name ??
                  contact?.displayName ??
                  context.l10n.commonUnknownContact;
              return ChatListTile(
                conversation: conv,
                contactName: name,
                myId: myId,
                isGroup: group != null,
                onTap: () => context.push('/conversation/${conv.contactId}'),
                onLongPress: () => _actions(context, ref, conv),
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
    );
  }

  void _actions(BuildContext context, WidgetRef ref, Conversation conv) {
    final notifier = ref.read(conversationsProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SepotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.unarchive_outlined),
          title: Text(context.l10n.archiveUnarchive),
          onTap: () {
            Navigator.pop(ctx);
            notifier.setArchived(conv.contactId, false);
          },
        ),
      ),
    );
  }
}
