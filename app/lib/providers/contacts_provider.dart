import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Stav seznamu kontaktů
class ContactsNotifier extends AsyncNotifier<List<Contact>> {
  @override
  Future<List<Contact>> build() async {
    final storage = ref.read(storageProvider);
    return storage.loadContacts();
  }

  /// Přidej kontakt z veřejné identity
  Future<Contact> addContact(PublicIdentity identity, {bool verified = false}) async {
    final storage = ref.read(storageProvider);
    final contacts = await future;

    // Odkaz bez routingu (aid+da) = protistrana ho vytvořila dřív, než měla
    // hotovou registraci. Přidat takový kontakt = časovaná bomba: první
    // odeslání spadne na „nemá doručovací adresu". Odmítnout hned s
    // jasnou hláškou. (Nullable routing má smysl jen na interních příjmových
    // cestách — roster/_findOrCreateContact —, ne při ručním importu.)
    if (identity.accountId == null || identity.deliveryAddress == null) {
      throw const ContactLinkIncompleteError();
    }

    // Kontrola duplicity. Výjimka: žádost o zprávu od téhož klíče — ruční
    // přidání (QR, odkaz) je právě to přijetí, na které čekala.
    final existing =
        contacts.where((c) => c.publicIdentity.id == identity.id).firstOrNull;
    if (existing != null) {
      if (existing.accepted) throw const ContactAlreadyExistsError();
      await accept(existing.id,
          name: identity.displayName.isEmpty
              ? existing.displayName
              : identity.displayName);
      if (verified) existing.verified = true;
      await storage.saveContact(existing);
      return existing;
    }

    final contact = Contact.fromPublicIdentity(identity, verified: verified);
    await storage.saveContact(contact);

    state = AsyncData([...contacts, contact]);
    return contact;
  }

  /// Přijme žádost o zprávu pod jménem, které jí dal uživatel (jméno
  /// zvolené odesílatelem se tím nepřebírá automaticky).
  Future<void> accept(String contactId, {required String name}) async {
    final storage = ref.read(storageProvider);
    final contacts = await future;
    final contact = contacts.where((c) => c.id == contactId).firstOrNull;
    if (contact == null) return;
    contact
      ..displayName = name.trim()
      ..accepted = true;
    await storage.saveContact(contact);
    state = AsyncData([...contacts]);
  }

  /// Smaž kontakt
  Future<void> removeContact(String contactId) async {
    final storage = ref.read(storageProvider);
    await storage.deleteContact(contactId);

    final contacts = await future;
    state = AsyncData(contacts.where((c) => c.id != contactId).toList());
  }

  // Pozn.: dřívější verifyContact() (slepé přepnutí flagu) odstraněna —
  // ověření jde VÝHRADNĚ přes safety number (ContactVerifyScreen).

  /// Zablokuj / odblokuj kontakt. Blokovaný: příchozí zprávy se zahodí,
  /// odesílání je v UI zakázané.
  Future<void> setBlocked(String contactId, bool blocked) async {
    final storage = ref.read(storageProvider);
    final contacts = await future;
    final contact = contacts.where((c) => c.id == contactId).firstOrNull;
    if (contact == null) return;
    contact.blocked = blocked;
    await storage.saveContact(contact);
    state = AsyncData([...contacts]);
  }

  /// Najdi kontakt podle identity ID
  Contact? findByIdentityId(String identityId) {
    final contacts = state.valueOrNull;
    if (contacts == null) return null;
    return contacts.where((c) => c.publicIdentity.id == identityId).firstOrNull;
  }
}

final contactsProvider =
    AsyncNotifierProvider<ContactsNotifier, List<Contact>>(
  ContactsNotifier.new,
);
