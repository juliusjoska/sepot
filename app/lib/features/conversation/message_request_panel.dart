/// Žádost o zprávu: místo psacího pole u odesílatele, kterého jsem si
/// nepřidal. Jméno i fotku si zvolil sám, takže dokud ho nepřijmu, nesmí
/// vypadat jako můj kontakt a nesmí ode mě dostat odpověď omylem.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/safety/lookalike_names.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/conversation/chat_actions.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/providers/contacts_provider.dart';

class MessageRequestPanel extends ConsumerWidget {
  const MessageRequestPanel({super.key, required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final contacts = ref.watch(contactsProvider).valueOrNull ?? const [];
    final claimed = contact.displayName.isEmpty
        ? l10n.commonUnknownContact
        : contact.displayName;
    final lookalike =
        lookalikeContact(contact.displayName, contacts, exceptId: contact.id);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: SepotColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: lookalike != null ? SepotColors.error : SepotColors.warning,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  lookalike != null
                      ? Icons.gpp_maybe_rounded
                      : Icons.person_search_rounded,
                  size: 20,
                  color: lookalike != null
                      ? SepotColors.error
                      : SepotColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.requestTitle,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.requestBody(claimed),
              style: const TextStyle(
                  fontSize: 13, color: SepotColors.textSecondary),
            ),
            if (lookalike != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.requestLookalikeWarning(lookalike.displayName),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SepotColors.error),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      setContactBlocked(context, ref, contact, true),
                  child: Text(l10n.chatMenuBlockContact,
                      style: const TextStyle(color: SepotColors.error)),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => acceptMessageRequest(context, ref, contact),
                  child: Text(l10n.requestAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Přijetí = uživatel kontakt pojmenuje sám. Jméno, které se plete
/// s jiným přijatým kontaktem, neprojde: dvě „Mámy“ v seznamu by
/// podvrh jen schovaly.
Future<void> acceptMessageRequest(
    BuildContext context, WidgetRef ref, Contact contact) async {
  final contacts = ref.read(contactsProvider).valueOrNull ?? const [];
  final controller = TextEditingController(
    text: lookalikeContact(contact.displayName, contacts,
                exceptId: contact.id) ==
            null
        ? contact.displayName
        : '',
  );
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => _AcceptDialog(
      controller: controller,
      isTaken: (n) =>
          lookalikeContact(n, contacts, exceptId: contact.id) != null,
    ),
  );
  controller.dispose();
  if (name == null) return;
  await ref.read(contactsProvider.notifier).accept(contact.id, name: name);
}

class _AcceptDialog extends StatefulWidget {
  const _AcceptDialog({required this.controller, required this.isTaken});

  final TextEditingController controller;
  final bool Function(String name) isTaken;

  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  String? _error;

  void _submit() {
    final l10n = context.l10n;
    final name = widget.controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.requestNameEmpty);
      return;
    }
    if (widget.isTaken(name)) {
      setState(() => _error = l10n.requestNameTaken);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.requestAcceptTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.requestAcceptBody, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            autofocus: true,
            maxLength: MessagingService.maxDisplayNameLength,
            decoration: InputDecoration(
              labelText: l10n.requestAcceptNameLabel,
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.requestAccept)),
      ],
    );
  }
}
