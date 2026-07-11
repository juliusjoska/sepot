// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Šepot';

  @override
  String get settingsLanguage => 'App-Sprache';

  @override
  String get languageSystem => 'Systemstandard';

  @override
  String get commonUnknownContact => 'Unbekannt';

  @override
  String get verifyVerified => 'Verifiziert';

  @override
  String get verifyUnverified => 'Nicht verifiziert';

  @override
  String get chatMenuVerifyContact => 'Kontakt verifizieren';

  @override
  String get chatDisappearingMessages => 'Verschwindende Nachrichten';

  @override
  String get chatMenuUnblockContact => 'Blockierung aufheben';

  @override
  String get chatMenuBlockContact => 'Kontakt blockieren';

  @override
  String get reportAndBlock => 'Melden und blockieren';

  @override
  String errorGeneric(String error) {
    return 'Fehler: $error';
  }

  @override
  String get groupsYouLeftGroup => 'Du bist nicht mehr in der Gruppe';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '1 Mitglied',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembers => 'Mitglieder';

  @override
  String get groupsRename => 'Gruppe umbenennen';

  @override
  String get groupsLeave => 'Gruppe verlassen';

  @override
  String get groupsLeftBanner =>
      'Du bist nicht mehr in der Gruppe. Der Verlauf bleibt, neue Nachrichten kommen nicht mehr an.';

  @override
  String groupsMembersWithCount(int count) {
    return 'Mitglieder ($count)';
  }

  @override
  String get groupsYou => 'Du';

  @override
  String get groupsFounder => 'Hat die Gruppe gegründet';

  @override
  String get groupsNameHint => 'Gruppenname';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String groupsRenameFailed(String error) {
    return 'Umbenennen fehlgeschlagen: $error';
  }

  @override
  String get groupsLeaveConfirmTitle => 'Gruppe verlassen?';

  @override
  String get groupsLeaveConfirmBody =>
      'Die anderen sehen, dass du nicht mehr in der Gruppe bist. Der Verlauf bleibt dir erhalten, aber du bekommst keine neuen Nachrichten mehr und musst neu eingeladen werden.';

  @override
  String get groupsLeaveAction => 'Verlassen';

  @override
  String groupsLeaveFailed(String error) {
    return 'Verlassen fehlgeschlagen: $error';
  }

  @override
  String get chatBlockedBanner =>
      'Der Kontakt ist blockiert. Du bekommst keine Nachrichten von ihm und kannst ihm nicht schreiben.';

  @override
  String get chatUnblock => 'Blockierung aufheben';

  @override
  String chatContactBlocked(String name) {
    return 'Kontakt $name wurde blockiert';
  }

  @override
  String chatContactUnblocked(String name) {
    return 'Blockierung von $name aufgehoben';
  }

  @override
  String reportAndBlockBody(String name) {
    return 'Wir blockieren den Kontakt $name und du bekommst keine Nachrichten mehr von ihm. Danach zeigen wir dir ein Formular, mit dem du uns mitteilst, was passiert ist — wir sehen den Inhalt der Nachrichten nicht und erfahren ohne deine Beschreibung nichts davon.';
  }

  @override
  String get chatEmptyEncrypted =>
      'Nachrichten sind Ende-zu-Ende-verschlüsselt.';

  @override
  String get chatEmptyNoOneElse => 'Niemand sonst kann sie lesen.';

  @override
  String get commonToday => 'Heute';

  @override
  String get commonYesterday => 'Gestern';

  @override
  String get chatMessageHint => 'Nachricht schreiben…';

  @override
  String get chatDiscardRecording => 'Verwerfen';

  @override
  String get chatRecording => 'Aufnahme läuft…';

  @override
  String get chatMicPermissionMissing => 'Mikrofonberechtigung fehlt';

  @override
  String chatRecordingFailed(String error) {
    return 'Aufnahme fehlgeschlagen: $error';
  }

  @override
  String chatVoiceSendFailed(String error) {
    return 'Senden der Sprachnachricht fehlgeschlagen: $error';
  }

  @override
  String get chatDeletedMessagePreview => 'Gelöschte Nachricht';

  @override
  String get chatVoiceMessagePreview => '🎤 Sprachnachricht';

  @override
  String get chatPhotoPreview => '📷 Foto';

  @override
  String get chatAttachmentPreview => '📎 Anhang';

  @override
  String get chatEditingMessage => 'Nachricht bearbeiten';

  @override
  String get chatReply => 'Antwort';

  @override
  String get chatActionReply => 'Antworten';

  @override
  String get commonCopy => 'Kopieren';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get chatDeleteForMe => 'Für mich löschen';

  @override
  String get chatDeleteForEveryone => 'Für alle löschen';

  @override
  String get commonOff => 'Aus';

  @override
  String get chatDisappearing30s => '30 Sekunden';

  @override
  String get chatDisappearing5m => '5 Minuten';

  @override
  String get chatDisappearing1h => '1 Stunde';

  @override
  String get chatDisappearing1d => '1 Tag';

  @override
  String get chatDisappearing1w => '1 Woche';

  @override
  String get chatDisappearingDescription =>
      'Neue Nachrichten werden nach Ablauf der Zeit bei dir und beim Gegenüber gelöscht.';

  @override
  String get chatDisappearingDisabled =>
      'Verschwindende Nachrichten deaktiviert';

  @override
  String chatDisappearingEnabled(String duration) {
    return 'Neue Nachrichten verschwinden nach: $duration';
  }

  @override
  String get attachmentGallery => 'Foto aus der Galerie';

  @override
  String get attachmentTakePhoto => 'Foto aufnehmen';

  @override
  String get attachmentDocument => 'Dokument';

  @override
  String attachmentTooLarge(int maxMb) {
    return 'Datei ist zu groß (max. $maxMb MB)';
  }

  @override
  String attachmentPickFailed(String error) {
    return 'Auswahl des Anhangs fehlgeschlagen: $error';
  }

  @override
  String attachmentSendFailed(String error) {
    return 'Senden des Anhangs fehlgeschlagen: $error';
  }

  @override
  String chatSendFailed(String error) {
    return 'Senden fehlgeschlagen: $error';
  }

  @override
  String get chatMessageDeleted => 'Nachricht gelöscht';

  @override
  String get chatEdited => 'bearbeitet';

  @override
  String get errorTrustRootChanged =>
      'Der Trust Root des Relays hat sich geändert! Kommunikation wird verweigert.';

  @override
  String get errorRelayUnavailable =>
      'Relay nicht erreichbar (Sender-Zertifikat)';

  @override
  String errorAttachmentTooLarge(int maxMb) {
    return 'Anhang ist zu groß (max. $maxMb MB)';
  }

  @override
  String get errorGroupNeedsMember =>
      'Die Gruppe braucht mindestens 1 Mitglied';

  @override
  String errorGroupMaxMembers(int maxMembers) {
    return 'Die Gruppe kann höchstens $maxMembers Mitglieder haben';
  }

  @override
  String errorMemberNoDeliveryAddress(String displayName) {
    return '$displayName hat keine Zustelladresse — frag nach einem neuen Link';
  }

  @override
  String get errorContactNoDeliveryAddress =>
      'Der Kontakt hat keine Zustelladresse — bitte ihn um einen neuen sepot://-Link';

  @override
  String get errorIdentityKeyMismatch =>
      'Der Identitätsschlüssel vom Relay passt NICHT zum Kontakt — möglicher MITM-Angriff! Nachricht nicht gesendet.';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsSectionGeneral => 'Allgemein';

  @override
  String get settingsSectionSecurity => 'Sicherheit';

  @override
  String get settingsChangePinTitle => 'PIN ändern';

  @override
  String get settingsChangePinSubtitle => '6-stellige PIN zum Entsperren';

  @override
  String get settingsAutoLockTitle => 'Automatische Sperre';

  @override
  String get settingsAutoLock5min => 'Nach 5 Minuten';

  @override
  String get settingsDecoyPinTitle => 'Tarn-PIN';

  @override
  String get settingsDecoyPinSetSubtitle =>
      'Eingerichtet — öffnet eine leere App';

  @override
  String get settingsDecoyPinUnsetSubtitle =>
      'Zweite PIN, die eine leere App öffnet';

  @override
  String get settingsSectionNotifications => 'Benachrichtigungen';

  @override
  String get settingsSectionConnection => 'Verbindung';

  @override
  String get settingsSectionPrivacy => 'Privatsphäre';

  @override
  String get settingsReadReceiptsTitle => 'Lesebestätigungen';

  @override
  String get settingsReadReceiptsSubtitle =>
      'Dem Gegenüber anzeigen, dass Nachrichten gelesen wurden (standardmäßig aus)';

  @override
  String get settingsScreenSecurityTitle => 'Bildschirmsicherheit';

  @override
  String get settingsScreenSecuritySubtitle =>
      'Screenshots blockieren und Inhalt in der App-Übersicht verbergen';

  @override
  String get settingsSectionBackup => 'Schlüssel-Backup';

  @override
  String get settingsSeedPhraseTitle => 'Wiederherstellungsphrase';

  @override
  String get settingsSeedPhraseSubtitle =>
      '24 Wörter zur Wiederherstellung deiner Identität';

  @override
  String get settingsBackupExportTitle => 'Verlauf sichern';

  @override
  String get settingsBackupExportSubtitle =>
      'Verschlüsselte Datei mit Kontakten und Nachrichten';

  @override
  String get settingsBackupImportTitle => 'Aus Backup wiederherstellen';

  @override
  String get settingsBackupImportSubtitle =>
      'Backup laden (nur mit deiner Identität)';

  @override
  String get settingsSectionSafety => 'Schutz';

  @override
  String get settingsReportAbuseTitle => 'Missbrauch melden';

  @override
  String get settingsReportAbuseSubtitle =>
      'Belästigung, Betrug, Gefährdung eines Kindes';

  @override
  String get settingsChildSafetyTitle => 'Kinderschutz-Standards';

  @override
  String get settingsChildSafetySubtitle =>
      'Wie wir gegen Kindesmissbrauch vorgehen';

  @override
  String get settingsSectionAbout => 'Über die App';

  @override
  String get commonAppName => 'Šepot';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsLicenseTitle => 'Lizenz';

  @override
  String get settingsLicenseSubtitle => 'AGPL-3.0';

  @override
  String get settingsPrivacyPolicyTitle => 'Datenschutzerklärung';

  @override
  String get settingsPrivacyPolicySubtitle =>
      'Was wir über dich wissen (und was nicht)';

  @override
  String get settingsTermsTitle => 'Nutzungsbedingungen';

  @override
  String get settingsTermsSubtitle => 'sepot.cz/podminky';

  @override
  String get settingsDataDeletionTitle => 'Datenlöschung';

  @override
  String get settingsDataDeletionSubtitle => 'So beantragst du die Löschung';

  @override
  String get settingsDeleteAllDataButton => 'Alle Daten löschen';

  @override
  String settingsLicenseBody(String supportEmail) {
    return 'Šepot wird unter der GNU Affero General Public License Version 3 (AGPL-3.0) verbreitet. Es nutzt die Bibliothek libsignal, ebenfalls AGPL-3.0.\n\nDen Quellcode zu dieser Version kannst du per E-Mail an $supportEmail anfordern — wir schicken ihn dir.';
  }

  @override
  String get commonClose => 'Schließen';

  @override
  String get settingsIdCopied => 'ID kopiert';

  @override
  String settingsFingerprint(String fingerprint) {
    return 'Fingerabdruck: $fingerprint';
  }

  @override
  String get backupShareSubject => 'Šepot — verschlüsseltes Backup';

  @override
  String backupExportFailed(String error) {
    return 'Backup fehlgeschlagen: $error';
  }

  @override
  String backupRestoredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen aus dem Backup wiederhergestellt',
      one: '1 Unterhaltung aus dem Backup wiederhergestellt',
    );
    return '$_temp0';
  }

  @override
  String backupImportFailed(String error) {
    return 'Wiederherstellung aus dem Backup fehlgeschlagen: $error';
  }

  @override
  String get settingsDecoyPinExplain =>
      'Mit dieser PIN öffnet sich die App leer — ohne deine Kontakte und Nachrichten. Sie muss sich von der normalen PIN unterscheiden.';

  @override
  String get commonConfirm => 'Bestätigen';

  @override
  String get commonSet => 'Festlegen';

  @override
  String get settingsDecoyPinEnabled => 'Tarn-PIN eingerichtet';

  @override
  String get settingsDecoyPinConflict =>
      'Die Tarn-PIN muss sich von der normalen PIN unterscheiden';

  @override
  String get settingsDecoyPinDisabled => 'Tarn-PIN deaktiviert';

  @override
  String get settingsSeedPhraseNotFound =>
      'Wiederherstellungsphrase nicht gefunden';

  @override
  String get settingsSeedPhraseWarning =>
      'Diese Wörter sind das einzige Backup deiner Identität. Zeig sie niemandem!';

  @override
  String settingsSeedWordChip(int index, String word) {
    return '$index. $word';
  }

  @override
  String get settingsAboutTagline => 'Šepot — Privater Messenger';

  @override
  String get settingsAboutBody =>
      'E2E-verschlüsselter Messenger mit offenem Quellcode.\n\nKryptografie:\n• X25519 (Schlüsselaustausch)\n• XChaCha20-Poly1305 (Verschlüsselung)\n• Ed25519 (Signaturen)\n\n© 2026 ajtak.it';

  @override
  String get settingsDeleteAccountTitle => 'Konto und alle Daten löschen?';

  @override
  String get settingsDeleteAccountBody =>
      'Diese Aktion kann nicht rückgängig gemacht werden. Alle Nachrichten, Kontakte und Schlüssel werden von diesem Gerät gelöscht und die Registrierung auf dem Server wird entfernt. Ohne Wiederherstellungsphrase verlierst du deine Identität.';

  @override
  String get settingsDeleteAccountServerOffline =>
      'Der Server ist gerade nicht erreichbar — die Daten auf dem Gerät sind gelöscht, die Registrierung auf dem Server besteht noch. Den Rest löschen wir für dich — schreib an podpora@sepot.cz.';

  @override
  String get settingsDeleteAllConfirm => 'Alles löschen';

  @override
  String groupsCreateFailed(String error) {
    return 'Gruppe konnte nicht erstellt werden: $error';
  }

  @override
  String get groupsNewGroupTitle => 'Neue Gruppe';

  @override
  String get groupsCreateAction => 'Erstellen';

  @override
  String groupsMembersCounter(int selectedCount, int maxMembers) {
    return 'Mitglieder ($selectedCount/$maxMembers)';
  }

  @override
  String get groupsEmptyContactsHint =>
      'Füge zuerst Kontakte hinzu — eine Gruppe besteht aus Leuten, mit denen du schon schreiben kannst.';

  @override
  String get groupsMemberMissingAddress =>
      'Zustelladresse fehlt — frag nach einem neuen Link';

  @override
  String attachmentSizeBytes(int bytes) {
    return '$bytes B';
  }

  @override
  String attachmentSizeKb(String kilobytes) {
    return '$kilobytes kB';
  }

  @override
  String attachmentSizeMb(String megabytes) {
    return '$megabytes MB';
  }

  @override
  String get attachmentDownloadFailedTapToRetry =>
      'Download fehlgeschlagen — zum Wiederholen antippen';

  @override
  String get attachmentDownloadFailed => 'Download fehlgeschlagen';

  @override
  String get attachmentDownloading => 'Wird heruntergeladen…';

  @override
  String get attachmentSharedFileFallbackName => 'datei';

  @override
  String attachmentOpenFailed(String error) {
    return 'Öffnen des Anhangs fehlgeschlagen: $error';
  }

  @override
  String get commonFile => 'Datei';

  @override
  String get chatListNewConversation => 'Neue Unterhaltung';

  @override
  String chatListPhotoWithCaptionPreview(String caption) {
    return '📷 $caption';
  }

  @override
  String chatListFilePreview(String fileName) {
    return '📎 $fileName';
  }

  @override
  String get chatListReadReceiptPreview => 'Gelesen';

  @override
  String get chatListTimeNow => 'jetzt';

  @override
  String chatListTimeMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get qrScanTitle => 'QR-Code scannen';

  @override
  String get qrScanInstruction =>
      'Richte die Kamera auf den QR-Code des Kontakts';

  @override
  String get qrScanHint =>
      'Der QR-Code enthält den öffentlichen Schlüssel des Kontakts';

  @override
  String get qrNewContactTitle => 'Neuer Kontakt';

  @override
  String qrContactAdded(String name) {
    return '$name hinzugefügt';
  }

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get onboardingWelcomeTitle => 'Willkommen bei Šepot';

  @override
  String get onboardingWelcomeSubtitle =>
      'Privater Messenger mit Ende-zu-Ende-Verschlüsselung.\nKeine Telefonnummer. Keine E-Mail.\nNur deine Schlüssel.';

  @override
  String get onboardingStart => 'Los geht\'s';

  @override
  String get onboardingRestoreExisting =>
      'Ich habe schon ein Konto — mit Wiederherstellungsphrase wiederherstellen';

  @override
  String get onboardingEncryptionTitle => 'Deine Nachrichten, deine Schlüssel';

  @override
  String get onboardingFeatureSignalTitle => 'Signal-Protokoll';

  @override
  String get onboardingFeatureSignalSubtitle =>
      'X3DH + Double Ratchet, Forward Secrecy';

  @override
  String get onboardingFeaturePqTitle => 'Post-Quanten-Schutz';

  @override
  String get onboardingFeaturePqSubtitle =>
      'Kyber (PQXDH) ab der ersten Nachricht';

  @override
  String get onboardingFeatureLocalKeysTitle =>
      'Schlüssel nur auf deinem Gerät';

  @override
  String get onboardingFeatureLocalKeysSubtitle => 'Kein Server kennt sie';

  @override
  String get onboardingFeatureDisappearingSubtitle =>
      'Werden automatisch gelöscht';

  @override
  String get commonContinue => 'Weiter';

  @override
  String get onboardingIdentityTitle => 'Erstelle deine Identität';

  @override
  String get onboardingIdentitySubtitle =>
      'Keine E-Mail, kein Telefon. Nur ein Name und kryptografische Schlüssel.';

  @override
  String get onboardingDisplayNameLabel => 'Anzeigename';

  @override
  String get onboardingDisplayNameHint => 'z. B. Anna';

  @override
  String onboardingSeedPhraseWarning(int count) {
    return 'Schreib dir diese $count Wörter auf. Sie sind das einzige Backup deiner Schlüssel!';
  }

  @override
  String get onboardingSeedSavedConfirm =>
      'Ich bestätige, dass ich die Phrase sicher gespeichert habe';

  @override
  String get onboardingGenerateKeys => 'Schlüssel erzeugen';

  @override
  String get verifyMismatchTitle => 'Nummern stimmen NICHT überein';

  @override
  String verifyMatchBody(String contactName) {
    return 'Die Schlüssel stimmen überein. $contactName ist ein verifizierter Kontakt.';
  }

  @override
  String get verifyMismatchBody =>
      'Die Sicherheitsnummern stimmen nicht überein. Jemand könnte die Verbindung abhören (MITM), oder du scannst den Code eines anderen Kontakts. Sende KEINE sensiblen Nachrichten und verifiziere den Kontakt noch einmal über einen anderen Kanal.';

  @override
  String get commonUnderstood => 'Verstanden';

  @override
  String get verifyManualConfirmTitle => 'Als verifiziert markieren?';

  @override
  String get verifyManualConfirmBody =>
      'Bestätige nur, wenn du die Ziffern mit deinem Gegenüber über einen anderen vertrauenswürdigen Kanal (persönlich, per Anruf…) verglichen hast und sie übereinstimmen.';

  @override
  String get verifyManualConfirmAction => 'Stimmen überein, verifizieren';

  @override
  String get verifyTitle => 'Kontakt verifizieren';

  @override
  String get verifyContactVerifiedBanner => 'Der Kontakt ist verifiziert';

  @override
  String verifyIntro(String contactName) {
    return 'Vergleiche diese Nummer mit $contactName. Wenn sie übereinstimmt, hört niemand eure Kommunikation ab. Am schnellsten geht es, wenn ihr gegenseitig eure QR-Codes scannt.';
  }

  @override
  String get verifyScanButton => 'Code des Gegenübers scannen';

  @override
  String get verifyManualButton => 'Ziffern stimmen — manuell markieren';

  @override
  String get verifyUnverifyButton => 'Verifizierung aufheben';

  @override
  String get verifyScanScreenTitle => 'Verifizierungs-QR scannen';

  @override
  String get reportTitle => 'Melden';

  @override
  String get reportSubmitted => 'Meldung gesendet';

  @override
  String get reportSubmittedChildSafety =>
      'Wir behandeln die Meldung mit Priorität. Wenn ein Kind unmittelbar in Gefahr ist, ruf die örtliche Polizei (Notruf) oder eine Kinderschutz-Hotline an.';

  @override
  String get reportSubmittedThanks =>
      'Danke. Wir sehen es uns so schnell wie möglich an.';

  @override
  String get commonDone => 'Fertig';

  @override
  String get reportPanelE2eNotice =>
      'Nachrichten sind Ende-zu-Ende-verschlüsselt — wir sehen ihren Inhalt auch jetzt nicht. Beschreibe bitte in eigenen Worten, was passiert ist. Füge keine Nachrichteninhalte oder Links darauf ein — wir dürfen sie nicht speichern und brauchen sie für die Prüfung nicht.';

  @override
  String get reportPanelCsamWarning =>
      'Schick uns KEIN Material, das den Missbrauch eines Kindes zeigt. Schon der Besitz ist auch für uns strafbar, und für die Meldung brauchen wir es nicht. Solches Material gehört direkt an die Polizei oder die zuständige Meldestelle in deinem Land. Schreib uns nur, was passiert ist — wir sperren das Konto und leiten die Sache weiter.';

  @override
  String get reportPanelIpNotice =>
      'Die Meldung läuft nicht über das Relay, sondern an unseren Webserver. Dieser erfährt beim Absenden deine IP-Adresse.';

  @override
  String get reportCategoryHeading => 'Worum es in der Meldung geht';

  @override
  String get reportDescriptionHeading => 'Was ist passiert';

  @override
  String get reportAttachContactId => 'ID des gemeldeten Kontakts anhängen';

  @override
  String reportAttachContactIdNamed(String contactName) {
    return 'ID des Kontakts $contactName anhängen';
  }

  @override
  String get reportReplyToHeading => 'Kontakt zu dir (optional)';

  @override
  String get reportReplyToHint => 'E-Mail, falls wir Rückfragen haben';

  @override
  String get reportSubmitButton => 'Meldung senden';

  @override
  String get contactsTitle => 'Kontakte';

  @override
  String get contactsAddContact => 'Kontakt hinzufügen';

  @override
  String get contactsSearchHint => 'Kontakt suchen...';

  @override
  String get contactsEmpty => 'Noch keine Kontakte';

  @override
  String get contactsNoResults => 'Keine Ergebnisse';

  @override
  String get contactsShareCardTitle => 'Teile deine Šepot-ID';

  @override
  String get contactsShareCardSubtitle =>
      'Zeig deinen QR-Code oder schick einen Link';

  @override
  String get contactsAddDialogPrompt =>
      'Füge den Share-String des Kontakts ein:';

  @override
  String get contactsShareStringHint => 'Share-String einfügen...';

  @override
  String get contactsInvalidShareString => 'Ungültiger Share-String';

  @override
  String contactsAdded(String name) {
    return 'Kontakt $name hinzugefügt';
  }

  @override
  String get verifyContactSubtitle => 'Sicherheitsnummer vergleichen';

  @override
  String get contactsDeleteContact => 'Kontakt löschen';

  @override
  String get pinConfirmTitle => 'PIN bestätigen';

  @override
  String get pinSetupTitle => 'PIN festlegen';

  @override
  String get pinConfirmSubtitle => 'Gib die PIN zur Bestätigung erneut ein';

  @override
  String get pinSetupSubtitle => '6-stellige PIN zum Entsperren der App';

  @override
  String get pinSetupFailed =>
      'PIN-Einrichtung fehlgeschlagen. Versuch es noch mal.';

  @override
  String get pinMismatchRetry =>
      'Die PINs stimmen nicht überein. Versuch es noch mal.';

  @override
  String get pinChangeCurrentTitle => 'Aktuelle PIN eingeben';

  @override
  String get pinChangeCurrentSubtitle =>
      'Wir prüfen sie durch Entsperren des Schlüssels';

  @override
  String get pinChangeNewTitle => 'Neue PIN eingeben';

  @override
  String get pinChangeNewSubtitle => '6 Ziffern';

  @override
  String get pinChangeConfirmTitle => 'Neue PIN bestätigen';

  @override
  String get pinChangeConfirmSubtitle => 'Gib sie noch einmal ein';

  @override
  String get pinWrong => 'Falsche PIN.';

  @override
  String get pinChangeMustDiffer =>
      'Die neue PIN muss sich von der aktuellen unterscheiden.';

  @override
  String get pinMismatch => 'Die PINs stimmen nicht überein.';

  @override
  String get pinDecoyConflict =>
      'Diese PIN gehört schon zum Tarn-Modus. Wähle eine andere.';

  @override
  String get pinChangeFailed =>
      'PIN-Änderung fehlgeschlagen. Versuch es noch mal.';

  @override
  String get pinChanged => 'PIN geändert';

  @override
  String get errorCryptoInitTitle =>
      'Der Verschlüsselungskern konnte nicht gestartet werden';

  @override
  String get errorStartupTitle => 'Šepot konnte nicht gestartet werden';

  @override
  String get errorScreenNotRenderedTitle =>
      'Dieser Bildschirm konnte nicht dargestellt werden';

  @override
  String get errorStartupBody =>
      'Gleich beim Start ist etwas schiefgegangen. Schick mir bitte diesen Text (gedrückt halten und kopieren) — er hilft mir, den Fehler zu finden.';

  @override
  String get errorContactFooter =>
      'sepot.cz · schreib mir über die Kontaktseite';

  @override
  String get pinUnlockTitle => 'Šepot entsperren';

  @override
  String get pinEnterPin => 'PIN eingeben';

  @override
  String get pinUnlockWithBiometrics => 'Mit Biometrie entsperren';

  @override
  String get pinWrong2 => 'Falsche PIN';

  @override
  String get pinUnlockError => 'Fehler beim Entsperren';

  @override
  String get pushTitle => 'Push-Benachrichtigungen';

  @override
  String get pushModeOffDesc =>
      'Nachrichten werden erst beim Öffnen der App abgerufen.';

  @override
  String get pushModeUp => 'UnifiedPush (empfohlen)';

  @override
  String get pushModeUpDesc =>
      'Google-frei — braucht die App ntfy (F-Droid/Play).';

  @override
  String get pushModeFcm => 'Google (FCM)';

  @override
  String get pushModeFcmDesc =>
      'Zuverlässig ohne zusätzliche App. Der Push-Token des Geräts geht an Google; der Inhalt der Nachrichten nie.';

  @override
  String pushSetupFailed(String error) {
    return 'Einrichtung der Push-Benachrichtigungen fehlgeschlagen: $error';
  }

  @override
  String get pushNoDistributorTitle => 'Kein Distributor';

  @override
  String get pushNoDistributorBody =>
      'Für Google-freie Benachrichtigungen installiere einen UnifiedPush-Distributor, z. B. ntfy (F-Droid oder Play). Aktiviere Push danach erneut.';

  @override
  String get commonOk => 'OK';

  @override
  String get pushPickDistributorTitle => 'Distributor wählen';

  @override
  String pushSubtitleUnifiedPush(String distributor) {
    return 'UnifiedPush · $distributor';
  }

  @override
  String get pushNoDistributorFallback => 'kein Distributor';

  @override
  String get pushSubtitleFcm => 'Google (FCM) — schnell, opt-in';

  @override
  String get restoreErrorNameRequired => 'Gib einen Anzeigenamen ein.';

  @override
  String restoreErrorWordCount(int wordCount, int requiredWords) {
    String _temp0 = intl.Intl.pluralLogic(
      wordCount,
      locale: localeName,
      other:
          'Die Phrase hat $wordCount Wörter, benötigt werden $requiredWords.',
      one: 'Die Phrase hat 1 Wort, benötigt werden $requiredWords.',
    );
    return '$_temp0';
  }

  @override
  String get restoreErrorInvalidPhrase =>
      'Die Phrase ist ungültig — prüfe die Wörter und ihre Reihenfolge.';

  @override
  String restoreErrorFailed(String error) {
    return 'Wiederherstellung fehlgeschlagen: $error';
  }

  @override
  String get restoreTitle => 'Konto wiederherstellen';

  @override
  String get restoreHeading => 'Gib deine Wiederherstellungsphrase ein';

  @override
  String restoreIntro(int wordCount) {
    return '$wordCount Wörter aus dem Backup, das beim Erstellen des Kontos angelegt wurde. Stellt deine Identität wieder her (gleicher SEP-Code, deine Kontakte erkennen dich weiter).';
  }

  @override
  String get restoreHistoryWarning =>
      'Der Nachrichtenverlauf wird nicht wiederhergestellt — er ist nur auf dem ursprünglichen Gerät gespeichert.';

  @override
  String get restorePhraseHint => 'wort1 wort2 wort3 …';

  @override
  String restoreWordCountHelper(int wordCount, int requiredWords) {
    return '$wordCount / $requiredWords Wörter';
  }

  @override
  String chatListArchivedCount(int count) {
    return 'Archiviert ($count)';
  }

  @override
  String get chatListEmptyTitle => 'Noch keine Unterhaltungen';

  @override
  String get chatListEmptySubtitle =>
      'Füge einen Kontakt hinzu und fang an zu flüstern!';

  @override
  String get chatListUnmute => 'Stummschaltung aufheben';

  @override
  String get chatListMute => 'Stummschalten';

  @override
  String get chatListArchive => 'Archivieren';

  @override
  String get qrShareTitle => 'Meine Šepot-ID';

  @override
  String get qrIdentityNotFound => 'Identität nicht gefunden';

  @override
  String get commonCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String qrShareInviteMessage(String shareString) {
    return 'Füg mich auf Šepot hinzu!\n\n$shareString';
  }

  @override
  String get commonShare => 'Teilen';

  @override
  String get qrShareInfo =>
      'Dein Kontakt scannt deinen QR-Code oder fügt den Share-String in die App ein.';

  @override
  String get reportCategoryChildSafety => 'Gefährdung eines Kindes';

  @override
  String get reportCategoryChildSafetyHint =>
      'Beschreibe die Situation in eigenen Worten. Füge keine Nachrichteninhalte oder Links zu Material ein.';

  @override
  String get reportCategoryHarassment => 'Belästigung oder Drohungen';

  @override
  String get reportCategoryHarassmentHint =>
      'Jemand schüchtert dich ein, droht dir oder belästigt dich.';

  @override
  String get reportCategorySpam => 'Spam';

  @override
  String get reportCategorySpamHint =>
      'Unerwünschte Nachrichten, Massenversand.';

  @override
  String get reportCategoryFraud => 'Betrug';

  @override
  String get reportCategoryFraudHint =>
      'Versuch, Geld, Schlüssel oder persönliche Daten zu erschleichen.';

  @override
  String get reportCategoryOther => 'Sonstiges';

  @override
  String get reportCategoryOtherHint =>
      'Etwas anderes, das wir wissen sollten.';

  @override
  String get reportErrorEmptyDescription => 'Schreib bitte, was passiert ist.';

  @override
  String reportErrorConnection(String supportEmail) {
    return 'Verbindung zum Server fehlgeschlagen. Versuch es noch mal oder schreib an $supportEmail.';
  }

  @override
  String reportErrorRateLimited(String supportEmail) {
    return 'Aus deinem Netzwerk kamen zu viele Meldungen. Versuch es in einer Stunde noch mal oder schreib an $supportEmail.';
  }

  @override
  String reportErrorServer(int statusCode, String supportEmail) {
    return 'Senden fehlgeschlagen (Code $statusCode). Schreib bitte an $supportEmail.';
  }

  @override
  String get settingsAutoLockNever => 'Nie';

  @override
  String get settingsAutoLock1min => 'Nach 1 Minute';

  @override
  String get settingsAutoLock15min => 'Nach 15 Minuten';

  @override
  String torToggleFailed(String error) {
    return 'Umschalten von Tor fehlgeschlagen: $error';
  }

  @override
  String get torConnectionTitle => 'Verbindung über Tor';

  @override
  String get torDialogBody =>
      'Der Verkehr zum Server läuft über das Tor-Netzwerk (verbirgt deine IP-Adresse). Erfordert die installierte und laufende App Orbot mit aktivem SOCKS-Proxy auf Port 9050.\n\nOhne laufendes Orbot werden Nachrichten weder gesendet noch empfangen. Die Verbindung ist meist langsamer.';

  @override
  String get commonTurnOn => 'Aktivieren';

  @override
  String get torSubtitleOff =>
      'Direkte verschlüsselte Verbindung (WSS). Aktiviere Tor, um deine IP zu verbergen.';

  @override
  String get torStatusConnected => 'Über Tor verbunden (.onion).';

  @override
  String get torStatusConnecting => 'Verbinde über Tor… (läuft Orbot?)';

  @override
  String get torStatusWaiting => 'Über Tor — warte auf Orbot (SOCKS 9050).';

  @override
  String get biometricsPinRequiredFirst =>
      'Richte zuerst eine PIN ein — Biometrie ergänzt sie nur.';

  @override
  String get biometricsStorageLocked =>
      'Der Speicher ist gesperrt — entsperre die App mit der PIN.';

  @override
  String get biometricsNotAvailable =>
      'Auf dem Gerät ist keine Biometrie eingerichtet.';

  @override
  String get biometricsEnrollPromptReason =>
      'Bestätige die Aktivierung der biometrischen Entsperrung';

  @override
  String biometricsSetupFailed(String error) {
    return 'Biometrie konnte nicht eingerichtet werden: $error';
  }

  @override
  String get biometricsTileTitle => 'Biometrie';

  @override
  String get biometricsTileSubtitle =>
      'Entsperren per Fingerabdruck/Gesicht (PIN bleibt als Backup)';

  @override
  String get backupErrorCorruptedFile => 'Beschädigte Backup-Datei';

  @override
  String get backupErrorUnknownFormat => 'Unbekanntes Backup-Format';

  @override
  String get backupErrorWrongIdentity =>
      'Backup lässt sich nicht entschlüsseln — gehört es zu einer anderen Identität?';

  @override
  String attachmentSharedImageFilename(String ext) {
    return 'sepot-bild.$ext';
  }

  @override
  String get attachmentDecryptFailed =>
      'Anhang konnte nicht entschlüsselt werden';

  @override
  String get pushActionOpen => 'Öffnen';

  @override
  String get pushChannelMessagesName => 'Nachrichten';

  @override
  String get pushChannelMessagesDescription =>
      'Hinweise auf neue Nachrichten (ohne Inhalt)';

  @override
  String pushNewMessageFrom(String senderName) {
    return 'Neue Nachricht von $senderName';
  }

  @override
  String get pushNewMessages => 'Du hast neue Nachrichten';

  @override
  String get archiveTitle => 'Archiviert';

  @override
  String get archiveEmpty => 'Keine archivierten Unterhaltungen';

  @override
  String get archiveUnarchive => 'Archivierung aufheben';

  @override
  String restoreErrorMnemonicWordCount(int count, int expected) {
    return 'Die Phrase hat $count Wörter, erwartet werden $expected';
  }

  @override
  String restoreErrorInvalidMnemonic(String message) {
    return 'Ungültige Phrase: $message';
  }

  @override
  String get contactsErrorAlreadyExists => 'Kontakt existiert bereits';

  @override
  String get commonAppTagline => 'Privater Messenger';

  @override
  String get commonE2eBadgeCompact => 'E2E';

  @override
  String get commonE2eBadgeFull => 'Ende-zu-Ende-verschlüsselt';
}
