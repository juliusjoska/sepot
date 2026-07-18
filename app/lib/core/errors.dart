/// Typované chyby, které se zobrazují uživateli.
///
/// Service vrstva nemá přístup k lokalizaci (žádný BuildContext), proto
/// nesmí formulovat texty pro uživatele — vyhazuje tyhle typy a UI je
/// překládá přes `describeError` (core/l10n/error_messages.dart).
/// `toString()` je anglický technický popis pro logy, ne pro UI.
library;

sealed class SepotUserError implements Exception {
  const SepotUserError();
}

/// Trust root relaye nesedí s pinovaným — server nelze ověřit.
class TrustRootChangedError extends SepotUserError {
  const TrustRootChangedError();

  @override
  String toString() => 'relay trust root changed — refusing to communicate';
}

/// Relay nedostupný (typicky fetch sender certificate).
class RelayUnavailableError extends SepotUserError {
  const RelayUnavailableError();

  @override
  String toString() => 'relay unavailable';
}

/// Vlastní registrace na relay ještě nedoběhla — nemáme sender adresu.
/// Přechodný stav po čerstvé instalaci; registrace běží na pozadí.
class NotYetRegisteredError extends SepotUserError {
  const NotYetRegisteredError();

  @override
  String toString() => 'not registered on relay yet';
}

/// Odkaz/QR kontaktu je neúplný (chybí routing aid+da) — vygenerovaný
/// dřív, než měla protistrana dokončenou registraci na relay.
class ContactLinkIncompleteError extends SepotUserError {
  const ContactLinkIncompleteError();

  @override
  String toString() => 'contact link is missing routing (incomplete)';
}

/// Příloha přesahuje serverový limit.
class AttachmentTooLargeError extends SepotUserError {
  const AttachmentTooLargeError(this.maxBytes);

  final int maxBytes;

  int get maxMb => (maxBytes / (1024 * 1024)).round();

  @override
  String toString() => 'attachment too large (max $maxBytes bytes)';
}

/// Skupina bez jediného dalšího člena nedává smysl.
class GroupNeedsMemberError extends SepotUserError {
  const GroupNeedsMemberError();

  @override
  String toString() => 'group needs at least one member';
}

/// Překročen strop počtu členů skupiny.
class GroupTooLargeError extends SepotUserError {
  const GroupTooLargeError(this.maxMembers);

  final int maxMembers;

  @override
  String toString() => 'group exceeds $maxMembers members';
}

/// Člen skupiny nemá doručovací adresu (starý odkaz bez routingu).
class MemberNoDeliveryAddressError extends SepotUserError {
  const MemberNoDeliveryAddressError(this.displayName);

  final String displayName;

  @override
  String toString() => 'member "$displayName" has no delivery address';
}

/// Kontakt nemá doručovací adresu (starý odkaz bez routingu).
class ContactNoDeliveryAddressError extends SepotUserError {
  const ContactNoDeliveryAddressError();

  @override
  String toString() => 'contact has no delivery address';
}

/// Identity klíč z relaye nesedí s uloženým kontaktem — možný MITM.
class IdentityKeyMismatchError extends SepotUserError {
  const IdentityKeyMismatchError();

  @override
  String toString() => 'identity key mismatch — possible MITM, message not sent';
}

// === Obnova účtu (mnemonic) ===

/// Fráze má špatný počet slov.
class MnemonicWordCountError extends SepotUserError {
  const MnemonicWordCountError(this.count, this.expected);

  final int count;
  final int expected;

  @override
  String toString() => 'mnemonic has $count words, expected $expected';
}

/// Fráze neprošla validací BIP39 (neznámé slovo, checksum…).
class MnemonicInvalidError extends SepotUserError {
  const MnemonicInvalidError(this.detail);

  final String detail;

  @override
  String toString() => 'invalid mnemonic: $detail';
}

// === Zálohy historie (backup_service) ===

/// Soubor zálohy je poškozený (nejde přečíst/dešifrovat strukturu).
class BackupCorruptedError extends SepotUserError {
  const BackupCorruptedError();

  @override
  String toString() => 'corrupted backup file';
}

/// Soubor není záloha Šepotu.
class BackupUnknownFormatError extends SepotUserError {
  const BackupUnknownFormatError();

  @override
  String toString() => 'unknown backup format';
}

/// Záloha je šifrovaná klíčem jiné identity.
class BackupWrongIdentityError extends SepotUserError {
  const BackupWrongIdentityError();

  @override
  String toString() => 'backup belongs to a different identity';
}

// === Kontakty ===

/// Kontakt s tímto fingerprintem už existuje.
class ContactAlreadyExistsError extends SepotUserError {
  const ContactAlreadyExistsError();

  @override
  String toString() => 'contact already exists';
}

// === Nahlášení zneužití (report_service) ===

/// Hlášení bez popisu nemá co řešit.
class ReportEmptyDescriptionError extends SepotUserError {
  const ReportEmptyDescriptionError();

  @override
  String toString() => 'report has empty description';
}

/// Server hlášení je nedosažitelný.
class ReportConnectionError extends SepotUserError {
  const ReportConnectionError();

  @override
  String toString() => 'report endpoint unreachable';
}

/// Rate limit hlášení (429).
class ReportRateLimitedError extends SepotUserError {
  const ReportRateLimitedError();

  @override
  String toString() => 'report rate limited';
}

/// Server hlášení vrátil chybový kód.
class ReportServerError extends SepotUserError {
  const ReportServerError(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'report failed with status $statusCode';
}
