import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/l10n/contact_name.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/core/utils/text_fold.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/widgets/avatar.dart';

/// Cíl přeposlání — kontakt nebo skupina, kam jde psát.
class _Target {
  const _Target(this.id, this.name,
      {this.isGroup = false, this.verified = false, this.isNotes = false});

  final String id;
  final String name;
  final bool isGroup;
  final bool isNotes;
  final bool verified;
}

/// Výběr chatu a přeposlání zprávy. Zdrojový chat v nabídce není —
/// přeposlat zprávu tam, kde už je, nikdo nechce.
Future<void> forwardMessage(
  BuildContext context,
  WidgetRef ref,
  Message message, {
  required String fromId,
}) async {
  final contacts = ref.read(contactsProvider).valueOrNull ?? const [];
  final groups = ref.read(groupsProvider).valueOrNull ?? const [];
  final targets = [
    for (final g in groups)
      if (!g.left && g.id != fromId) _Target(g.id, g.name, isGroup: true),
    for (final c in contacts)
      if (!c.blocked && c.accepted && c.id != fromId)
        _Target(c.id, contactName(context.l10n, c), verified: c.verified),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  // Poznámky nahoře: přeposlat si něco „na později“ je nejčastější případ.
  if (!ConversationsNotifier.isNotes(fromId)) {
    targets.insert(
        0,
        _Target(AppConstants.notesConversationId,
            context.l10n.notesTitle,
            isNotes: true));
  }

  final target = await showModalBottomSheet<_Target>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SepotColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ForwardPicker(targets: targets),
  );
  if (target == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await ref
        .read(conversationsProvider.notifier)
        .forwardMessage(message, target.id);
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.forwardDone(target.name))));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.forwardFailed(describeError(l10n, e)))));
  }
}

class _ForwardPicker extends StatefulWidget {
  const _ForwardPicker({required this.targets});

  final List<_Target> targets;

  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final q = fold(_query);
    final shown = q.isEmpty
        ? widget.targets
        : widget.targets
            .where((t) => fold(t.name).contains(q))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.forwardTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SepotColors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: l10n.forwardSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      l10n.forwardEmpty,
                      style: const TextStyle(color: SepotColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final t = shown[i];
                      return ListTile(
                        leading: t.isNotes
                            ? const NotesAvatar(size: 40)
                            : t.isGroup
                            ? SepotGroupAvatar(seed: t.id, size: 40)
                            : SepotAvatar(
                                name: t.name,
                                seed: t.id,
                                size: 40,
                                verified: t.verified,
                              ),
                        title: Text(t.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: SepotColors.textPrimary)),
                        onTap: () => Navigator.pop(context, t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
