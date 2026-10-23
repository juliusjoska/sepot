import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/contact_name.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/core/utils/text_fold.dart';
import 'package:sepot/features/chat_list/chat_list_tile.dart';
import 'package:sepot/features/chat_list/push_hint_banner.dart';
import 'package:sepot/features/contacts/contacts_screen.dart';
import 'package:sepot/features/settings/settings_screen.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/drafts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/push_provider.dart';
import 'package:sepot/widgets/avatar.dart';
import 'package:sepot/widgets/e2e_badge.dart';
import 'package:sepot/widgets/glass.dart';

/// Výška plovoucí navigace včetně okraje — obsah karet pod ní končí.
const _navHeight = 66.0 + 18.0;

/// Domovská obrazovka: karty Chaty / Kontakty / Nastavení pod průsvitnou
/// plovoucí navigací.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Nastartuje krypto + spojení s relayem (idempotentní)
    ref.watch(messagingStartProvider);
    // Zaregistruje push callbacky (po startu messagingu) a obnoví režim.
    ref.watch(pushInitProvider);

    final l10n = context.l10n;
    // S klávesnicí (hledání) by navigace i „Nový chat“ plavaly nad ní.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Pod plovoucí navigací je ještě systémová lišta telefonu.
    final tabBottom = _navHeight + MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          _ChatsTab(onOpenSettings: () => setState(() => _tab = 2)),
          // Kontakty a Nastavení mají vlastní Scaffold; spodní okraj, ať
          // poslední položka neskončí pod navigací.
          Padding(
            padding: EdgeInsets.only(bottom: tabBottom),
            child: const ContactsScreen(),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: tabBottom),
            child: const SettingsScreen(),
          ),
        ],
      ),
      floatingActionButton: _tab == 0 && !keyboard
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/contacts'),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.chatListNewChat,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      bottomNavigationBar: keyboard
          ? null
          : SafeArea(
            minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 66,
                child: Row(
                  children: [
                    _NavItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      activeIcon: Icons.chat_bubble_rounded,
                      label: l10n.navChats,
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    _NavItem(
                      icon: Icons.people_outline_rounded,
                      activeIcon: Icons.people_rounded,
                      label: l10n.contactsTitle,
                      selected: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                    _NavItem(
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings_rounded,
                      label: l10n.settingsTitle,
                      selected: _tab == 2,
                      onTap: () => setState(() => _tab = 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? SepotColors.ember : SepotColors.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, size: 23, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Filter { all, unread, groups }

/// Karta Chaty: nadpis, hledání, filtry, připnuté a seznam.
class _ChatsTab extends ConsumerStatefulWidget {
  const _ChatsTab({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  ConsumerState<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<_ChatsTab> {
  final _search = TextEditingController();
  var _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conversationsAsync = ref.watch(conversationsProvider);
    final contacts = ref.watch(contactsProvider).valueOrNull ?? const [];
    final groups = ref.watch(groupsProvider).valueOrNull ?? const [];
    final identity = ref.watch(identityProvider).valueOrNull;
    final myId = identity?.id ?? '';
    final typing = ref.watch(typingProvider).valueOrNull ?? const {};
    final drafts = ref.watch(draftsProvider).valueOrNull ?? const {};

    Contact? contactOf(String id) =>
        contacts.where((c) => c.publicIdentity.id == id).firstOrNull;
    Group? groupOf(String id) => groups.where((g) => g.id == id).firstOrNull;
    String nameOf(Conversation c) => ConversationsNotifier.isNotes(c.contactId)
        ? l10n.notesTitle
        : groupOf(c.contactId)?.name ??
        _nameOrNull(l10n, contactOf(c.contactId)) ??
        l10n.commonUnknownContact;

    return SafeArea(
      bottom: false,
      child: conversationsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: SepotColors.ember)),
        error: (e, _) => Center(child: Text(describeError(l10n, e))),
        data: (conversations) {
          final active = conversations.where((c) => !c.archived).toList();
          final archived = conversations.where((c) => c.archived).length;
          final query = _search.text.trim();
          final searching = query.isNotEmpty;

          // Hledání: jméno i obsah zpráv, bez diakritiky. U shody ve zprávě
          // se místo poslední zprávy ukáže ta nalezená.
          final hits = <Conversation, Message?>{};
          if (searching) {
            final q = fold(query);
            for (final c in conversations) {
              if (fold(nameOf(c)).contains(q)) {
                hits[c] = null;
                continue;
              }
              final m = c.messages.reversed
                  .where((m) =>
                      !m.isDeleted &&
                      m.content != null &&
                      fold(m.content!).contains(q))
                  .firstOrNull;
              if (m != null) hits[c] = m;
            }
          }

          final unreadCount =
              active.where((c) => c.unreadCount(myId) > 0).length;
          final pinned = active.where((c) => c.pinned).toList();
          final list = searching
              ? hits.keys.toList()
              : active.where((c) {
                  if (_filter == _Filter.all && c.pinned) return false;
                  return switch (_filter) {
                    _Filter.all => true,
                    _Filter.unread => c.unreadCount(myId) > 0,
                    _Filter.groups => groupOf(c.contactId) != null,
                  };
                }).toList();

          Widget tile(Conversation c) {
            final group = groupOf(c.contactId);
            final last = c.lastMessage;
            final writers = typing[c.contactId] ?? const <String>{};
            final typingLabel = writers.isEmpty
                ? null
                : group == null
                    ? l10n.chatTyping
                    : writers.length == 1
                        ? l10n.chatTypingNamed(
                            (_nameOrNull(l10n, contactOf(writers.first)) ??
                                    '?')
                                .split(' ')
                                .first)
                        : l10n.chatTypingSeveral;
            return ChatListTile(
              conversation: c,
              contactName: nameOf(c),
              myId: myId,
              isGroup: group != null,
              verified: contactOf(c.contactId)?.verified ?? false,
              isRequest: group == null &&
                  contactOf(c.contactId)?.accepted == false,
              lastAuthor: group != null && last != null
                  ? _nameOrNull(l10n, contactOf(last.senderId))
                  : null,
              highlight: hits[c],
              typingLabel: typingLabel,
              draft: hits[c] == null ? drafts[c.contactId] : null,
              onTap: () => context.push('/conversation/${c.contactId}'),
              onLongPress: () => _showChatActions(c, nameOf(c)),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l10n.navChats,
                            style: SepotTheme.largeTitle),
                      ),
                      IconButton.filledTonal(
                        tooltip: l10n.qrScanTitle,
                        style: IconButton.styleFrom(
                            backgroundColor: SepotColors.surface,
                            foregroundColor: SepotColors.textPrimary),
                        onPressed: () => context.push('/qr-scan'),
                        icon: const Icon(Icons.qr_code_scanner_rounded,
                            size: 21),
                      ),
                      const SizedBox(width: 6),
                      Semantics(
                        button: true,
                        label: l10n.settingsTitle,
                        child: GestureDetector(
                          onTap: widget.onOpenSettings,
                          child: SepotAvatar(
                            name: identity?.displayName ?? '?',
                            seed: myId,
                            size: 42,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.chatListSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: SepotColors.textSecondary),
                      suffixIcon: searching
                          ? IconButton(
                              tooltip: l10n.commonCancel,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () =>
                                  setState(() => _search.clear()),
                            )
                          : null,
                      filled: true,
                      fillColor: SepotColors.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: SepotColors.ember, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              // Bez budíčků appka na pozadí spí — ať uživatel ví, proč
              // mu zprávy chodí, až když Šepot otevře.
              const SliverToBoxAdapter(child: PushHintBanner()),
              if (!searching)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [
                        _FilterChip(
                          label: l10n.chatFilterAll,
                          selected: _filter == _Filter.all,
                          onTap: () => setState(() => _filter = _Filter.all),
                        ),
                        _FilterChip(
                          label: l10n.chatFilterUnread,
                          count: unreadCount,
                          selected: _filter == _Filter.unread,
                          onTap: () =>
                              setState(() => _filter = _Filter.unread),
                        ),
                        _FilterChip(
                          label: l10n.chatFilterGroups,
                          selected: _filter == _Filter.groups,
                          onTap: () =>
                              setState(() => _filter = _Filter.groups),
                        ),
                        if (archived > 0)
                          _FilterChip(
                            label: l10n.chatFilterArchive,
                            count: archived,
                            icon: Icons.archive_outlined,
                            selected: false,
                            onTap: () => context.push('/archived'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (!searching && _filter == _Filter.all && pinned.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      itemCount: pinned.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final c = pinned[i];
                        return _PinnedChat(
                          name: nameOf(c),
                          seed: c.contactId,
                          isGroup: groupOf(c.contactId) != null,
                          unread: c.unreadCount(myId) > 0 && !c.isMuted,
                          onTap: () =>
                              context.push('/conversation/${c.contactId}'),
                          onLongPress: () => _showChatActions(c, nameOf(c)),
                        );
                      },
                    ),
                  ),
                ),
              if (conversations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else if (list.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(
                      searching ? l10n.chatListNoResults : l10n.chatListFilterEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SepotColors.textSecondary),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => tile(list[i]),
                ),
              // Místo pro „Nový chat“ a plovoucí navigaci.
              const SliverToBoxAdapter(child: SizedBox(height: 170)),
            ],
          );
        },
      ),
    );
  }

  /// Akce nad konverzací (long-press): připnout / ztlumit / archivovat.
  void _showChatActions(Conversation conv, String name) {
    final notifier = ref.read(conversationsProvider.notifier);
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
            ListTile(
              leading: Icon(conv.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded),
              title: Text(conv.pinned ? l10n.chatListUnpin : l10n.chatListPin),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setPinned(conv.contactId, !conv.pinned);
              },
            ),
            ListTile(
              leading: Icon(conv.isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined),
              title: Text(
                  conv.isMuted ? l10n.chatListUnmute : l10n.chatListMute),
              onTap: () {
                Navigator.pop(ctx);
                notifier.setMuted(conv.contactId, !conv.isMuted);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(l10n.chatListArchive),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? SepotColors.ember : SepotColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: selected ? SepotColors.ember : SepotColors.border),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: SepotColors.textEmphasis),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? SepotColors.emberInk
                        : SepotColors.textEmphasis,
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? SepotColors.emberInk
                          : SepotColors.ember,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedChat extends StatelessWidget {
  const _PinnedChat({
    required this.name,
    required this.seed,
    required this.isGroup,
    required this.unread,
    required this.onTap,
    required this.onLongPress,
  });

  final String name;
  final String seed;
  final bool isGroup;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            isGroup
                ? Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: unread ? SepotColors.ember : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: SepotGroupAvatar(seed: seed, size: 54),
                  )
                : SepotAvatar(
                    name: name,
                    seed: seed,
                    size: 54,
                    ring: unread ? SepotColors.ember : SepotColors.border,
                  ),
            const SizedBox(height: 6),
            Text(
              name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
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
            child: const Icon(Icons.chat_bubble_outline_rounded,
                size: 40, color: SepotColors.ember),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.chatListEmptyTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.chatListEmptySubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SepotColors.textSecondary),
          ),
          const SizedBox(height: 32),
          const E2EBadge(),
        ],
      ),
    );
  }
}

String? _nameOrNull(AppLocalizations l10n, Contact? c) =>
    c == null ? null : contactName(l10n, c);
