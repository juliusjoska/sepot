import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/storage/secure_storage.dart' show DecoyPinConflict;
import 'package:sepot/l10n/generated/app_localizations.dart';

/// Přeloží chybu na větu pro uživatele.
///
/// Typované chyby (`SepotUserError`, `DecoyPinConflict`) mají vlastní
/// lokalizované hlášky; cokoli neznámého spadne do obecné hlášky
/// s technickým popisem — radši ošklivá pravda než němé selhání.
String describeError(AppLocalizations l10n, Object error) => switch (error) {
      TrustRootChangedError() => l10n.errorTrustRootChanged,
      RelayUnavailableError() => l10n.errorRelayUnavailable,
      NotYetRegisteredError() => l10n.errorNotYetRegistered,
      ContactLinkIncompleteError() => l10n.errorContactLinkIncomplete,
      AttachmentTooLargeError(:final maxMb) =>
        l10n.errorAttachmentTooLarge(maxMb),
      GroupNeedsMemberError() => l10n.errorGroupNeedsMember,
      GroupTooLargeError(:final maxMembers) =>
        l10n.errorGroupMaxMembers(maxMembers),
      MemberNoDeliveryAddressError(:final displayName) =>
        l10n.errorMemberNoDeliveryAddress(displayName),
      ContactNoDeliveryAddressError() => l10n.errorContactNoDeliveryAddress,
      IdentityKeyMismatchError() => l10n.errorIdentityKeyMismatch,
      MnemonicWordCountError(:final count, :final expected) =>
        l10n.restoreErrorMnemonicWordCount(count, expected),
      MnemonicInvalidError(:final detail) =>
        l10n.restoreErrorInvalidMnemonic(detail),
      BackupCorruptedError() => l10n.backupErrorCorruptedFile,
      BackupUnknownFormatError() => l10n.backupErrorUnknownFormat,
      BackupWrongIdentityError() => l10n.backupErrorWrongIdentity,
      ContactAlreadyExistsError() => l10n.contactsErrorAlreadyExists,
      ReportEmptyDescriptionError() => l10n.reportErrorEmptyDescription,
      ReportConnectionError() =>
        l10n.reportErrorConnection(AppConstants.supportEmail),
      ReportRateLimitedError() =>
        l10n.reportErrorRateLimited(AppConstants.supportEmail),
      ReportServerError(:final statusCode) =>
        l10n.reportErrorServer(statusCode, AppConstants.supportEmail),
      DecoyPinConflict() => l10n.settingsDecoyPinConflict,
      _ => l10n.errorGeneric(error.toString()),
    };
