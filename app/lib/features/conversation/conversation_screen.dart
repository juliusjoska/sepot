import 'dart:async';
import 'dart:io';


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/conversation/widgets/attachment_content.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/features/conversation/photo_preview_screen.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/avatar.dart';
import 'package:sepot/widgets/e2e_badge.dart';

enum _AttachAction { gallery, camera, document }

/// Chat obrazovka — zprávy s kontaktem
class ConversationScreen extends ConsumerStatefulWidget {
  final String contactId;

  const ConversationScreen({super.key, required this.contactId});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  Message? _replyingTo; // aktivní odpověď (nad inputem)
  String? _editingId; // id právě upravované zprávy

  // Nahrávání hlasové zprávy
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDur = Duration.zero;
  Timer? _recordTimer;
  String? _recordPath;

  /// Malá sada emoji pro rychlé reakce.
  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  void initState() {
    super.initState();
    // Označ zprávy jako přečtené
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(conversationsProvider.notifier).markAsRead(widget.contactId);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final contact = contacts
        .where((c) => c.publicIdentity.id == widget.contactId)
        .firstOrNull;
    final conversationAsync = ref.watch(conversationProvider(widget.contactId));
    final identity = ref.watch(identityProvider).valueOrNull;
    // Skupinová konverzace: contactId == gid
    final group = ref.watch(groupProvider(widget.contactId)).valueOrNull;

    if (group != null) {
      return _buildGroupScaffold(context, group, conversationAsync, identity,
          contacts: contacts);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            SepotAvatar(name: contact?.displayName ?? '?', size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (contact == null || contact.displayName.isEmpty)
                        ? context.l10n.commonUnknownContact
                        : contact.displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Stav ověření místo syrového ID —
                  // klepnutí vede na safety number obrazovku
                  if (contact != null)
                    GestureDetector(
                      onTap: () => context.push('/verify/${contact.id}'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            contact.verified
                                ? Icons.verified
                                : Icons.shield_outlined,
                            size: 12,
                            color: contact.verified
                                ? SepotColors.sage
                                : SepotColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            contact.verified
                                ? context.l10n.verifyVerified
                                : context.l10n.verifyUnverified,
                            style: TextStyle(
                              fontSize: 11,
                              color: contact.verified
                                  ? SepotColors.sage
                                  : SepotColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          const E2EBadge(compact: true),
          const SizedBox(width: 8),
          if (contact != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'verify':
                    context.push('/verify/${contact.id}');
                  case 'disappearing':
                    _configureDisappearing();
                  case 'block':
                    _setBlocked(contact, true);
                  case 'unblock':
                    _setBlocked(contact, false);
                  case 'report':
                    _reportAndBlock(contact);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'verify',
                  child: Text(context.l10n.chatMenuVerifyContact),
                ),
                PopupMenuItem(
                  value: 'disappearing',
                  child: Text(context.l10n.chatDisappearingMessages),
                ),
                const PopupMenuDivider(),
                if (contact.blocked)
                  PopupMenuItem(
                    value: 'unblock',
                    child: Text(context.l10n.chatMenuUnblockContact),
                  )
                else ...[
                  PopupMenuItem(
                    value: 'block',
                    child: Text(context.l10n.chatMenuBlockContact),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: Text(context.l10n.reportAndBlock,
                        style: const TextStyle(color: SepotColors.error)),
                  ),
                ],
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Seznam zpráv
          Expanded(
            child: conversationAsync.when(
              data: (conversation) {
                final messages = conversation?.messages ?? [];

                if (messages.isEmpty) {
                  return _buildEmptyChat();
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[messages.length - 1 - index];
                    final isMine = msg.isMine(identity?.id ?? '');
                    final showDate = index == messages.length - 1 ||
                        !_isSameDay(
                          msg.timestamp,
                          messages[messages.length - 2 - index].timestamp,
                        );
                    final repliedTo = msg.replyToId == null
                        ? null
                        : messages
                            .where((m) => m.id == msg.replyToId)
                            .firstOrNull;

                    return Column(
                      children: [
                        if (showDate) _buildDateDivider(msg.timestamp),
                        _MessageBubble(
                          message: msg,
                          isMine: isMine,
                          contactId: widget.contactId,
                          repliedTo: repliedTo,
                          onLongPress: () => _showMessageActions(msg, isMine),
                          onToggleReaction: (emoji) =>
                              _toggleReaction(msg, emoji),
                        ),
                      ],
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
          ),
          // Input bar — nebo banner, když je kontakt blokovaný
          if (contact?.blocked == true)
            _buildBlockedBanner(contact!)
          else
            _buildInputBar(),
        ],
      ),
    );
  }

  /// Skupinová konverzace : jména autorů nad cizími
  /// bublinami, menu Členové / Přejmenovat / Opustit, žádný verify badge
  /// (ověřují se jednotliví členové v Kontaktech).
  Widget _buildGroupScaffold(
    BuildContext context,
    Group group,
    AsyncValue<Conversation?> conversationAsync,
    LocalIdentity? identity, {
    required List<Contact> contacts,
  }) {
    // Fingerprint → jméno pro popisky autorů. Členy, kteří ještě nejsou
    // v kontaktech (roster je zakládá až s první zprávou), zkrátíme na id.
    String autorJmeno(String fingerprint) {
      final jmeno = contacts
          .where((c) => c.publicIdentity.id == fingerprint)
          .firstOrNull
          ?.displayName;
      if (jmeno == null) {
        return 'SEP-${fingerprint.substring(0, fingerprint.length.clamp(0, 10))}';
      }
      return jmeno.isEmpty ? context.l10n.commonUnknownContact : jmeno;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SepotColors.ember.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_rounded,
                  size: 20, color: SepotColors.ember),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showGroupMembers(group, autorJmeno),
                    child: Text(
                      group.left
                          ? context.l10n.groupsYouLeftGroup
                          : context.l10n
                              .groupsMemberCount(group.memberIds.length),
                      style: const TextStyle(
                        fontSize: 11,
                        color: SepotColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          const E2EBadge(compact: true),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'members':
                  _showGroupMembers(group, autorJmeno);
                case 'rename':
                  _renameGroup(group);
                case 'disappearing':
                  _configureDisappearing();
                case 'leave':
                  _leaveGroup(group);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'members', child: Text(context.l10n.groupsMembers)),
              if (!group.left) ...[
                PopupMenuItem(
                    value: 'rename', child: Text(context.l10n.groupsRename)),
                PopupMenuItem(
                    value: 'disappearing',
                    child: Text(context.l10n.chatDisappearingMessages)),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'leave',
                  child: Text(context.l10n.groupsLeave,
                      style: const TextStyle(color: SepotColors.error)),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: conversationAsync.when(
              data: (conversation) {
                final messages = conversation?.messages ?? [];
                if (messages.isEmpty) return _buildEmptyChat();

                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[messages.length - 1 - index];
                    final isMine = msg.isMine(identity?.id ?? '');
                    final showDate = index == messages.length - 1 ||
                        !_isSameDay(
                          msg.timestamp,
                          messages[messages.length - 2 - index].timestamp,
                        );
                    final repliedTo = msg.replyToId == null
                        ? null
                        : messages
                            .where((m) => m.id == msg.replyToId)
                            .firstOrNull;

                    // Jméno autora jen u cizí zprávy a jen když ji nepíše
                    // tentýž autor jako předchozí (shlukování bublin).
                    final predchozi = index == messages.length - 1
                        ? null
                        : messages[messages.length - 2 - index];
                    final zobrazAutora = !isMine &&
                        (showDate ||
                            predchozi == null ||
                            predchozi.senderId != msg.senderId);

                    return Column(
                      children: [
                        if (showDate) _buildDateDivider(msg.timestamp),
                        if (zobrazAutora)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: 12, bottom: 2),
                              child: Text(
                                autorJmeno(msg.senderId),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: SepotColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        _MessageBubble(
                          message: msg,
                          isMine: isMine,
                          contactId: widget.contactId,
                          repliedTo: repliedTo,
                          onLongPress: () => _showMessageActions(msg, isMine),
                          onToggleReaction: (emoji) =>
                              _toggleReaction(msg, emoji),
                        ),
                      ],
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
          ),
          if (group.left) _buildLeftGroupBanner() else _buildInputBar(),
        ],
      ),
    );
  }

  /// Banner místo inputu ve skupině, kterou jsem opustil.
  Widget _buildLeftGroupBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: SepotColors.surface),
      child: Text(
        context.l10n.groupsLeftBanner,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: SepotColors.textMuted),
      ),
    );
  }

  void _showGroupMembers(Group group, String Function(String) autorJmeno) {
    final identity = ref.read(identityProvider).valueOrNull;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SepotColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.groupsMembersWithCount(group.memberIds.length),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in group.memberIds)
                    // Sebe ukazuj vlastním jménem — autorJmeno() by pro můj
                    // fingerprint spadlo na „SEP-…" (v kontaktech nejsem).
                    ListTile(
                      leading: SepotAvatar(
                        name: f == identity?.id
                            ? (identity?.displayName ?? context.l10n.groupsYou)
                            : autorJmeno(f),
                        size: 36,
                      ),
                      title: Text(
                        f == identity?.id
                            ? context.l10n.groupsYou
                            : autorJmeno(f),
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: f == group.createdBy
                          ? Text(context.l10n.groupsFounder,
                              style: const TextStyle(fontSize: 11))
                          : null,
                      // Ověření členů běží přes Kontakty (skupina nemá
                      // vlastní safety number — každá dvojice má svůj).
                      onTap: f == identity?.id
                          ? null
                          : () {
                              Navigator.of(ctx).pop();
                              context.push('/verify/$f');
                            },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _renameGroup(Group group) async {
    final controller = TextEditingController(text: group.name);
    final novy = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.groupsRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration:
              InputDecoration(hintText: context.l10n.groupsNameHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.l10n.commonCancel)),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
    if (novy == null || novy.isEmpty || novy == group.name) return;
    try {
      await ref.read(groupsProvider.notifier).rename(group, novy);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .groupsRenameFailed(describeError(context.l10n, e)))),
        );
      }
    }
  }

