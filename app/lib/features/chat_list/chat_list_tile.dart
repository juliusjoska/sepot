import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/widgets/avatar.dart';

/// Dlaždice konverzace v seznamu chatů. Sdílená hlavním i archivovaným
/// seznamem, aby se logika (fajfky, náhled, ztlumení) nerozešla.
class ChatListTile extends StatelessWidget {
  final Conversation conversation;
  final String contactName;
  final String myId;
  final bool isGroup;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ChatListTile({
    super.key,
    required this.conversation,
    required this.contactName,
    required this.myId,
    this.isGroup = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final lastMsg = conversation.lastMessage;
    final unread = conversation.unreadCount(myId);
    final muted = conversation.isMuted;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            isGroup
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SepotColors.surfaceVariant,
                      border: Border.all(color: SepotColors.border),
                    ),
                    child: const Icon(Icons.group_rounded,
                        color: SepotColors.ember, size: 24),
                  )
                : SepotAvatar(name: contactName),
            const SizedBox(width: 12),
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
                                unread > 0 ? FontWeight.w700 : FontWeight.w500,
                            color: SepotColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (muted)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.notifications_off,
                              size: 15, color: SepotColors.textMuted),
                        ),
                      if (lastMsg != null)
                        Text(
                          _formatTime(context, lastMsg.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread > 0 && !muted
                                ? SepotColors.ember
                                : SepotColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (lastMsg != null && lastMsg.isMine(myId))
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            switch (lastMsg.status) {
                              MessageStatus.sending => Icons.schedule,
                              MessageStatus.sent => Icons.done,
                              MessageStatus.delivered => Icons.done_all,
                              MessageStatus.read => Icons.done_all,
                              MessageStatus.failed => Icons.error_outline,
                            },
                            size: 16,
                            color: lastMsg.status == MessageStatus.failed
                                ? SepotColors.error
                                : lastMsg.status == MessageStatus.read
                                    ? SepotColors.mist
                                    : SepotColors.textMuted,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          _getLastMessageText(context.l10n, lastMsg),
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
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            // Ztlumené = šedý badge (počet ano, důraz ne)
                            color: muted
                                ? SepotColors.textMuted
                                : SepotColors.ember,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unread.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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

  static String _getLastMessageText(AppLocalizations l10n, Message? msg) {
    if (msg == null) return l10n.chatListNewConversation;
    if (msg.isDeleted) return l10n.chatMessageDeleted;
    if (msg.attachment?.isAudio == true) return l10n.chatVoiceMessagePreview;
    switch (msg.type) {
      case MessageType.text:
        return msg.content ?? '';
      case MessageType.image:
        return msg.content?.isNotEmpty == true
            ? l10n.chatListPhotoWithCaptionPreview(msg.content!)
            : l10n.chatPhotoPreview;
      case MessageType.file:
        return l10n.chatListFilePreview(msg.fileName ?? l10n.commonFile);
      case MessageType.readReceipt:
        return l10n.chatListReadReceiptPreview;
      default:
        return '';
    }
  }

  static String _formatTime(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return context.l10n.chatListTimeNow;
    if (diff.inHours < 1) return context.l10n.chatListTimeMinutes(diff.inMinutes);
    if (diff.inDays < 1) return DateFormat.Hm(locale).format(time);
    if (diff.inDays < 7) return DateFormat.E(locale).format(time);
    return DateFormat.Md(locale).format(time);
  }
}
