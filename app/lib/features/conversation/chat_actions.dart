/// Akce nad konverzací, kontaktem a skupinou sdílené obrazovkou chatu
/// a profily — ať se chování (potvrzení, hlášky, pořadí kroků) nerozejde.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

String contactLabel(BuildContext context, Contact contact) =>
    contact.displayName.isEmpty
        ? context.l10n.commonUnknownContact
        : contact.displayName;

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Popisky voleb mizících zpráv (sekundy → text); -1 = vypnuto.
List<(int, String)> disappearingOptions(BuildContext context) => [
      (-1, context.l10n.commonOff),
      (30, context.l10n.chatDisappearing30s),
      (300, context.l10n.chatDisappearing5m),
      (3600, context.l10n.chatDisappearing1h),
      (86400, context.l10n.chatDisappearing1d),
      (604800, context.l10n.chatDisappearing1w),
    ];

/// Text aktuálního nastavení mizících zpráv („1 týden“ / „Vypnuto“).
String disappearingLabel(BuildContext context, int? seconds) {
  final options = disappearingOptions(context);
  return options.where((o) => o.$1 == (seconds ?? -1)).firstOrNull?.$2 ??
      context.l10n.commonOff;
}

/// Per-konverzace TTL mizících zpráv. Platí pro NOVĚ odeslané zprávy
/// (TTL cestuje E2E kanálem, protistrana ho respektuje). Poctivá
/// hranice: je to dohoda klientů, ne DRM — screenshot nezastavíš.
Future<void> configureDisappearing(
    BuildContext context, WidgetRef ref, String convId) async {
  final storage = ref.read(storageProvider);
  final conv = await storage.loadConversation(convId) ??
      Conversation(contactId: convId);
  if (!context.mounted) return;

  final options = disappearingOptions(context);
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
            style:
                const TextStyle(fontSize: 13, color: SepotColors.textSecondary),
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
  ref.invalidate(conversationProvider(convId));
  ref.invalidate(conversationsProvider);
  if (context.mounted) {
    _snack(
        context,
        picked == -1
            ? context.l10n.chatDisappearingDisabled
            : context.l10n.chatDisappearingEnabled(
                options.firstWhere((o) => o.$1 == picked).$2));
  }
}

Future<void> setContactBlocked(
    BuildContext context, WidgetRef ref, Contact contact, bool blocked) async {
  await ref.read(contactsProvider.notifier).setBlocked(contact.id, blocked);
  if (!context.mounted) return;
  final jmeno = contactLabel(context, contact);
  _snack(
      context,
      blocked
          ? context.l10n.chatContactBlocked(jmeno)
          : context.l10n.chatContactUnblocked(jmeno));
}

/// Nahlásit a zablokovat: nejdřív blok (okamžitá ochrana), pak formulář.
Future<void> reportAndBlock(
    BuildContext context, WidgetRef ref, Contact contact) async {
  final jmeno = contactLabel(context, contact);
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
  if (ok != true || !context.mounted) return;

  await setContactBlocked(context, ref, contact, true);
  if (!context.mounted) return;
  final q = <String, String>{'contact': contact.id, 'name': contact.displayName};
  context.push(Uri(path: '/report', queryParameters: q).toString());
}

Future<void> renameGroup(
    BuildContext context, WidgetRef ref, Group group) async {
  final controller = TextEditingController(text: group.name);
  final novy = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.groupsRename),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 64,
        decoration: InputDecoration(hintText: context.l10n.groupsNameHint),
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
  controller.dispose();
  if (novy == null || novy.isEmpty || novy == group.name) return;
  try {
    await ref.read(groupsProvider.notifier).rename(group, novy);
  } catch (e) {
    if (context.mounted) {
      _snack(context,
          context.l10n.groupsRenameFailed(describeError(context.l10n, e)));
    }
  }
}

/// Odebere člena skupiny (jen správce) po potvrzení.
Future<void> removeGroupMember(BuildContext context, WidgetRef ref,
    Group group, String fingerprint, String name) async {
  final potvrzeno = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.groupsRemoveMemberConfirmTitle(name)),
      content: Text(
        context.l10n.groupsRemoveMemberConfirmBody,
        style: const TextStyle(color: SepotColors.textSecondary),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.commonCancel)),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: SepotColors.error),
          child: Text(context.l10n.groupsRemoveAction),
        ),
      ],
    ),
  );
  if (potvrzeno != true || !context.mounted) return;
  await _adminAction(context,
      () => ref.read(groupsProvider.notifier).removeMember(group, fingerprint));
}

/// Udělí / odebere roli správce (jen správce).
Future<void> setGroupAdmin(BuildContext context, WidgetRef ref, Group group,
        String fingerprint, bool admin) =>
    _adminAction(
        context,
        () => ref
            .read(groupsProvider.notifier)
            .setAdmin(group, fingerprint, admin));

Future<void> _adminAction(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      _snack(context,
          context.l10n.groupsAdminActionFailed(describeError(context.l10n, e)));
    }
  }
}

/// Vrací true, když uživatel skupinu opravdu opustil.
Future<bool> leaveGroup(
    BuildContext context, WidgetRef ref, Group group) async {
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
          style: ElevatedButton.styleFrom(backgroundColor: SepotColors.error),
          child: Text(context.l10n.groupsLeaveAction),
        ),
      ],
    ),
  );
  if (potvrzeno != true) return false;
  try {
    await ref.read(groupsProvider.notifier).leave(group);
    return true;
  } catch (e) {
    if (context.mounted) {
      _snack(context,
          context.l10n.groupsLeaveFailed(describeError(context.l10n, e)));
    }
    return false;
  }
}