  Future<void> _leaveGroup(Group group) async {
    final potvrzeno = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.groupsLeaveConfirmTitle),
        content: Text(
          context.l10n.groupsLeaveConfirmBody,
          style: const TextStyle(color: SepotColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.commonCancel)),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: SepotColors.error),
            child: Text(context.l10n.groupsLeaveAction),
          ),
        ],
      ),
    );
    if (potvrzeno != true) return;
    try {
      await ref.read(groupsProvider.notifier).leave(group);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .groupsLeaveFailed(describeError(context.l10n, e)))),
        );
      }
    }
  }

  /// Banner místo inputu u blokovaného kontaktu.
  Widget _buildBlockedBanner(Contact contact) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: SepotColors.surface,
        border: Border(top: BorderSide(color: SepotColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.chatBlockedBanner,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: SepotColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _setBlocked(contact, false),
              child: Text(context.l10n.chatUnblock),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setBlocked(Contact contact, bool blocked) async {
    await ref
        .read(contactsProvider.notifier)
        .setBlocked(contact.id, blocked);
    if (mounted) {
      final jmeno = contact.displayName.isEmpty
          ? context.l10n.commonUnknownContact
          : contact.displayName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(blocked
              ? context.l10n.chatContactBlocked(jmeno)
              : context.l10n.chatContactUnblocked(jmeno)),
        ),
      );
    }
  }

  Future<void> _reportAndBlock(Contact contact) async {
    final jmeno = contact.displayName.isEmpty
        ? context.l10n.commonUnknownContact
        : contact.displayName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.reportAndBlock),
        content: Text(context.l10n.reportAndBlockBody(jmeno)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.reportAndBlock,
                style: const TextStyle(color: SepotColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _setBlocked(contact, true);
    if (!mounted) return;

    final q = <String, String>{
      'contact': contact.id,
      'name': contact.displayName,
    };
    context.push(Uri(path: '/report', queryParameters: q).toString());
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const E2EBadge(),
          const SizedBox(height: 16),
          Text(
            context.l10n.chatEmptyEncrypted,
            style: const TextStyle(
                fontFamily: kFontSans,
              fontSize: 14,
              color: SepotColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.chatEmptyNoOneElse,
            style: const TextStyle(
                fontFamily: kFontSans,
              fontSize: 14,
              color: SepotColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final now = DateTime.now();
    String text;

    if (_isSameDay(date, now)) {
      text = context.l10n.commonToday;
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      text = context.l10n.commonYesterday;
    } else {
      text = DateFormat.yMMMd(Localizations.localeOf(context).toString())
          .format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: SepotColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: SepotColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText =
        _messageController.text.trim().isNotEmpty || _editingId != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: SepotColors.surface,
        border: Border(
          top: BorderSide(color: SepotColors.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null || _editingId != null) _buildComposeBanner(),
            if (_isRecording)
              _buildRecordingBar()
            else
              // Jedno pole s tenkým obrysem (odlišené od plných bublin),
              // příloha i mikrofon/odeslat UVNITŘ. `filled: false` PŘEBÍJÍ
              // globální InputDecorationTheme (jinak by vzniklo vnořené pole).
              Container(
                decoration: BoxDecoration(
                  color: SepotColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: SepotColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.attach_file_rounded,
                          size: 22, color: SepotColors.textMuted),
                      visualDensity: VisualDensity.compact,
                      onPressed: (_isSending || _editingId != null)
                          ? null
                          : _pickAndSendAttachment,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: context.l10n.chatMessageHint,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 9),
                        ),
                        maxLines: 5,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: SepotColors.ember),
                            )
                          : Icon(
                              hasText
                                  ? (_editingId != null
                                      ? Icons.check_rounded
                                      : Icons.send_rounded)
                                  : Icons.mic_rounded,
                              size: 24,
                              color: SepotColors.ember),
                      visualDensity: VisualDensity.compact,
                      onPressed: _isSending
                          ? null
                          : (hasText ? _sendMessage : _startRecording),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtRec(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Lišta při nahrávání hlasové zprávy: zahodit · čas · odeslat.
  Widget _buildRecordingBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline, color: SepotColors.error),
          onPressed: _cancelRecording,
          tooltip: context.l10n.chatDiscardRecording,
        ),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: SepotColors.error),
        ),
        const SizedBox(width: 10),
        Text(_fmtRec(_recordDur),
            style: const TextStyle(
                color: SepotColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(width: 12),
        Text(context.l10n.chatRecording,
            style: const TextStyle(color: SepotColors.textMuted, fontSize: 13)),
        const Spacer(),
        Container(
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: SepotColors.ember),
          child: IconButton(
            icon: const Icon(Icons.send_rounded, color: Colors.white),
            onPressed: _stopAndSend,
          ),
        ),
      ],
    );
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.chatMicPermissionMissing)),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );
      _recordPath = path;
      setState(() {
        _isRecording = true;
        _recordDur = Duration.zero;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordDur += const Duration(seconds: 1));
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .chatRecordingFailed(describeError(context.l10n, e)))),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    final p = _recordPath;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordPath = null;
      });
    }
  }

  Future<void> _stopAndSend() async {
    _recordTimer?.cancel();
    final dur = _recordDur;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    setState(() => _isRecording = false);
    if (path == null) return;
    final file = File(path);
    try {
      // Moc krátké klepnutí — zahoď (uživatel to nechtěl poslat)
      if (dur.inMilliseconds < 800) {
        await file.delete();
        return;
      }
      final bytes = await file.readAsBytes();
      await ref.read(conversationsProvider.notifier).sendVoiceMessage(
            widget.contactId,
            bytes: bytes,
            durationMs: dur.inMilliseconds,
          );
      ref.invalidate(conversationProvider(widget.contactId));
      await file.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .chatVoiceSendFailed(describeError(context.l10n, e)))),
        );
      }
    }
  }

  /// Banner nad inputem: aktivní odpověď nebo režim úpravy.
  Widget _buildComposeBanner() {
    final editing = _editingId != null;
    final preview = editing
        ? _messageController.text
        : (_replyingTo?.isDeleted ?? false
            ? context.l10n.chatDeletedMessagePreview
            : (_replyingTo?.attachment?.isAudio == true
                ? context.l10n.chatVoiceMessagePreview
                : (_replyingTo?.content?.isNotEmpty == true
                    ? _replyingTo!.content!
                    : (_replyingTo?.type == MessageType.image
                        ? context.l10n.chatPhotoPreview
                        : context.l10n.chatAttachmentPreview))));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: SepotColors.ember),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    editing
                        ? context.l10n.chatEditingMessage
                        : context.l10n.chatReply,
                    style: const TextStyle(
                        fontSize: 12,
                        color: SepotColors.ember,
                        fontWeight: FontWeight.w600)),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: SepotColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: SepotColors.textMuted,
            onPressed: () => setState(() {
              _replyingTo = null;
              _editingId = null;
              if (editing) _messageController.clear();
            }),
          ),
        ],
      ),
    );
  }

  /// Akční menu zprávy (long-press): odpovědět / reagovat / upravit /
  /// smazat / kopírovat.
  void _showMessageActions(Message msg, bool isMine) {
    if (msg.isDeleted) return;
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
            // Řádek rychlých reakcí
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _quickReactions)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleReaction(msg, e);
                      },
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: SepotColors.border),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(context.l10n.chatActionReply),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _replyingTo = msg;
                  _editingId = null;
                });
              },
            ),
            if (msg.type == MessageType.text && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(context.l10n.commonCopy),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg.content ?? ''));
                },
              ),
            if (isMine && msg.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(context.l10n.commonEdit),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editingId = msg.id;
                    _replyingTo = null;
                    _messageController.text = msg.content ?? '';
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.chatDeleteForMe),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(conversationsProvider.notifier)
                    .deleteLocalMessage(widget.contactId, msg.id);
                ref.invalidate(conversationProvider(widget.contactId));
              },
            ),
            if (isMine && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.delete_forever,
                    color: SepotColors.error),
                title: Text(context.l10n.chatDeleteForEveryone,
                    style: const TextStyle(color: SepotColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(conversationsProvider.notifier)
                      .deleteMessage(widget.contactId, msg.id);
                  ref.invalidate(conversationProvider(widget.contactId));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReaction(Message msg, String emoji) async {
    final mine = ref.read(identityProvider).valueOrNull?.fingerprint.display;
    final already = mine != null && msg.reactions[mine] == emoji;
    await ref
        .read(conversationsProvider.notifier)
        .reactToMessage(widget.contactId, msg.id, already ? null : emoji);
    ref.invalidate(conversationProvider(widget.contactId));
  }

  /// Per-konverzace TTL mizících zpráv. Platí pro NOVĚ odeslané zprávy
  /// (TTL cestuje E2E kanálem, protistrana ho respektuje). Poctivá
  /// hranice: je to dohoda klientů, ne DRM — screenshot nezastavíš.
  Future<void> _configureDisappearing() async {
    final storage = ref.read(storageProvider);
    final conv = await storage.loadConversation(widget.contactId) ??
        Conversation(contactId: widget.contactId);
    if (!mounted) return;

    final options = <(int, String)>[
      (-1, context.l10n.commonOff),
      (30, context.l10n.chatDisappearing30s),
      (300, context.l10n.chatDisappearing5m),
      (3600, context.l10n.chatDisappearing1h),
      (86400, context.l10n.chatDisappearing1d),
      (604800, context.l10n.chatDisappearing1w),
    ];
    final current = conv.disappearAfterSeconds ?? -1;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.l10n.chatDisappearingMessages),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              context.l10n.chatDisappearingDescription,
              style: const TextStyle(
                  fontSize: 13, color: SepotColors.textSecondary),
            ),
          ),
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(value),
              child: Row(
                children: [
                  Icon(
                    value == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: value == current
                        ? SepotColors.ember
                        : SepotColors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Text(label),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;

    conv.disappearAfterSeconds = picked == -1 ? null : picked;
    await storage.saveConversation(conv);
    ref.invalidate(conversationProvider(widget.contactId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(picked == -1
            ? context.l10n.chatDisappearingDisabled
            : context.l10n.chatDisappearingEnabled(
                options.firstWhere((o) => o.$1 == picked).$2)),
      ));
    }
  }

  Future<void> _pickAndSendAttachment() async {
    final action = await showModalBottomSheet<_AttachAction>(
      context: context,
      backgroundColor: SepotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final (icon, label, value) in [
              (
                Icons.photo_library_outlined,
                context.l10n.attachmentGallery,
                _AttachAction.gallery
              ),
              (
                Icons.photo_camera_outlined,
                context.l10n.attachmentTakePhoto,
                _AttachAction.camera
              ),
              (
                Icons.description_outlined,
                context.l10n.attachmentDocument,
                _AttachAction.document
              ),
            ])
              ListTile(
                leading: Icon(icon, color: SepotColors.ember),
                title: Text(label),
                onTap: () => Navigator.pop(context, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null) return;

    Uint8List? bytes;
    var fileName = '';
    String? mime;
    String? caption;
    try {
      switch (action) {
        case _AttachAction.gallery:
        case _AttachAction.camera:
          // maxWidth/Height 2048 = strop ImageProcessoru; menší vstup šetří
          // RAM při náhledu i finálním renderu úprav.
          final picked = await ImagePicker().pickImage(
            source: action == _AttachAction.gallery
                ? ImageSource.gallery
                : ImageSource.camera,
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 92,
          );
          if (picked == null) return;
          final pickedBytes = await picked.readAsBytes();
          if (!mounted) return;
          // Nic neodchází rovnou z kamery — náhled s úpravami a potvrzením.
          final preview = await Navigator.of(context).push<PhotoPreviewResult>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => PhotoPreviewScreen(
                bytes: pickedBytes,
                fileName: picked.name,
                mime: picked.mimeType,
              ),
            ),
          );
          if (preview == null || !mounted) return;
          bytes = preview.bytes;
          fileName = preview.fileName;
          mime = preview.mime;
          caption = preview.caption;
        case _AttachAction.document:
          final result = await FilePicker.pickFiles(withData: true);
          final file = result?.files.firstOrNull;
          if (file == null || file.bytes == null) return;
          if (file.size > AppConstants.maxAttachmentBytes) {
            if (mounted) {
              _showError(context.l10n.attachmentTooLarge(
                  AppConstants.maxAttachmentBytes ~/ (1024 * 1024)));
            }
            return;
          }
          bytes = file.bytes;
          fileName = file.name;
      }
    } catch (e) {
      if (mounted) {
        _showError(
            context.l10n.attachmentPickFailed(describeError(context.l10n, e)));
      }
      return;
    }
    if (bytes == null) return;

    setState(() => _isSending = true);
    try {
      await ref.read(conversationsProvider.notifier).sendAttachment(
            widget.contactId,
            bytes: bytes,
            fileName: fileName,
            mime: mime,
            caption: caption,
          );
      ref.invalidate(conversationProvider(widget.contactId));
    } catch (e) {
      if (mounted) {
        _showError(
            context.l10n.attachmentSendFailed(describeError(context.l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final editingId = _editingId;
    final replyToId = _replyingTo?.id;
    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final notifier = ref.read(conversationsProvider.notifier);
      if (editingId != null) {
        await notifier.editMessage(widget.contactId, editingId, text);
      } else {
        await notifier.sendMessage(widget.contactId, text,
            replyToId: replyToId);
      }
      if (mounted) {
        setState(() {
          _replyingTo = null;
          _editingId = null;
        });
      }
      ref.invalidate(conversationProvider(widget.contactId));
    } catch (e) {
      if (mounted) {
        _messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  context.l10n.chatSendFailed(describeError(context.l10n, e)))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// Šířka bubliny: textové zprávy se scalují podle obsahu (IntrinsicWidth),
/// obrázky/přílohy zůstávají „plné" — AspectRatio potřebuje šířku od rodiče.
class _CompactWidth extends StatelessWidget {
  const _CompactWidth({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      compact ? IntrinsicWidth(child: child) : child;
}

/// Bublina se zprávou (text, obrázek, dokument)
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final String contactId;
  final Message? repliedTo; // zpráva, na kterou tahle odpovídá
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onToggleReaction;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.contactId,
    this.repliedTo,
    this.onLongPress,
    this.onToggleReaction,
  });

  /// Ztlumený inkoust pro metadata na ember bublině.
  static const _inkSoft = Color(0x8C2B120A);

  @override
  Widget build(BuildContext context) {
    final hasAttachment = !message.isDeleted &&
        message.attachment != null &&
        (message.type == MessageType.image ||
            message.type == MessageType.file);
    if (message.type != MessageType.text &&
        !hasAttachment &&
        !message.isDeleted) {
      return const SizedBox.shrink();
    }
    final isImage = hasAttachment && message.type == MessageType.image;
    final isAudio = hasAttachment && message.attachment!.isAudio;
    final ink = isMine ? SepotColors.emberInk : SepotColors.textPrimary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: message.isDeleted ? null : onLongPress,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: isImage
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? SepotColors.bubbleSent
                    : SepotColors.bubbleReceived,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMine
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isMine
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
              ),
              child: _CompactWidth(
                compact: !isImage && !hasAttachment,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isDeleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block, size: 14, color: ink.withValues(alpha: .6)),
                        const SizedBox(width: 6),
                        Text(context.l10n.chatMessageDeleted,
                            style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: ink.withValues(alpha: .7))),
                      ],
                    )
                  else ...[
                    if (repliedTo != null) _buildQuote(context, ink),
                    if (isImage)
                      ImageAttachmentContent(
                          contactId: contactId, message: message)
                    else if (isAudio)
                      AudioAttachmentContent(
                          contactId: contactId,
                          message: message,
                          isMine: isMine)
                    else if (hasAttachment)
                      DocumentAttachmentContent(
                          contactId: contactId, message: message),
                    if (message.content != null && message.content!.isNotEmpty)
                      Padding(
                        padding: hasAttachment
                            ? const EdgeInsets.only(top: 6, bottom: 2)
                            : EdgeInsets.zero,
                        child: Text(
                          message.content!,
                          style: TextStyle(
                              fontSize: 15, color: ink, height: 1.4),
                        ),
                      ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                        if (message.editedAt != null && !message.isDeleted)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(context.l10n.chatEdited,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: isMine
                                        ? _inkSoft
                                        : SepotColors.textMuted)),
                          ),
                        if (message.isDisappearing)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.timer_outlined,
                                size: 12,
                                color: isMine
                                    ? _inkSoft
                                    : SepotColors.textMuted),
                          ),
                        Text(
                          DateFormat.Hm(
                                  Localizations.localeOf(context).toString())
                              .format(message.timestamp),
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  isMine ? _inkSoft : SepotColors.textMuted),
                        ),
                        if (isMine && !message.isDeleted) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _statusIcon(message.status),
                            size: 14,
                            color: message.status == MessageStatus.failed
                                ? SepotColors.error
                                : message.status == MessageStatus.read
                                    ? SepotColors.mist
                                    : _inkSoft,
                          ),
                        ],
                    ],
                  ),
                ],
              ),
              ),
            ),
          ),
          if (message.reactions.isNotEmpty) _buildReactions(),
        ],
      ),
    );
  }

  Widget _buildQuote(BuildContext context, Color ink) {
    final r = repliedTo!;
    final preview = r.isDeleted
        ? context.l10n.chatDeletedMessagePreview
        : (r.attachment?.isAudio == true
            ? context.l10n.chatVoiceMessagePreview
            : (r.content?.isNotEmpty == true
                ? r.content!
                : (r.type == MessageType.image
                    ? context.l10n.chatPhotoPreview
                    : context.l10n.chatAttachmentPreview)));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(color: ink.withValues(alpha: .5), width: 3)),
      ),
      child: Text(preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: ink.withValues(alpha: .8))),
    );
  }

  /// Seskupené reakce (emoji × počet).
  Widget _buildReactions() {
    final counts = <String, int>{};
    for (final e in message.reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Wrap(
        spacing: 4,
        children: [
          for (final entry in counts.entries)
            GestureDetector(
              onTap: () => onToggleReaction?.call(entry.key),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SepotColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SepotColors.border),
                ),
                child: Text(
                  entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ikona stavu odeslané zprávy (⏱ / ✓ / ✓✓ / ✕). Sdílí ji bublina i
/// seznam konverzací, ať se stav zobrazuje konzistentně.
IconData _statusIcon(MessageStatus status) => switch (status) {
      MessageStatus.sending => Icons.schedule,
      MessageStatus.sent => Icons.done,
      MessageStatus.delivered => Icons.done_all,
      MessageStatus.read => Icons.done_all,
      MessageStatus.failed => Icons.error_outline,
    };
