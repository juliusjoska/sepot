// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Šepot';

  @override
  String get settingsLanguage => 'App language';

  @override
  String get languageSystem => 'System default';

  @override
  String get commonUnknownContact => 'Unknown';

  @override
  String get verifyVerified => 'Verified';

  @override
  String get verifyUnverified => 'Not verified';

  @override
  String get chatMenuVerifyContact => 'Verify contact';

  @override
  String get chatDisappearingMessages => 'Disappearing messages';

  @override
  String get chatMenuUnblockContact => 'Unblock contact';

  @override
  String get chatMenuBlockContact => 'Block contact';

  @override
  String get reportAndBlock => 'Report and block';

  @override
  String errorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String get groupsYouLeftGroup => 'You\'re no longer in this group';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembers => 'Members';

  @override
  String get groupsRename => 'Rename group';

  @override
  String get groupsLeave => 'Leave group';

  @override
  String get groupsLeftBanner =>
      'You\'re no longer in this group. Your history stays, but new messages won\'t arrive.';

  @override
  String groupsMembersWithCount(int count) {
    return 'Members ($count)';
  }

  @override
  String get groupsYou => 'You';

  @override
  String get groupsFounder => 'Founder';

  @override
  String get groupsNameHint => 'Group name';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String groupsRenameFailed(String error) {
    return 'Rename failed: $error';
  }

  @override
  String get groupsLeaveConfirmTitle => 'Leave group?';

  @override
  String get groupsLeaveConfirmBody =>
      'Others will see that you\'ve left. Your history stays, but you won\'t receive new messages and someone will have to invite you back.';

  @override
  String get groupsLeaveAction => 'Leave';

  @override
  String groupsLeaveFailed(String error) {
    return 'Leaving failed: $error';
  }

  @override
  String get chatBlockedBanner =>
      'This contact is blocked. You won\'t receive their messages and can\'t message them.';

  @override
  String get chatUnblock => 'Unblock';

  @override
  String chatContactBlocked(String name) {
    return '$name is blocked';
  }

  @override
  String chatContactUnblocked(String name) {
    return '$name is unblocked';
  }

  @override
  String reportAndBlockBody(String name) {
    return 'We\'ll block $name and you\'ll stop receiving their messages. Then we\'ll show you a form to tell us what happened — we can\'t see message content, so without your description we won\'t know about it.';
  }

  @override
  String get chatEmptyEncrypted => 'Messages are end-to-end encrypted.';

  @override
  String get chatEmptyNoOneElse => 'No one else can read them.';

  @override
  String get commonToday => 'Today';

  @override
  String get commonYesterday => 'Yesterday';

  @override
  String get chatMessageHint => 'Type a message…';

  @override
  String get chatDiscardRecording => 'Discard';

  @override
  String get chatRecording => 'Recording…';

  @override
  String get chatMicPermissionMissing => 'Microphone permission missing';

  @override
  String chatRecordingFailed(String error) {
    return 'Recording failed: $error';
  }

  @override
  String chatVoiceSendFailed(String error) {
    return 'Sending voice message failed: $error';
  }

  @override
  String get chatDeletedMessagePreview => 'Deleted message';

  @override
  String get chatVoiceMessagePreview => '🎤 Voice message';

  @override
  String get chatPhotoPreview => '📷 Photo';

  @override
  String get chatAttachmentPreview => '📎 Attachment';

  @override
  String get chatEditingMessage => 'Editing message';

  @override
  String get chatReply => 'Reply';

  @override
  String get chatActionReply => 'Reply';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonEdit => 'Edit';

  @override
  String get chatDeleteForMe => 'Delete for me';

  @override
  String get chatDeleteForEveryone => 'Delete for everyone';

  @override
  String get commonOff => 'Off';

  @override
  String get chatDisappearing30s => '30 seconds';

  @override
  String get chatDisappearing5m => '5 minutes';

  @override
  String get chatDisappearing1h => '1 hour';

  @override
  String get chatDisappearing1d => '1 day';

  @override
  String get chatDisappearing1w => '1 week';

  @override
  String get chatDisappearingDescription =>
      'New messages will be deleted for both you and the other person once the time is up.';

  @override
  String get chatDisappearingDisabled => 'Disappearing messages turned off';

  @override
  String chatDisappearingEnabled(String duration) {
    return 'New messages will disappear after: $duration';
  }

  @override
  String get attachmentGallery => 'Photo from gallery';

  @override
  String get attachmentTakePhoto => 'Take photo';

  @override
  String get attachmentDocument => 'Document';

  @override
  String attachmentTooLarge(int maxMb) {
    return 'File is too large (max $maxMb MB)';
  }

  @override
  String attachmentPickFailed(String error) {
    return 'Picking attachment failed: $error';
  }

  @override
  String attachmentSendFailed(String error) {
    return 'Sending attachment failed: $error';
  }

  @override
  String chatSendFailed(String error) {
    return 'Sending failed: $error';
  }

  @override
  String get chatMessageDeleted => 'Message deleted';

  @override
  String get chatEdited => 'edited';

  @override
  String get errorTrustRootChanged =>
      'The relay\'s trust root has changed! Refusing to communicate.';

  @override
  String get errorRelayUnavailable => 'Relay unavailable (sender certificate)';

  @override
  String get errorNotYetRegistered =>
      'Šepot is still connecting to the relay — try sending again in a moment.';

  @override
  String get errorContactLinkIncomplete =>
      'This link is incomplete — the other person created it before connecting. Ask them for a new sepot:// link.';

  @override
  String errorAttachmentTooLarge(int maxMb) {
    return 'Attachment is too large (max $maxMb MB)';
  }

  @override
  String get errorGroupNeedsMember => 'A group needs at least 1 member';

  @override
  String errorGroupMaxMembers(int maxMembers) {
    return 'A group can have at most $maxMembers members';
  }

  @override
  String errorMemberNoDeliveryAddress(String displayName) {
    return '$displayName has no delivery address — ask them for a new link';
  }

  @override
  String get errorContactNoDeliveryAddress =>
      'This contact has no delivery address — ask them for a new sepot:// link';

  @override
  String get errorIdentityKeyMismatch =>
      'The identity key from the relay does NOT match this contact — possible MITM! Message not sent.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get settingsChangePinTitle => 'Change PIN';

  @override
  String get settingsChangePinSubtitle => '6-digit PIN for unlocking';

  @override
  String get settingsAutoLockTitle => 'Auto-lock';

  @override
  String get settingsAutoLock5min => 'After 5 minutes';

  @override
  String get settingsDecoyPinTitle => 'Duress PIN';

  @override
  String get settingsDecoyPinSetSubtitle => 'Set — opens an empty app';

  @override
  String get settingsDecoyPinUnsetSubtitle =>
      'A second PIN that opens an empty app';

  @override
  String get settingsSectionNotifications => 'Notifications';

  @override
  String get settingsSectionConnection => 'Connection';

  @override
  String get settingsSectionPrivacy => 'Privacy';

  @override
  String get settingsReadReceiptsTitle => 'Read receipts';

  @override
  String get settingsReadReceiptsSubtitle =>
      'Let others see when you\'ve read their messages (off by default)';

  @override
  String get settingsScreenSecurityTitle => 'Screen security';

  @override
  String get settingsScreenSecuritySubtitle =>
      'Block screenshots and hide content in the app switcher';

  @override
  String get settingsSectionBackup => 'Key backup';

  @override
  String get settingsSeedPhraseTitle => 'Recovery phrase';

  @override
  String get settingsSeedPhraseSubtitle => '24 words to restore your identity';

  @override
  String get settingsBackupExportTitle => 'Back up history';

  @override
  String get settingsBackupExportSubtitle =>
      'Encrypted file with your contacts and messages';

  @override
  String get settingsBackupImportTitle => 'Restore from backup';

  @override
  String get settingsBackupImportSubtitle =>
      'Load a backup (only with your identity)';

  @override
  String get settingsSectionSafety => 'Safety';

  @override
  String get settingsReportAbuseTitle => 'Report abuse';

  @override
  String get settingsReportAbuseSubtitle =>
      'Harassment, fraud, child endangerment';

  @override
  String get settingsChildSafetyTitle => 'Child safety standards';

  @override
  String get settingsChildSafetySubtitle => 'How we respond to child abuse';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get commonAppName => 'Šepot';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsLicenseTitle => 'License';

  @override
  String get settingsLicenseSubtitle => 'AGPL-3.0';

  @override
  String get settingsPrivacyPolicyTitle => 'Privacy policy';

  @override
  String get settingsPrivacyPolicySubtitle =>
      'What we know about you (and what we don\'t)';

  @override
  String get settingsTermsTitle => 'Terms of use';

  @override
  String get settingsTermsSubtitle => 'sepot.cz/podminky';

  @override
  String get settingsDataDeletionTitle => 'Data deletion';

  @override
  String get settingsDataDeletionSubtitle => 'How to request erasure';

  @override
  String get settingsDeleteAllDataButton => 'Delete all data';

  @override
  String settingsLicenseBody(String supportEmail) {
    return 'Šepot is distributed under the GNU Affero General Public License version 3 (AGPL-3.0). It uses the libsignal library, also AGPL-3.0.\n\nTo get the source code corresponding to this version, write to $supportEmail and we\'ll send it to you.';
  }

  @override
  String get commonClose => 'Close';

  @override
  String get settingsIdCopied => 'ID copied';

  @override
  String settingsFingerprint(String fingerprint) {
    return 'Fingerprint: $fingerprint';
  }

  @override
  String get backupShareSubject => 'Šepot — encrypted backup';

  @override
  String backupExportFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String backupRestoredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restored $count conversations from the backup',
      one: 'Restored 1 conversation from the backup',
    );
    return '$_temp0';
  }

  @override
  String backupImportFailed(String error) {
    return 'Restoring from backup failed: $error';
  }

  @override
  String get settingsDecoyPinExplain =>
      'Entering this PIN opens the app empty — without your contacts and messages. It must be different from your regular PIN.';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSet => 'Set';

  @override
  String get settingsDecoyPinEnabled => 'Duress PIN set';

  @override
  String get settingsDecoyPinConflict =>
      'The duress PIN must differ from your regular PIN';

  @override
  String get settingsDecoyPinDisabled => 'Duress PIN removed';

  @override
  String get settingsSeedPhraseNotFound => 'Recovery phrase not found';

  @override
  String get settingsSeedPhraseWarning =>
      'These words are the only backup of your identity. Don\'t show them to anyone!';

  @override
  String settingsSeedWordChip(int index, String word) {
    return '$index. $word';
  }

  @override
  String get settingsAboutTagline => 'Šepot — Private Messenger';

  @override
  String get settingsAboutBody =>
      'An open-source end-to-end encrypted messenger.\n\nCryptography:\n• X25519 (key exchange)\n• XChaCha20-Poly1305 (encryption)\n• Ed25519 (signatures)\n\n© 2026 ajtak.it';

  @override
  String get settingsDeleteAccountTitle => 'Delete account and all data?';

  @override
  String get settingsDeleteAccountBody =>
      'This action cannot be undone. All messages, contacts and keys will be deleted from this device and the account will be deregistered from the server. If you don\'t have your recovery phrase, you\'ll lose your identity.';

  @override
  String get settingsDeleteAccountServerOffline =>
      'The server is unreachable right now — data on this device has been deleted, but the server registration remains. Write to podpora@sepot.cz and we\'ll delete the rest.';

  @override
  String get settingsDeleteAllConfirm => 'Delete everything';

  @override
  String groupsCreateFailed(String error) {
    return 'Couldn\'t create the group: $error';
  }

  @override
  String get groupsNewGroupTitle => 'New group';

  @override
  String get groupsCreateAction => 'Create';

  @override
  String groupsMembersCounter(int selectedCount, int maxMembers) {
    return 'Members ($selectedCount/$maxMembers)';
  }

  @override
  String get groupsEmptyContactsHint =>
      'Add some contacts first — a group is made of people you can already message.';

  @override
  String get groupsMemberMissingAddress =>
      'Missing delivery address — ask them for a new link';

  @override
  String attachmentSizeBytes(int bytes) {
    return '$bytes B';
  }

  @override
  String attachmentSizeKb(String kilobytes) {
    return '$kilobytes KB';
  }

  @override
  String attachmentSizeMb(String megabytes) {
    return '$megabytes MB';
  }

  @override
  String get attachmentDownloadFailedTapToRetry =>
      'Download failed — tap to retry';

  @override
  String get attachmentDownloadFailed => 'Download failed';

  @override
  String get attachmentDownloading => 'Downloading…';

  @override
  String get attachmentSharedFileFallbackName => 'file';

  @override
  String attachmentOpenFailed(String error) {
    return 'Opening attachment failed: $error';
  }

  @override
  String get commonFile => 'File';

  @override
  String get chatListNewConversation => 'New conversation';

  @override
  String chatListPhotoWithCaptionPreview(String caption) {
    return '📷 $caption';
  }

  @override
  String chatListFilePreview(String fileName) {
    return '📎 $fileName';
  }

  @override
  String get chatListReadReceiptPreview => 'Read';

  @override
  String get chatListTimeNow => 'now';

  @override
  String chatListTimeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get qrScanTitle => 'Scan QR code';

  @override
  String get qrScanInstruction => 'Point the camera at your contact\'s QR code';

  @override
  String get qrScanHint => 'The QR code contains the contact\'s public key';

  @override
  String get qrNewContactTitle => 'New contact';

  @override
  String qrContactAdded(String name) {
    return '$name added';
  }

  @override
  String get commonAdd => 'Add';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Šepot';

  @override
  String get onboardingWelcomeSubtitle =>
      'A private messenger with end-to-end encryption.\nNo phone number. No email.\nJust your keys.';

  @override
  String get onboardingStart => 'Get started';

  @override
  String get onboardingRestoreExisting =>
      'I already have an account — restore from recovery phrase';

  @override
  String get onboardingEncryptionTitle => 'Your messages, your keys';

  @override
  String get onboardingFeatureSignalTitle => 'Signal protocol';

  @override
  String get onboardingFeatureSignalSubtitle =>
      'X3DH + Double Ratchet, forward secrecy';

  @override
  String get onboardingFeaturePqTitle => 'Post-quantum protection';

  @override
  String get onboardingFeaturePqSubtitle =>
      'Kyber (PQXDH) from the first message';

  @override
  String get onboardingFeatureLocalKeysTitle => 'Keys stay on your device';

  @override
  String get onboardingFeatureLocalKeysSubtitle => 'No server ever sees them';

  @override
  String get onboardingFeatureDisappearingSubtitle => 'Deleted automatically';

  @override
  String get commonContinue => 'Continue';

  @override
  String get onboardingIdentityTitle => 'Create your identity';

  @override
  String get onboardingIdentitySubtitle =>
      'No email or phone. Just a name and cryptographic keys.';

  @override
  String get onboardingDisplayNameLabel => 'Display name';

  @override
  String get onboardingDisplayNameHint => 'e.g. John';

  @override
  String onboardingSeedPhraseWarning(int count) {
    return 'Write down these $count words. They\'re the only backup of your keys!';
  }

  @override
  String get onboardingSeedSavedConfirm =>
      'I confirm I\'ve stored the phrase safely';

  @override
  String get onboardingGenerateKeys => 'Generate keys';

  @override
  String get verifyMismatchTitle => 'Numbers DO NOT match';

  @override
  String verifyMatchBody(String contactName) {
    return 'The keys match. $contactName is a verified contact.';
  }

  @override
  String get verifyMismatchBody =>
      'The safety numbers don\'t match. Someone may be intercepting your connection (MITM), or you\'re scanning a different contact\'s code. Do NOT send sensitive messages and verify each other again over a different channel.';

  @override
  String get commonUnderstood => 'Got it';

  @override
  String get verifyManualConfirmTitle => 'Mark as verified?';

  @override
  String get verifyManualConfirmBody =>
      'Confirm only if you\'ve compared the digits with the other person over another trusted channel (in person, on a call…) and they match.';

  @override
  String get verifyManualConfirmAction => 'They match — verify';

  @override
  String get verifyTitle => 'Verify contact';

  @override
  String get verifyContactVerifiedBanner => 'This contact is verified';

  @override
  String verifyIntro(String contactName) {
    return 'Compare this number with $contactName. If it matches, no one is eavesdropping on your encryption. The fastest way is to scan each other\'s QR codes.';
  }

  @override
  String get verifyScanButton => 'Scan their code';

  @override
  String get verifyManualButton => 'Digits match — mark manually';

  @override
  String get verifyUnverifyButton => 'Clear verification';

  @override
  String get verifyScanScreenTitle => 'Scan verification QR';

  @override
  String get reportTitle => 'Report';

  @override
  String get reportSubmitted => 'Report submitted';

  @override
  String get reportSubmittedChildSafety =>
      'We handle these reports with priority. If a child is in immediate danger, call your local police or a child helpline.';

  @override
  String get reportSubmittedThanks =>
      'Thanks. We\'ll look into it as soon as possible.';

  @override
  String get commonDone => 'Done';

  @override
  String get reportPanelE2eNotice =>
      'Messages are end-to-end encrypted, so we can\'t see their content even now. Please describe in your own words what happened. Don\'t paste message content or links to it here — we\'re not allowed to store it and we don\'t need it to assess the report.';

  @override
  String get reportPanelCsamWarning =>
      'Do NOT send us material depicting child abuse. Possessing it is a crime — for us too — and we don\'t need it for a report. It should go directly to the police or a dedicated child sexual abuse reporting hotline. Just tell us what happened — we\'ll block the account and pass the matter on.';

  @override
  String get reportPanelIpNotice =>
      'Reports aren\'t sent through the relay — they go to our web server, which will see your IP address when you submit.';

  @override
  String get reportCategoryHeading => 'What the report is about';

  @override
  String get reportDescriptionHeading => 'What happened';

  @override
  String get reportAttachContactId => 'Attach the reported contact\'s ID';

  @override
  String reportAttachContactIdNamed(String contactName) {
    return 'Attach $contactName\'s ID';
  }

  @override
  String get reportReplyToHeading => 'How to reach you (optional)';

  @override
  String get reportReplyToHint => 'email, in case we need to follow up';

  @override
  String get reportSubmitButton => 'Submit report';

  @override
  String get contactsTitle => 'Contacts';

  @override
  String get contactsAddContact => 'Add contact';

  @override
  String get contactsSearchHint => 'Search contacts…';

  @override
  String get contactsEmpty => 'No contacts yet';

  @override
  String get contactsNoResults => 'No results';

  @override
  String get contactsShareCardTitle => 'Share your Šepot ID';

  @override
  String get contactsShareCardSubtitle => 'Show your QR code or send a link';

  @override
  String get contactsAddDialogPrompt => 'Paste the contact\'s share string:';

  @override
  String get contactsShareStringHint => 'Paste share string…';

  @override
  String get contactsInvalidShareString => 'Invalid share string';

  @override
  String contactsAdded(String name) {
    return 'Contact $name added';
  }

  @override
  String get verifyContactSubtitle => 'Compare safety numbers';

  @override
  String get contactsDeleteContact => 'Delete contact';

  @override
  String get pinConfirmTitle => 'Confirm PIN';

  @override
  String get pinSetupTitle => 'Set up a PIN';

  @override
  String get pinConfirmSubtitle => 'Enter the PIN again to confirm';

  @override
  String get pinSetupSubtitle => '6-digit PIN to unlock the app';

  @override
  String get pinSetupFailed => 'Setting the PIN failed. Try again.';

  @override
  String get pinMismatchRetry => 'PINs don\'t match. Try again.';

  @override
  String get pinChangeCurrentTitle => 'Enter your current PIN';

  @override
  String get pinChangeCurrentSubtitle =>
      'We\'ll verify it by unlocking your key';

  @override
  String get pinChangeNewTitle => 'Enter a new PIN';

  @override
  String get pinChangeNewSubtitle => '6 digits';

  @override
  String get pinChangeConfirmTitle => 'Confirm the new PIN';

  @override
  String get pinChangeConfirmSubtitle => 'Enter it one more time';

  @override
  String get pinWrong => 'Wrong PIN.';

  @override
  String get pinChangeMustDiffer =>
      'The new PIN must differ from the current one.';

  @override
  String get pinMismatch => 'PINs don\'t match.';

  @override
  String get pinDecoyConflict =>
      'This PIN already belongs to duress mode. Choose a different one.';

  @override
  String get pinChangeFailed => 'Changing the PIN failed. Try again.';

  @override
  String get pinChanged => 'PIN changed';

  @override
  String get errorCryptoInitTitle => 'The encryption core failed to start';

  @override
  String get errorStartupTitle => 'Šepot failed to start';

  @override
  String get errorScreenNotRenderedTitle => 'This screen failed to render';

  @override
  String get errorStartupBody =>
      'Something went wrong right at startup. Please send me this text (long-press and copy) — it will help me find the bug.';

  @override
  String get errorContactFooter => 'sepot.cz · get in touch';

  @override
  String get pinUnlockTitle => 'Unlock Šepot';

  @override
  String get pinEnterPin => 'Enter PIN';

  @override
  String get pinUnlockWithBiometrics => 'Unlock with biometrics';

  @override
  String get pinWrong2 => 'Wrong PIN';

  @override
  String get pinUnlockError => 'Unlock error';

  @override
  String get pushTitle => 'Push notifications';

  @override
  String get pushModeOffDesc => 'Messages arrive only after you open the app.';

  @override
  String get pushModeUp => 'UnifiedPush (recommended)';

  @override
  String get pushModeUpDesc =>
      'De-Googled — needs the ntfy app (F-Droid/Play).';

  @override
  String get pushModeFcm => 'Google (FCM)';

  @override
  String get pushModeFcmDesc =>
      'Reliable without an extra app. The device push token goes to Google; message content never does.';

  @override
  String pushSetupFailed(String error) {
    return 'Setting up push failed: $error';
  }

  @override
  String get pushHintOff =>
      'Messages arrive only when you open Šepot — wake-ups aren’t set up.';

  @override
  String get pushHintFailed =>
      'Wake-ups aren’t working; you’ll see messages only after opening Šepot.';

  @override
  String get pushRegistrationFailed =>
      'Wake-ups aren’t arriving — the distributor refused registration. Try turning push off and on again.';

  @override
  String get pushNoDistributorTitle => 'No distributor';

  @override
  String get pushNoDistributorBody =>
      'For de-Googled notifications, install a UnifiedPush distributor such as ntfy (F-Droid or Play). Then turn push on again.';

  @override
  String get commonOk => 'OK';

  @override
  String get pushPickDistributorTitle => 'Choose a distributor';

  @override
  String pushSubtitleUnifiedPush(String distributor) {
    return 'UnifiedPush · $distributor';
  }

  @override
  String get pushNoDistributorFallback => 'no distributor';

  @override
  String get pushSubtitleFcm => 'Google (FCM) — fast, opt-in';

  @override
  String get restoreErrorNameRequired => 'Enter a display name.';

  @override
  String restoreErrorWordCount(int wordCount, int requiredWords) {
    String _temp0 = intl.Intl.pluralLogic(
      wordCount,
      locale: localeName,
      other: 'The phrase has $wordCount words, $requiredWords are needed.',
      one: 'The phrase has 1 word, $requiredWords are needed.',
    );
    return '$_temp0';
  }

  @override
  String get restoreErrorInvalidPhrase =>
      'The phrase isn\'t valid — check the words and their order.';

  @override
  String restoreErrorFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get restoreTitle => 'Restore account';

  @override
  String get restoreHeading => 'Enter your recovery phrase';

  @override
  String restoreIntro(int wordCount) {
    return '$wordCount words from the backup created when you set up your account. This restores your identity (same SEP code — your contacts will still recognize you).';
  }

  @override
  String get restoreHistoryWarning =>
      'Message history won\'t be restored — it\'s stored only on the original device.';

  @override
  String get restorePhraseHint => 'word1 word2 word3 …';

  @override
  String restoreWordCountHelper(int wordCount, int requiredWords) {
    return '$wordCount / $requiredWords words';
  }

  @override
  String chatListArchivedCount(int count) {
    return 'Archived ($count)';
  }

  @override
  String get chatListEmptyTitle => 'No conversations yet';

  @override
  String get chatListEmptySubtitle => 'Add a contact and start whispering!';

  @override
  String get chatListUnmute => 'Unmute';

  @override
  String get chatListMute => 'Mute';

  @override
  String get chatListArchive => 'Archive';

  @override
  String get qrShareTitle => 'My Šepot ID';

  @override
  String get qrShareConnectingTitle => 'Connecting to the relay…';

  @override
  String get qrShareConnectingBody =>
      'Your QR code and link will appear once Šepot connects for the first time. Just a moment — it only takes a few seconds.';

  @override
  String get qrIdentityNotFound => 'Identity not found';

  @override
  String get commonCopiedToClipboard => 'Copied to clipboard';

  @override
  String qrShareInviteMessage(String shareString) {
    return 'Add me on Šepot!\n\n$shareString';
  }

  @override
  String get commonShare => 'Share';

  @override
  String get qrShareInfo =>
      'Your contact scans your QR code or pastes the share string into the app.';

  @override
  String get reportCategoryChildSafety => 'Child endangerment';

  @override
  String get reportCategoryChildSafetyHint =>
      'Describe the situation in your own words. Don\'t paste message content or links to material.';

  @override
  String get reportCategoryHarassment => 'Harassment or threats';

  @override
  String get reportCategoryHarassmentHint =>
      'Someone is intimidating, threatening or harassing you.';

  @override
  String get reportCategorySpam => 'Spam';

  @override
  String get reportCategorySpamHint => 'Unsolicited messages, bulk sending.';

  @override
  String get reportCategoryFraud => 'Fraud';

  @override
  String get reportCategoryFraudHint =>
      'An attempt to trick you out of money, keys or personal data.';

  @override
  String get reportCategoryOther => 'Other';

  @override
  String get reportCategoryOtherHint => 'Something else we should know about.';

  @override
  String get reportErrorEmptyDescription => 'Please describe what happened.';

  @override
  String reportErrorConnection(String supportEmail) {
    return 'Couldn\'t reach the server. Try again, or write to $supportEmail.';
  }

  @override
  String reportErrorRateLimited(String supportEmail) {
    return 'Too many reports came from your network. Try again in an hour, or write to $supportEmail.';
  }

  @override
  String reportErrorServer(int statusCode, String supportEmail) {
    return 'Submission failed (code $statusCode). Please write to $supportEmail.';
  }

  @override
  String get settingsAutoLockNever => 'Never';

  @override
  String get settingsAutoLock1min => 'After 1 minute';

  @override
  String get settingsAutoLock15min => 'After 15 minutes';

  @override
  String torToggleFailed(String error) {
    return 'Toggling Tor failed: $error';
  }

  @override
  String get torConnectionTitle => 'Connect via Tor';

  @override
  String get torDialogBody =>
      'Traffic to the server will go through the Tor network (hides your IP address). Requires the Orbot app installed and running with an active SOCKS proxy on port 9050.\n\nWithout Orbot running, messages won\'t be sent or received. The connection is usually slower.';

  @override
  String get commonTurnOn => 'Turn on';

  @override
  String get torSubtitleOff =>
      'Direct encrypted connection (WSS). Turn on to hide your IP via Tor.';

  @override
  String get torStatusConnected => 'Connected via Tor (.onion).';

  @override
  String get torStatusConnecting => 'Connecting via Tor… (is Orbot running?)';

  @override
  String get torStatusWaiting => 'Via Tor — waiting for Orbot (SOCKS 9050).';

  @override
  String get biometricsPinRequiredFirst =>
      'Set a PIN first — biometrics only complement it.';

  @override
  String get biometricsStorageLocked =>
      'Storage is locked — unlock the app with your PIN.';

  @override
  String get biometricsNotAvailable => 'This device has no biometrics set up.';

  @override
  String get biometricsEnrollPromptReason =>
      'Confirm enabling biometric unlock';

  @override
  String biometricsSetupFailed(String error) {
    return 'Couldn\'t set up biometrics: $error';
  }

  @override
  String get biometricsTileTitle => 'Biometrics';

  @override
  String get biometricsTileSubtitle =>
      'Unlock with fingerprint / face (PIN stays as a backup)';

  @override
  String get backupErrorCorruptedFile => 'Corrupted backup file';

  @override
  String get backupErrorUnknownFormat => 'Unrecognized backup format';

  @override
  String get backupErrorWrongIdentity =>
      'Can\'t decrypt this backup — does it belong to a different identity?';

  @override
  String attachmentSharedImageFilename(String ext) {
    return 'sepot-image.$ext';
  }

  @override
  String get attachmentDecryptFailed => 'Couldn\'t decrypt the attachment';

  @override
  String get pushActionOpen => 'Open';

  @override
  String get pushChannelMessagesName => 'Messages';

  @override
  String get pushChannelMessagesDescription =>
      'Alerts about new messages (no content)';

  @override
  String pushNewMessageFrom(String senderName) {
    return 'New message from $senderName';
  }

  @override
  String get pushNewMessages => 'You have new messages';

  @override
  String get archiveTitle => 'Archived';

  @override
  String get archiveEmpty => 'No archived conversations';

  @override
  String get archiveUnarchive => 'Unarchive';

  @override
  String restoreErrorMnemonicWordCount(int count, int expected) {
    return 'The phrase has $count words, expected $expected';
  }

  @override
  String restoreErrorInvalidMnemonic(String message) {
    return 'Invalid phrase: $message';
  }

  @override
  String get contactsErrorAlreadyExists => 'Contact already exists';

  @override
  String get commonAppTagline => 'Private messenger';

  @override
  String get commonE2eBadgeCompact => 'E2E';

  @override
  String get commonE2eBadgeFull => 'End-to-end encrypted';

  @override
  String get photoPreviewCaptionHint => 'Add a caption…';

  @override
  String get photoPreviewDraw => 'Draw';

  @override
  String get photoPreviewAddText => 'Add text';

  @override
  String get photoPreviewRotate => 'Rotate';

  @override
  String get photoPreviewUndo => 'Undo';

  @override
  String get photoPreviewSend => 'Send';

  @override
  String get photoPreviewTextDialogTitle => 'Text on photo';

  @override
  String get photoPreviewRemoveText => 'Remove';

  @override
  String get photoPreviewDecodeFailed => 'Couldn\'t load the photo';
}
