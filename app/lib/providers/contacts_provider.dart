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

    // Kontrola duplicity
    if (contacts.any((c) => c.publicIdentity.id == identity.id)) {
      throw const ContactAlreadyExistsError();
    }

    final contact = Contact.fromPublicIdentity(identity, verified: verified);
    await storage.saveContact(contact);

    state = AsyncData([...contacts, contact]);
    return contact;
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
