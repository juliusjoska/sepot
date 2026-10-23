import 'package:sepot/models/avatar_ref.dart';
import 'package:sepot/models/identity.dart';

/// Kontakt — osoba, se kterou můžeme chatovat
///
/// Odpovídá Rust: Contact
class Contact {
  String displayName;
  final PublicIdentity publicIdentity;
  final DateTime addedAt;
  bool verified;
  String? notes;

  /// Blokovaný kontakt: příchozí zprávy se zahodí (ACKnou, ale neuloží ani
  /// nezobrazí) a odesílání je v UI zablokované.
  bool blocked;

  /// Profilová fotka, kterou kontakt sdílí (null = iniciály).
  AvatarRef? avatar;

  /// Přijatý kontakt. False = žádost o zprávu: napsal mi někdo, koho jsem
  /// si sám nepřidal (nebo jsem ho potkal jen ve skupině), takže jméno
  /// i fotku si zvolil on. Dokud ho nepřijmu, appka ho značí jako
  /// neznámého, neukazuje jeho fotku, nezvoní jeho hovory a nedává mu
  /// vědět, že čtu nebo píšu.
  bool accepted;

  Contact({
    required this.displayName,
    required this.publicIdentity,
    required this.addedAt,
    this.verified = false,
    this.notes,
    this.blocked = false,
    this.avatar,
    this.accepted = true,
  });

  /// ID kontaktu = fingerprint identity klíče (identita = klíč).
  ///
  /// Dřív náhodné UUID — vznikly tím DVĚ klíčové soustavy (konverzace se
  /// ukládaly pod UUID, UI ale routovalo fingerprintem), takže konverzace
  /// otevřená z kontaktů neuměla odeslat zprávu a chat list nenašel jméno.
  /// Bez datové migrace (žádná produkční data; testovací zařízení se
  /// re-párují — stejný precedens jako S9).
  String get id => publicIdentity.id;

  /// Vytvoř nový kontakt z veřejné identity
  factory Contact.fromPublicIdentity(
    PublicIdentity identity, {
    bool verified = false,
    bool accepted = true,
  }) {
    return Contact(
      displayName: identity.displayName,
      publicIdentity: identity,
      addedAt: DateTime.now(),
      verified: verified,
      accepted: accepted,
    );
  }

  /// Šepot ID kontaktu
  String get sepotId => publicIdentity.sepotId;

  /// Otisk kontaktu (plné Crockford base32 zobrazení)
  String get fingerprint => publicIdentity.fingerprint.display;

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'publicIdentity': publicIdentity.toJson(),
        'addedAt': addedAt.toIso8601String(),
        'verified': verified,
        'notes': notes,
        'blocked': blocked,
        'avatar': avatar?.toJson(),
        'accepted': accepted,
      };

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      displayName: json['displayName'] as String,
      publicIdentity: PublicIdentity.fromJson(
        json['publicIdentity'] as Map<String, dynamic>,
      ),
      addedAt: DateTime.parse(json['addedAt'] as String),
      verified: json['verified'] as bool? ?? false,
      notes: json['notes'] as String?,
      blocked: json['blocked'] as bool? ?? false,
      avatar: AvatarRef.fromJson(json['avatar']),
      // Kontakty z doby před žádostmi o zprávu uživatel už léta používá —
      // zpětně je vydávat za neznámé by jen naučilo varování odklikávat.
      accepted: json['accepted'] as bool? ?? true,
    );
  }
}
