import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Stav identity uživatele
class IdentityNotifier extends AsyncNotifier<LocalIdentity?> {
  @override
  Future<LocalIdentity?> build() async {
    final storage = ref.read(storageProvider);
    return storage.loadIdentity();
  }

  /// Vytvoř novou identitu
  Future<LocalIdentity> createIdentity(String displayName) async {
    final identity = await LocalIdentity.create(displayName);
    final storage = ref.read(storageProvider);
    await storage.saveIdentity(identity);
    state = AsyncData(identity);
    return identity;
  }

  /// Obnov identitu z 24slovné zálohovací fráze (recovery flow).
  ///
  /// Obnoví IDENTITU (stejný klíč → stejný SEP kód a safety number, kontakty
  /// tě dál poznají), ne historii zpráv. `LocalIdentity.recover` vyhodí
  /// [FormatException] při neplatné frázi. Po uložení messaging_provider
  /// sám spustí registraci u relaye (nová delivery adresa + bundle).
  Future<LocalIdentity> recoverIdentity(
      List<String> words, String displayName) async {
    final identity = await LocalIdentity.recover(
      mnemonicWords: words,
      displayName: displayName,
    );
    final storage = ref.read(storageProvider);
    await storage.saveIdentity(identity);
    await storage.saveSeedPhrase(identity.mnemonic);
    state = AsyncData(identity);
    return identity;
  }

  /// Znovu načti z úložiště
  Future<void> reload() async {
    final storage = ref.read(storageProvider);
    state = AsyncData(await storage.loadIdentity());
  }
}

final identityProvider =
    AsyncNotifierProvider<IdentityNotifier, LocalIdentity?>(
  IdentityNotifier.new,
);

/// Zkontroluj, zda je onboarding hotový
final isOnboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final storage = ref.read(storageProvider);
  return storage.isOnboardingComplete();
});

/// Zkontroluj, zda existuje PIN
final hasPinProvider = FutureProvider<bool>((ref) async {
  final storage = ref.read(storageProvider);
  return storage.hasPin();
});
