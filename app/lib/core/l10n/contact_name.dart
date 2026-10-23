import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/contact.dart';

/// Jméno kontaktu pro UI. U žádosti o zprávu s viditelnou značkou, že si
/// jméno zvolil odesílatel sám: „Máma (neznámý)“ se nesmí na pohled
/// shodovat s přijatou „Mámou“ v seznamu, hlavičce ani ve skupině.
String contactName(AppLocalizations l10n, Contact contact) {
  if (contact.displayName.isEmpty) return l10n.commonUnknownContact;
  return contact.accepted
      ? contact.displayName
      : l10n.contactRequestName(contact.displayName);
}
