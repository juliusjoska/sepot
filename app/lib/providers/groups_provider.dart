import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Stav skupin. Zápisové operace jdou přes
/// MessagingService (fanout členům), tady se jen drží seznam pro UI.
class GroupsNotifier extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() async {
    return ref.read(storageProvider).loadGroups();
  }

  Future<Group> createGroup(String name, List<Contact> members) async {
    final group =
        await ref.read(messagingServiceProvider).createGroup(name, members);
    await _refresh();
    return group;
  }

  Future<void> addMembers(Group group, List<Contact> added) async {
    await ref.read(messagingServiceProvider).addGroupMembers(group, added);
    await _refresh();
  }

  Future<void> rename(Group group, String newName) async {
    await ref.read(messagingServiceProvider).renameGroup(group, newName);
    await _refresh();
  }

  Future<void> leave(Group group) async {
    await ref.read(messagingServiceProvider).leaveGroup(group);
    await _refresh();
  }

  Future<void> _refresh() async {
    state = AsyncData(await ref.read(storageProvider).loadGroups());
    ref.invalidate(conversationsProvider);
  }
}

final groupsProvider = AsyncNotifierProvider<GroupsNotifier, List<Group>>(
  GroupsNotifier.new,
);

/// Jedna skupina podle id (null = id nepatří skupině → 1:1 konverzace).
final groupProvider = FutureProvider.family<Group?, String>((ref, id) async {
  // Závislost na seznamu — invalidace groupsProvider obnoví i family.
  ref.watch(groupsProvider);
  return ref.read(storageProvider).loadGroup(id);
});
