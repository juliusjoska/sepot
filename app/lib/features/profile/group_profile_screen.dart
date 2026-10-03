import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/conversation/chat_actions.dart';
import 'package:sepot/features/profile/profile_widgets.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/widgets/avatar.dart';

/// Profil skupiny: členové a jejich ověření, přidání lidí, sdílená média,
/// nastavení konverzace a odchod.
///
/// Členství, role a jméno mění správci. Ne-správce
/// vidí akce neaktivní a pod členy vysvětlení; přidávat lidi smí i on, dokud
/// je ve skupině někdo se starší verzí (v1 to umí a skupina se nesmí
/// rozejít).
class GroupProfileScreen extends ConsumerWidget {
  const GroupProfileScreen({
    super.key,
    required this.groupId,
    this.fromChat = false,
  });

  final String groupId;
  final bool fromChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    final conv = ref.watch(conversationProvider(groupId)).valueOrNull;
    final contacts = ref.watch(contactsProvider).valueOrNull ?? const [];
    final myId = ref.watch(identityProvider).valueOrNull?.id;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
            child: CircularProgressIndicator(color: SepotColors.ember)),
      );
    }

    final me = myId ?? '';
    final amAdmin = group.isAdmin(me);
    final active = !group.left;
    final canAdd = active && (amAdmin || !group.isEnforced(me));
    final canRename = active && amAdmin;
    final rejectedAt = group.rejectedOpAt;
    final rejectedRecently = rejectedAt != null &&
        DateTime.now().difference(rejectedAt) < _rejectedNoticeFor;

    final muted = conv?.isMuted ?? false;
    final locale = Localizations.localeOf(context).toString();

    void openChat({bool search = false}) {
      if (fromChat) {
        Navigator.of(context).pop(search ? ProfileResult.openSearch : null);
      } else {
        context.push('/conversation/$groupId${search ? '?search=1' : ''}');
      }
    }

    // Já první, pak ověření, pak ostatní — kdo je důvěryhodný, je nahoře.
    final members = [...group.memberIds]..sort((a, b) {
        if (a == myId) return -1;
        if (b == myId) return 1;
        final va = contacts.any((c) => c.id == a && c.verified) ? 0 : 1;
        final vb = contacts.any((c) => c.id == b && c.verified) ? 0 : 1;
        return va.compareTo(vb);
      });

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ProfileHero(
            avatar: SepotGroupAvatar(seed: groupId, size: 104),
            title: group.name,
            onTitleTap:
                canRename ? () => renameGroup(context, ref, group) : null,
            lines: [
              Text(
                group.left
                    ? l10n.groupsYouLeftGroup
                    : l10n.profileGroupSubtitle(
                        l10n.groupsMemberCount(group.memberIds.length),
                        DateFormat.yMMMd(locale).format(group.createdAt)),
                style: const TextStyle(
                    fontSize: 13, color: SepotColors.textSecondary),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ProfileAction(
                      icon: Icons.person_add_alt_1_outlined,
                      label: l10n.profileAdd,
                      accent: true,
                      onTap: canAdd
                          ? () => context.push('/group/$groupId/add')
                          : null,
                    ),
                    const SizedBox(width: 8),
                    ProfileAction(
                      icon: Icons.search_rounded,
                      label: l10n.profileSearch,
                      onTap: () => openChat(search: true),
                    ),
                    const SizedBox(width: 8),
                    ProfileAction(
                      icon: muted
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      label: muted ? l10n.profileUnmute : l10n.chatListMute,
                      onTap: conv == null
                          ? null
                          : () => ref
                              .read(conversationsProvider.notifier)
                              .setMuted(groupId, !muted)
                              .then((_) => ref
                                  .invalidate(conversationProvider(groupId))),
                    ),
                    const SizedBox(width: 8),
                    ProfileAction(
                      icon: Icons.timer_outlined,
                      label: l10n.profileDisappearing,
                      onTap: group.left
                          ? null
                          : () => configureDisappearing(context, ref, groupId),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (active && group.needsResync) ...[
                  _GroupNotice(
                    icon: Icons.sync_rounded,
                    text: l10n.groupsResyncNotice,
                    color: SepotColors.mist,
                  ),
                  const SizedBox(height: 10),
                ],
                if (active && rejectedRecently) ...[
                  _GroupNotice(
                    icon: Icons.gpp_maybe_outlined,
                    text: l10n.groupsRejectedChangeNotice,
                    color: SepotColors.warning,
                  ),
                  const SizedBox(height: 10),
                ],
                ProfileCard(
                  title: l10n.groupsMembers,
                  trailing: l10n.profileMembersOfMax(
                      group.memberIds.length, Group.maxMembers),
                  children: [
                    for (final f in members)
                      _MemberRow(
                        group: group,
                        fingerprint: f,
                        isMe: f == myId,
                        canManage: active && amAdmin,
                      ),
                  ],
                ),
                if (active && !amAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 16, color: SepotColors.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            group.isEnforced(me)
                                ? l10n.groupsAdminOnlyHint
                                : l10n.groupsAdminOnlyCompatHint,
                            style: const TextStyle(
                                fontSize: 13,
                                color: SepotColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                if (conv != null) ...[
                  SharedMediaCard(messages: conv.messages),
                  const SizedBox(height: 14),
                ],
                ProfileCard(
                  children: [
                    ProfileRow(
                      label: l10n.chatDisappearingMessages,
                      value: disappearingLabel(
                          context, conv?.disappearAfterSeconds),
                      onTap: group.left
                          ? null
                          : () => configureDisappearing(context, ref, groupId),
                    ),
                  ],
                ),
                if (!group.left) ...[
                  const SizedBox(height: 14),
                  ProfileCard(
                    children: [
                      ProfileRow(
                        label: l10n.groupsLeave,
                        danger: true,
                        onTap: () async {
                          if (await leaveGroup(context, ref, group) &&
                              context.mounted) {
                            context.go('/chats');
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jak dlouho po odmítnuté neoprávněné změně skupiny o ní profil mluví.
const _rejectedNoticeFor = Duration(days: 7);

/// Upozornění nad seznamem členů (resync, odmítnutá změna).
class _GroupNotice extends StatelessWidget {
  const _GroupNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: SepotColors.textEmphasis)),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.group,
    required this.fingerprint,
    required this.isMe,
    required this.canManage,
  });

  final Group group;
  final String fingerprint;
  final bool isMe;

  /// Dívám se jako správce — řádek otevře nabídku správcovských akcí.
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final identity = ref.watch(identityProvider).valueOrNull;
    final contact = (ref.watch(contactsProvider).valueOrNull ?? const [])
        .where((c) => c.id == fingerprint)
        .firstOrNull;
    final name = isMe
        ? l10n.groupsYou
        : contact == null
            ? 'SEP-${fingerprint.substring(0, fingerprint.length.clamp(0, 10))}'
            : contactLabel(context, contact);
    final verified = contact?.verified ?? false;
    final isAdmin = group.isAdmin(fingerprint);
    final isFounder = fingerprint == group.createdBy;
    // Správce má přednost: zakladatel, který roli předal, už nic neřídí.
    final badge = isAdmin
        ? l10n.groupsAdmin
        : isFounder && !group.provisional
            ? l10n.groupsFounder
            : null;

    void openContact() => context.push('/contact/$fingerprint');

    return ProfileRow(
      leading: SepotAvatar(
        name: isMe ? (identity?.displayName ?? name) : name,
        seed: fingerprint,
        size: 40,
        verified: verified,
      ),
      label: name,
      subtitle: isMe
          ? null
          : verified
              ? l10n.verifyVerified
              : l10n.verifyUnverified,
      trailing: badge == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isAdmin
                    ? SepotColors.ember.withValues(alpha: 0.12)
                    : SepotColors.border,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(badge,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isAdmin
                          ? SepotColors.ember
                          : SepotColors.textSecondary)),
            ),
      onTap: isMe
          ? null
          : canManage
              ? () => _showMemberActions(context, ref,
                  name: name,
                  isAdmin: isAdmin,
                  onOpenContact: contact == null ? null : openContact)
              : contact == null
                  ? null
                  : openContact,
    );
  }

  void _showMemberActions(
    BuildContext context,
    WidgetRef ref, {
    required String name,
    required bool isAdmin,
    required VoidCallback? onOpenContact,
  }) {
    final l10n = context.l10n;
    HapticFeedback.mediumImpact();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (onOpenContact != null)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(l10n.groupsViewContact),
                onTap: () {
                  Navigator.pop(ctx);
                  onOpenContact();
                },
              ),
            ListTile(
              leading: Icon(isAdmin
                  ? Icons.remove_moderator_outlined
                  : Icons.add_moderator_outlined),
              title: Text(
                  isAdmin ? l10n.groupsDismissAdmin : l10n.groupsMakeAdmin),
              onTap: () {
                Navigator.pop(ctx);
                setGroupAdmin(context, ref, group, fingerprint, !isAdmin);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: SepotColors.error),
              title: Text(l10n.groupsRemoveMember,
                  style: const TextStyle(color: SepotColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                removeGroupMember(context, ref, group, fingerprint, name);
              },
            ),
          ],
        ),
      ),
    );
  }
}
