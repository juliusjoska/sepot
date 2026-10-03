import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/widgets/avatar.dart';

/// Založení skupiny: jméno + výběr členů. S `addToGroupId`
/// jde o přidání lidí do existující skupiny — bez jména, stávající členové
/// v nabídce nejsou a strop počítá s nimi.
///
/// Vybrat jde jen kontakty s doručovací adresou (routing) — bez ní jim
/// fanout nemá kam doručit. Kontakty bez routingu jsou v seznamu vidět,
/// ale zašedlé s vysvětlením.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key, this.addToGroupId});

  final String? addToGroupId;

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _selected = <String>{};
  var _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool _hasRouting(Contact c) =>
      c.publicIdentity.accountId != null &&
      c.publicIdentity.deliveryAddress != null;

  Future<void> _submit(List<Contact> contacts, Group? existing) async {
    final name = _nameController.text.trim();
    if ((existing == null && name.isEmpty) || _selected.isEmpty || _creating) {
      return;
    }

    setState(() => _creating = true);
    final members = contacts.where((c) => _selected.contains(c.id)).toList();
    final groups = ref.read(groupsProvider.notifier);
    try {
      if (existing != null) {
        await groups.addMembers(existing, members);
        if (mounted) context.pop();
      } else {
        final group = await groups.createGroup(name, members);
        if (mounted) context.pushReplacement('/conversation/${group.id}');
      }
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) {
        final detail = describeError(context.l10n, e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing != null
                ? context.l10n.groupsAddMembersFailed(detail)
                : context.l10n.groupsCreateFailed(detail)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.addToGroupId != null;
    final existing = adding
        ? ref.watch(groupProvider(widget.addToGroupId!)).valueOrNull
        : null;
    final contactsAsync = ref.watch(contactsProvider);
    final contacts = (contactsAsync.valueOrNull ?? [])
        .where((c) => !c.blocked)
        .where((c) => existing == null || !existing.memberIds.contains(c.id))
        .toList();
    // Já jsem v memberIds existující skupiny; nová skupina mě přidá sama.
    final capacity = Group.maxMembers - (existing?.memberIds.length ?? 1);
    final canSubmit =
        (adding ? existing != null : _nameController.text.trim().isNotEmpty) &&
            _selected.isNotEmpty &&
            !_creating;

    return Scaffold(
      appBar: AppBar(
        title: Text(adding
            ? context.l10n.groupsAddMembers
            : context.l10n.groupsNewGroupTitle),
        actions: [
          TextButton(
            onPressed: canSubmit ? () => _submit(contacts, existing) : null,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SepotColors.ember),
                  )
                : Text(adding
                    ? context.l10n.groupsAddMembersAction
                    : context.l10n.groupsCreateAction),
          ),
        ],
      ),
      body: Column(
        children: [
          if (adding)
            const SizedBox(height: 16)
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _nameController,
                maxLength: 64,
                decoration: InputDecoration(
                  labelText: context.l10n.groupsNameHint,
                  counterText: '',
                  prefixIcon: const Icon(Icons.group_rounded,
                      color: SepotColors.textMuted),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  context.l10n.groupsMembersCounter(_selected.length, capacity),
                  style: const TextStyle(
                      color: SepotColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: contacts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        adding
                            ? context.l10n.groupsNoContactsToAdd
                            : context.l10n.groupsEmptyContactsHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: SepotColors.textSecondary),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final c = contacts[index];
                      final routable = _hasRouting(c);
                      final checked = _selected.contains(c.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: routable
                            ? (v) => setState(() {
                                  if (v == true) {
                                    if (_selected.length < capacity) {
                                      _selected.add(c.id);
                                    }
                                  } else {
                                    _selected.remove(c.id);
                                  }
                                })
                            : null,
                        secondary: SepotAvatar(
                            name: c.displayName, seed: c.id, size: 40),
                        title: Text(
                          c.displayName,
                          style: TextStyle(
                            color: routable
                                ? SepotColors.textPrimary
                                : SepotColors.textMuted,
                          ),
                        ),
                        subtitle: routable
                            ? null
                            : Text(
                                context.l10n.groupsMemberMissingAddress,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: SepotColors.textMuted),
                              ),
                        activeColor: SepotColors.ember,
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
