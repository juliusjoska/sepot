import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/conversation/chat_actions.dart';
import 'package:sepot/features/profile/profile_widgets.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/widgets/avatar.dart';

/// Profil kontaktu: kdo to je, jestli je ověřený, co jsme si poslali,
/// ve kterých skupinách jsme spolu a nastavení konverzace.
class ContactProfileScreen extends ConsumerWidget {
  const ContactProfileScreen({
    super.key,
    required this.contactId,
    this.fromChat = false,
  });

  final String contactId;

  /// Otevřeno z hlavičky chatu — „Zpráva“ se jen vrátí, nic nepřidá
  /// do zásobníku obrazovek.
  final bool fromChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final contact = (ref.watch(contactsProvider).valueOrNull ?? const [])
        .where((c) => c.publicIdentity.id == contactId)
        .firstOrNull;
    final conv = ref.watch(conversationProvider(contactId)).valueOrNull;
    final groups = (ref.watch(groupsProvider).valueOrNull ?? const [])
        .where((g) => !g.left && g.memberIds.contains(contactId))
        .toList();

    if (contact == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.commonUnknownContact)),
      );
    }

    final name = contactLabel(context, contact);
    final muted = conv?.isMuted ?? false;

    void openChat({bool search = false}) {
      if (fromChat) {
        Navigator.of(context).pop(search ? ProfileResult.openSearch : null);
      } else {
        context.push('/conversation/$contactId${search ? '?search=1' : ''}');
      }
    }

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ProfileHero(
            avatar: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: contact.verified
                      ? SepotColors.sage
                      : SepotColors.border,
                  width: 2,
                ),
              ),
              child: SepotAvatar(
                name: name,
                seed: contactId,
                size: 108,
                verified: contact.verified,
              ),
            ),
            title: name,
            lines: [
              SelectableText(
                contact.publicIdentity.fingerprint.short,
                style: const TextStyle(
                  fontFamily: kFontMono,
                  fontSize: 13,
                  color: SepotColors.textSecondary,
                ),
              ),
              _VerificationLine(
                verified: contact.verified,
                onVerify: () => context.push('/verify/$contactId'),
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
                      icon: Icons.chat_bubble_outline_rounded,
                      label: l10n.profileMessage,
                      accent: true,
                      onTap: contact.blocked ? null : openChat,
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
                              .setMuted(contactId, !muted)
                              .then((_) => ref
                                  .invalidate(conversationProvider(contactId))),
                    ),
                    const SizedBox(width: 8),
                    ProfileAction(
                      icon: Icons.timer_outlined,
                      label: l10n.profileDisappearing,
                      onTap: () =>
                          configureDisappearing(context, ref, contactId),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (conv != null) ...[
                  SharedMediaCard(messages: conv.messages),
                  const SizedBox(height: 14),
                ],
                if (groups.isNotEmpty) ...[
                  ProfileCard(
                    title: l10n.profileCommonGroups,
                    trailing: '${groups.length}',
                    children: [
                      for (final g in groups)
                        ProfileRow(
                          leading: SepotGroupAvatar(seed: g.id, size: 38),
                          label: g.name,
                          subtitle: l10n.groupsMemberCount(g.memberIds.length),
                          onTap: () => context.push('/conversation/${g.id}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                ProfileCard(
                  children: [
                    ProfileRow(
                      label: l10n.chatDisappearingMessages,
                      value:
                          disappearingLabel(context, conv?.disappearAfterSeconds),
                      onTap: () =>
                          configureDisappearing(context, ref, contactId),
                    ),
                    ProfileRow(
                      label: l10n.profileSafetyNumber,
                      subtitle: contact.verified
                          ? l10n.verifyVerified
                          : l10n.profileSafetyNumberHint,
                      onTap: () => context.push('/verify/$contactId'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ProfileCard(
                  children: [
                    ProfileRow(
                      label: contact.blocked
                          ? l10n.chatMenuUnblockContact
                          : l10n.chatMenuBlockContact,
                      danger: !contact.blocked,
                      onTap: () => setContactBlocked(
                          context, ref, contact, !contact.blocked),
                    ),
                    if (!contact.blocked)
                      ProfileRow(
                        label: l10n.reportAndBlock,
                        danger: true,
                        onTap: () => reportAndBlock(context, ref, contact),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationLine extends StatelessWidget {
  const _VerificationLine({required this.verified, required this.onVerify});

  final bool verified;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    if (verified) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 16, color: SepotColors.sage),
          const SizedBox(width: 6),
          Text(context.l10n.profileVerifiedInPerson,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SepotColors.sage)),
        ],
      );
    }
    return TextButton.icon(
      onPressed: onVerify,
      icon: const Icon(Icons.shield_outlined, size: 16),
      label: Text(context.l10n.profileVerifyNow),
    );
  }
}
