import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Rozepsané zprávy (contactId → text). Jeden záznam v šifrovaném nastavení,
/// ne pole konverzace: konverzace se ukládá celá jako load → změna → save
/// a zápis konceptu při psaní by mohl přepsat zprávu, která mezitím dorazila.
class DraftsNotifier extends AsyncNotifier<Map<String, String>> {
  static const key = 'drafts';

  @override
  Future<Map<String, String>> build() async {
    final raw =
        await ref.read(storageProvider).getSetting<Map<String, dynamic>>(key);
    return {
      for (final e in (raw ?? const {}).entries)
        if (e.value is String) e.key: e.value as String,
    };
  }

  Future<void> set(String contactId, String text) async {
    // Počkat na načtení — jinak by zápis před dokončením build() smazal
    // koncepty ostatních chatů.
    final current = {...await future};
    final trimmed = text.trim();
    if ((current[contactId] ?? '') == trimmed) return;
    if (trimmed.isEmpty) {
      current.remove(contactId);
    } else {
      current[contactId] = trimmed;
    }
    state = AsyncData(current);
    await ref.read(storageProvider).setSetting(key, current);
  }
}

final draftsProvider =
    AsyncNotifierProvider<DraftsNotifier, Map<String, String>>(
        DraftsNotifier.new);
