import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/widgets/avatar.dart';

/// Obrazovka kontaktů
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: SepotTheme.largeTitleBarHeight,
        title: Text(context.l10n.contactsTitle, style: SepotTheme.largeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => context.push('/create-group'),
            tooltip: context.l10n.groupsNewGroupTitle,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push('/qr-scan'),
            tooltip: context.l10n.qrScanTitle,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => _showAddContactDialog(context),
            tooltip: context.l10n.contactsAddContact,
          ),
        ],
      ),
      body: Column(
        children: [
          // Vyhledávání
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.contactsSearchHint,
                prefixIcon: const Icon(Icons.search, color: SepotColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: SepotColors.border),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          // Sdílet vlastní QR
          _buildShareCard(context),
          const Divider(height: 1),
          ListTile(
            leading: const NotesAvatar(size: 40),
            title: Text(context.l10n.notesTitle,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(context.l10n.notesSubtitle,
                style: const TextStyle(
                    fontSize: 12, color: SepotColors.textSecondary)),
            onTap: () async {
              await ref.read(conversationsProvider.notifier).ensureNotes();
              if (context.mounted) {
                context.push(
                    '/conversation/${AppConstants.notesConversationId}');
              }
            },
          ),
          const Divider(height: 1),
          // Seznam kontaktů
          Expanded(
            child: contactsAsync.when(
              data: (contacts) {
                // Žádosti o zprávu kontakty nejsou — žijí jen v seznamu chatů.
                final filtered = contacts.where((c) {
                  if (!c.accepted) return false;
                  if (_searchQuery.isEmpty) return true;
                  return c.displayName.toLowerCase().contains(_searchQuery) ||
                      c.sepotId.toLowerCase().contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 48,
                          color: SepotColors.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? context.l10n.contactsEmpty
                              : context.l10n.contactsNoResults,
                          style: const TextStyle(
                            fontFamily: kFontSans,
                            fontSize: 16,
                            color: SepotColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final contact = filtered[index];
                    final displayName = contact.displayName.isEmpty
                        ? context.l10n.commonUnknownContact
                        : contact.displayName;
                    final id = contact.publicIdentity.id;
                    return ListTile(
                      leading: GestureDetector(
                        onTap: () => context.push('/contact/$id'),
                        child: SepotAvatar(
                          name: displayName,
                          seed: id,
                          verified: contact.verified,
                        ),
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            contact.sepotId,
                            style: SepotTheme.cryptoText.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: context.l10n.chatOpenProfile,
                        icon: const Icon(Icons.person_outline_rounded,
                            color: SepotColors.textSecondary),
                        onPressed: () => context.push('/contact/$id'),
                      ),
                      onTap: () => context.push('/conversation/$id'),
                      onLongPress: () =>
                          _showContactOptions(context, contact.id),
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
        ],
      ),
    );
  }

  Widget _buildShareCard(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/qr-share'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: SepotColors.surfaceVariant,
              child: Icon(
                Icons.qr_code_rounded,
                color: SepotColors.ember,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.contactsShareCardTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: SepotColors.textPrimary,
                    ),
                  ),
                  Text(
                    context.l10n.contactsShareCardSubtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SepotColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: SepotColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _showAddContactDialog(BuildContext context) {
    final idController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.contactsAddContact),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.contactsAddDialogPrompt,
              style: const TextStyle(
                  fontSize: 14, color: SepotColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: idController,
              decoration: InputDecoration(
                hintText: context.l10n.contactsShareStringHint,
                prefixIcon: const Icon(Icons.link),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final shareString = idController.text.trim();
              if (shareString.isEmpty) return;

              final identity = PublicIdentity.fromShareString(shareString);
              if (identity == null) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(context.l10n.contactsInvalidShareString)),
                  );
                }
                return;
              }

              try {
                await ref
                    .read(contactsProvider.notifier)
                    .addContact(identity);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.contactsAdded(
                          identity.displayName.isEmpty
                              ? context.l10n.commonUnknownContact
                              : identity.displayName)),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(describeError(context.l10n, e))),
                  );
                }
              }
            },
            child: Text(context.l10n.commonAdd),
          ),
        ],
      ),
    );
  }

  void _showContactOptions(BuildContext context, String contactId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SepotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.verified_outlined, color: SepotColors.ember),
              title: Text(context.l10n.chatMenuVerifyContact),
              subtitle: Text(context.l10n.verifyContactSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                // Skutečné ověření = safety number, ne slepé přepnutí flagu
                context.push('/verify/$contactId');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: SepotColors.error),
              title: Text(context.l10n.contactsDeleteContact,
                  style: const TextStyle(color: SepotColors.error)),
              onTap: () {
                ref.read(contactsProvider.notifier).removeContact(contactId);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
