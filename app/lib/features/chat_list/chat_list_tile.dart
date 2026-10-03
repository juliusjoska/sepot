import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/calls/call_log_text.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/widgets/avatar.dart';
import 'package:sepot/widgets/message_status_icon.dart';

/// Dlaždice konverzace v seznamu chatů. Sdílená hlavním i archivovaným
/// seznamem, aby se logika (fajfky, náhled, ztlumení) nerozešla.
class ChatListTile extends StatelessWidget {
  final Conversation conversation;
  final String contactName;
  final String myId;
  final bool isGroup;
  final bool verified;

  /// Jméno autora poslední zprávy ve skupině (null = 1:1 nebo neznámý).
  final String? lastAuthor;

  /// Nalezená zpráva při hledání — ukáže se místo poslední.
  final Message? highlight;

  /// Kdo právě píše (už složený text „píše…“ / „Alice píše…“), null = nikdo.
  final String? typingLabel;

  /// Rozepsaná zpráva v tomhle chatu — v náhledu má přednost před poslední
  /// zprávou, jinak by se na ni snadno zapomnělo.
  final String? draft;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ChatListTile({
    super.key,
    required this.conversation,
    required this.contactName,
    required this.myId,
    this.isGroup = false,
    this.verified = false,
    this.lastAuthor,
    this.highlight,
    this.typingLabel,
    this.draft,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final lastMsg = highlight ?? conversation.lastMessage;
    final unread = conversation.unreadCount(myId);
    final muted = conversation.isMuted;
    final mine = lastMsg != null && lastMsg.isMine(myId);
    final preview = previewOf(context.l10n, lastMsg);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            conversation.contactId == AppConstants.notesConversationId
                ? const NotesAvatar(size: 54)
                : isGroup
                ? SepotGroupAvatar(seed: conversation.contactId, size: 54)
                : SepotAvatar(
                    name: contactName,
                    seed: conversation.contactId,
                    size: 54,
                    verified: verified,
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contactName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                unread > 0 ? FontWeight.w700 : FontWeight.w600,
                            color: SepotColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.pinned)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.push_pin_rounded,
                              size: 14, color: SepotColors.textMuted),
                        ),
                      if (lastMsg != null)
                        Text(
                          formatListTime(context, lastMsg.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                unread > 0 ? FontWeight.w600 : FontWeight.w400,
                            color: unread > 0 && !muted
                                ? SepotColors.ember
                                : SepotColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (typingLabel != null)
                        Expanded(
                          child: Text(
                            typingLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: SepotColors.ember,
                            ),
                          ),
                        )
                      else if (draft != null)
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '${context.l10n.chatListDraft}: ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: SepotColors.ember,
                                ),
                              ),
                              TextSpan(text: draft!.replaceAll('\n', ' ')),
                            ]),
                            style: const TextStyle(
                              fontSize: 14,
                              color: SepotColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        )
                      else ...[
                        if (mine && !lastMsg.isDeleted) ...[
                          MessageStatusIcon(status: lastMsg.status),
                          const SizedBox(width: 6),
                        ],
                        if (preview.icon != null) ...[
                          Icon(preview.icon,
                              size: 15, color: SepotColors.textSecondary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              if (isGroup && !mine && lastAuthor != null)
                                TextSpan(
                                  text: '$lastAuthor: ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: SepotColors.textEmphasis,
                                  ),
                                ),
                              TextSpan(text: preview.text),
                            ]),
                            style: TextStyle(
                              fontSize: 14,
                              color: unread > 0
                                  ? SepotColors.textPrimary
                                  : SepotColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                      if (muted)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.notifications_off_outlined,
                              size: 16, color: SepotColors.textMuted),
                        ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // Ztlumené = šedý badge (počet ano, důraz ne)
                            color: muted
                                ? SepotColors.surfaceVariant
                                : SepotColors.ember,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : unread.toString(),
                            style: TextStyle(
                              color: muted
                                  ? SepotColors.textSecondary
                                  : SepotColors.emberInk,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Náhled zprávy: ikona typu (fotka, soubor, hlas) + text. Ikona místo
  /// emoji — emoji se na každém systému kreslí jinak a v náhledu ruší.
  static ({IconData? icon, String text}) previewOf(
      AppLocalizations l10n, Message? msg) {
    if (msg == null) return (icon: null, text: l10n.chatListNewConversation);
    if (msg.isDeleted) {
      return (icon: Icons.block_rounded, text: l10n.chatMessageDeleted);
    }
    if (msg.attachment?.isAudio == true) {
      return (icon: Icons.mic_none_rounded, text: l10n.chatVoiceMessagePreview);
    }
    if (msg.poll != null) {
      return (icon: Icons.bar_chart_rounded, text: msg.poll!.question);
    }
    final call = msg.callLog;
    if (call != null) {
      final label = callLogLabel(l10n, call);
      return (icon: label.icon, text: label.text);
    }
    return switch (msg.type) {
      MessageType.text => (icon: null, text: msg.content ?? ''),
      MessageType.image => (
          icon: Icons.photo_outlined,
          text: msg.content?.isNotEmpty == true
              ? msg.content!
              : l10n.chatPhotoPreview,
        ),
      MessageType.file => (
          icon: Icons.attach_file_rounded,
          text: msg.fileName ?? l10n.commonFile,
        ),
      MessageType.readReceipt => (
          icon: null,
          text: l10n.chatListReadReceiptPreview,
        ),
      _ => (icon: null, text: ''),
    };
  }

  static String formatListTime(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final diff = now.difference(time);
    // Záporný rozdíl = hodiny odesílatele jdou napřed; „teď“ by lhalo.
    if (!diff.isNegative && diff.inMinutes < 1) {
      return context.l10n.chatListTimeNow;
    }
    if (!diff.isNegative && diff.inHours < 1) {
      return context.l10n.chatListTimeMinutes(diff.inMinutes);
    }
    final sameDay = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;
    if (sameDay) return DateFormat.Hm(locale).format(time);
    if (diff.inDays < 7) return DateFormat.E(locale).format(time);
    return DateFormat.Md(locale).format(time);
  }
}
