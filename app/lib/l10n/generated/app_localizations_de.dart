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
  String get groupsYou => 'Du';

  @override
  String get groupsFounder => 'Hat die Gruppe gegründet';

  @override
  String get groupsAdmin => 'Admin';

  @override
  String get groupsMakeAdmin => 'Zum Admin machen';

  @override
  String get groupsDismissAdmin => 'Adminrolle entziehen';

  @override
  String get groupsRemoveMember => 'Aus der Gruppe entfernen';

  @override
  String groupsRemoveMemberConfirmTitle(String name) {
    return '$name aus der Gruppe entfernen?';
  }

  @override
  String get groupsRemoveMemberConfirmBody =>
      'Neue Nachrichten der Gruppe kommen dann nicht mehr an. Der bisherige Verlauf bleibt erhalten.';

  @override
  String get groupsRemoveAction => 'Entfernen';

  @override
  String get groupsViewContact => 'Kontakt anzeigen';

  @override
  String get groupsAdminOnlyHint =>
      'Nur Admins können Namen, Mitglieder und Admins der Gruppe ändern.';

  @override
  String get groupsAdminOnlyCompatHint =>
      'Nur Admins können die Gruppe umbenennen oder Admins ändern. Personen hinzufügen kann vorerst jeder, weil jemand in der Gruppe eine ältere Šepot-Version hat.';

  @override
  String groupsAdminActionFailed(String error) {
    return 'Änderung fehlgeschlagen: $error';
  }

  @override
  String get groupsResyncNotice =>
      'Die Gruppe gleicht sich mit dem Admin ab. Änderungen an Mitgliedern können sich kurz verzögern.';

  @override
  String get groupsRejectedChangeNotice =>
      'Jemand ohne Berechtigung hat versucht, die Gruppe zu ändern. Die Änderung wurde nicht übernommen.';

  @override
  String get errorGroupNotAdmin => 'Das kann nur ein Admin der Gruppe.';

  @override
  String get errorGroupLastAdmin =>
      'Du bist der einzige Admin. Mach zuerst jemand anderen zum Admin.';

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
  String get chatActionForward => 'Weiterleiten';

  @override
  String get forwardTitle => 'Weiterleiten an…';

  @override
  String get forwardSearchHint => 'Kontakt oder Gruppe suchen';

  @override
  String get forwardEmpty => 'Nichts gefunden';

  @override
  String forwardDone(String name) {
    return 'Weitergeleitet an $name';
  }

  @override
  String forwardFailed(String error) {
    return 'Weiterleiten fehlgeschlagen: $error';
  }

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
  String get attachmentKeepsMetadataTitle => 'Foto enthält den Standort';

  @override
  String get attachmentKeepsMetadataBody =>
      'Aus diesem Fotoformat (z. B. HEIC) kann ich die Metadaten nicht entfernen. Es würde im Original gesendet, einschließlich Aufnahmeort und Angaben zum Telefon. Sicherer ist das Senden über die Galerie, dort werden die Metadaten entfernt.';

  @override
  String get attachmentSendOriginal => 'Original senden';

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
  String get errorNotYetRegistered =>
      'Šepot verbindet sich noch mit dem Relay — versuch es gleich noch einmal.';

  @override
  String get errorContactLinkIncomplete =>
      'Dieser Link ist unvollständig — die andere Person hat ihn erstellt, bevor sie verbunden war. Bitte sie um einen neuen sepot://-Link.';

  @override
  String errorAttachmentTooLarge(int maxMb) {
    return 'Anhang ist zu groß (max. $maxMb MB)';
  }

  @override
  String get errorGroupNeedsMember =>
      'Die Gruppe braucht mindestens 1 Mitglied';

  @override
  String get errorAttachmentUnavailable =>
      'Der Anhang ist nicht mehr auf diesem Telefon';

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
  String get chatListReadReceiptPreview => 'Gelesen';

  @override
  String get chatListDraft => 'Entwurf';

  @override
  String get notesTitle => 'Notizen für mich';

  @override
  String get notesSubtitle => 'Nur auf diesem Telefon, verschlüsselt';

  @override
  String get callVoice => 'Anrufen';

  @override
  String get callVideo => 'Videoanruf';

  @override
  String get callStatusRinging => 'Klingelt…';

  @override
  String get callIncomingVoice => 'Eingehender Anruf';

  @override
  String get callIncomingVideo => 'Eingehender Videoanruf';

  @override
  String get callStatusConnecting => 'Verbinde…';

  @override
  String get callEnded => 'Anruf beendet';

  @override
  String get callEndedBusy => 'Besetzt';

  @override
  String get callEndedRejected => 'Anruf abgelehnt';

  @override
  String get callEndedUnanswered => 'Keine Antwort';

  @override
  String get callEndedFailed => 'Verbindung fehlgeschlagen';

  @override
  String get callEncrypted => 'Ende-zu-Ende-verschlüsselt';

  @override
  String get callAccept => 'Annehmen';

  @override
  String get callReject => 'Ablehnen';

  @override
  String get callMute => 'Stummschalten';

  @override
  String get callSpeaker => 'Lautsprecher';

  @override
  String get callCamera => 'Kamera aus';

  @override
  String get callSwitchCamera => 'Kamera wechseln';

  @override
  String get callHangUp => 'Auflegen';

  @override
  String get callLogMissed => 'Verpasster Anruf';

  @override
  String get callLogUnanswered => 'Unbeantworteter Anruf';

  @override
  String get callLogRejected => 'Abgelehnter Anruf';

  @override
  String get callLogBusy => 'Besetzt';

  @override
  String get callLogFailed => 'Anruf fehlgeschlagen';

  @override
  String callLogVoice(String duration) {
    return 'Anruf · $duration';
  }

  @override
  String callLogVideo(String duration) {
    return 'Videoanruf · $duration';
  }

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
  String pinLockedFor(int seconds) {
    return 'Zu viele Versuche. Versuche es in $seconds s erneut.';
  }

  @override
  String get pushTitle => 'Push-Benachrichtigungen';

  @override
  String get pushModeOffDesc =>
      'Nachrichten werden erst beim Öffnen der App abgerufen.';

  @override
  String get pushModeUp => 'UnifiedPush (ohne Google)';

  @override
  String get pushModeUpDesc =>
      'Google-frei — braucht die App ntfy (F-Droid/Play).';

  @override
  String get pushModeFcm => 'Google (FCM, Standard)';

  @override
  String get pushModeFcmDesc =>
      'Zuverlässig ohne zusätzliche App. Der Push-Token des Geräts geht an Google; der Inhalt der Nachrichten nie.';

  @override
  String pushSetupFailed(String error) {
    return 'Einrichtung der Push-Benachrichtigungen fehlgeschlagen: $error';
  }

  @override
  String get pushHintOff =>
      'Nachrichten kommen erst an, wenn du Šepot öffnest — keine Weckrufe eingerichtet.';

  @override
  String get pushHintFailed =>
      'Weckrufe funktionieren nicht; Nachrichten siehst du erst beim Öffnen von Šepot.';

  @override
  String get pushRegistrationFailed =>
      'Es kommen keine Weckrufe an — der Distributor hat die Registrierung abgelehnt. Schalte Push aus und wieder ein.';

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
  String get pushSubtitleFcm => 'Google (FCM)';

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
  String get qrShareConnectingTitle => 'Verbinde mit dem Relay…';

  @override
  String get qrShareConnectingBody =>
      'Dein QR-Code und Link erscheinen, sobald sich Šepot zum ersten Mal verbindet. Einen Moment — es dauert nur ein paar Sekunden.';

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

  @override
  String get photoPreviewCaptionHint => 'Bildunterschrift hinzufügen…';

  @override
  String get photoPreviewDraw => 'Zeichnen';

  @override
  String get photoPreviewAddText => 'Text hinzufügen';

  @override
  String get photoPreviewRotate => 'Drehen';

  @override
  String get photoPreviewUndo => 'Rückgängig';

  @override
  String get photoPreviewSend => 'Senden';

  @override
  String get photoPreviewTextDialogTitle => 'Text auf dem Foto';

  @override
  String get photoPreviewRemoveText => 'Entfernen';

  @override
  String get photoPreviewDecodeFailed => 'Foto konnte nicht geladen werden';

  @override
  String get chatActionInfo => 'Nachrichteninfo';

  @override
  String get messageInfoSent => 'Gesendet';

  @override
  String get messageInfoDelivered => 'Zugestellt';

  @override
  String get messageInfoRead => 'Gelesen';

  @override
  String get messageInfoPending => 'noch nicht';

  @override
  String get messageInfoReadReceiptsOff =>
      'Wann deine Nachrichten gelesen wurden, siehst du nur, wenn du selbst Lesebestätigungen teilst (Einstellungen).';

  @override
  String chatStatusReadAt(String time) {
    return 'Gelesen $time';
  }

  @override
  String chatStatusDeliveredAt(String time) {
    return 'Zugestellt $time';
  }

  @override
  String get groupsAddMembers => 'Mitglieder hinzufügen';

  @override
  String get groupsAddMembersAction => 'Hinzufügen';

  @override
  String groupsAddMembersFailed(String error) {
    return 'Hinzufügen fehlgeschlagen: $error';
  }

  @override
  String get groupsNoContactsToAdd =>
      'Alle deine Kontakte sind schon in der Gruppe. Füge neue Personen zuerst per QR-Code zu deinen Kontakten hinzu.';

  @override
  String get navChats => 'Chats';

  @override
  String get chatListNewChat => 'Neuer Chat';

  @override
  String get chatListSearchHint => 'Chats und Nachrichten durchsuchen';

  @override
  String get chatFilterAll => 'Alle';

  @override
  String get chatFilterUnread => 'Ungelesen';

  @override
  String get chatFilterGroups => 'Gruppen';

  @override
  String get chatFilterArchive => 'Archiv';

  @override
  String get chatListNoResults => 'Nichts gefunden.';

  @override
  String get chatListFilterEmpty => 'Hier ist noch nichts.';

  @override
  String get chatListPin => 'Anheften';

  @override
  String get chatListUnpin => 'Lösen';

  @override
  String get chatOpenProfile => 'Profil anzeigen';

  @override
  String get groupsProfile => 'Gruppeninfo';

  @override
  String get chatSearchHint => 'Im Chat suchen';

  @override
  String get chatSearchNoMatches => 'Keine';

  @override
  String chatSearchCounter(int current, int total) {
    return '$current von $total';
  }

  @override
  String get chatSearchOlder => 'Ältere Treffer';

  @override
  String get chatSearchNewer => 'Neuerer Treffer';

  @override
  String chatUnreadDivider(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Nachrichten',
      one: '1 neue Nachricht',
    );
    return '$_temp0';
  }

  @override
  String get chatJumpToLatest => 'Zu den neuesten';

  @override
  String get chatAttach => 'Anhängen';

  @override
  String get chatSend => 'Senden';

  @override
  String get chatRecordVoice => 'Sprachnachricht aufnehmen';

  @override
  String get profileSharedMedia => 'Geteilte Medien';

  @override
  String get profileMessage => 'Nachricht';

  @override
  String get profileSearch => 'Suchen';

  @override
  String get profileUnmute => 'Ton an';

  @override
  String get profileDisappearing => 'Verschwinden';

  @override
  String get profileCommonGroups => 'Gemeinsame Gruppen';

  @override
  String get profileSafetyNumber => 'Sicherheitsnummer';

  @override
  String get profileSafetyNumberHint =>
      'Persönlich oder per QR-Code vergleichen';

  @override
  String get profileVerifiedInPerson => 'Persönlich verifiziert';

  @override
  String get profileVerifyNow => 'Kontakt verifizieren';

  @override
  String get profileAdd => 'Hinzufügen';

  @override
  String profileGroupSubtitle(String members, String date) {
    return 'Gruppe · $members · erstellt am $date';
  }

  @override
  String profileMembersOfMax(int count, int max) {
    return '$count von $max';
  }

  @override
  String get chatTyping => 'schreibt…';

  @override
  String chatTypingNamed(String name) {
    return '$name schreibt…';
  }

  @override
  String get chatTypingSeveral => 'Mehrere schreiben…';

  @override
  String get settingsTypingTitle => 'Tippindikator';

  @override
  String get settingsTypingSubtitle =>
      'Gegenseitig — wer nicht teilt, sieht nichts (standardmäßig aus)';

  @override
  String get pollAttach => 'Umfrage';

  @override
  String get pollCreateTitle => 'Neue Umfrage';

  @override
  String get pollQuestion => 'Frage';

  @override
  String pollOptionHint(int number) {
    return 'Option $number';
  }

  @override
  String get pollAddOption => 'Option hinzufügen';

  @override
  String get pollRemoveOption => 'Option entfernen';

  @override
  String get pollAllowMultiple => 'Mehrere Antworten erlauben';

  @override
  String get pollSingle => 'Umfrage';

  @override
  String get pollMulti => 'Umfrage, Mehrfachauswahl';

  @override
  String pollVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stimmen',
      one: '1 Stimme',
      zero: 'noch keine Stimmen',
    );
    return '$_temp0';
  }

  @override
  String pollFallback(String question) {
    return 'Umfrage: $question';
  }

  @override
  String get pollFallbackUpdate => 'Zum Abstimmen Šepot aktualisieren.';

  @override
  String get profilePhotoEdit => 'Profilbild ändern';

  @override
  String get profilePhotoPick => 'Foto auswählen';

  @override
  String get profilePhotoRemove => 'Foto entfernen';

  @override
  String get profilePhotoHint =>
      'Nur deine Chatpartner sehen es — Ende-zu-Ende-verschlüsselt wie Nachrichten. Standort und Fotodaten werden nicht gesendet.';

  @override
  String profilePhotoFailed(String error) {
    return 'Foto konnte nicht gesetzt werden: $error';
  }

  @override
  String get reauthTitle => 'Bestätige, dass du es bist';

  @override
  String get reauthPinRequired =>
      'Diese Aktion erfordert eine PIN. Lege zuerst eine fest.';

  @override
  String get reauthSetPin => 'PIN festlegen';

  @override
  String get reauthReasonSeed => '24 Wiederherstellungswörter anzeigen';

  @override
  String get reauthReasonBackupExport => 'Backup exportieren';

  @override
  String get reauthReasonBackupImport => 'Aus Backup wiederherstellen';

  @override
  String get reauthReasonDecoyPin => 'Notfall-PIN ändern';

  @override
  String get reauthReasonAutoLock => 'Automatische Sperre verlängern';

  @override
  String get reauthReasonScreenSecurity => 'Bildschirmschutz ausschalten';

  @override
  String get reauthReasonDeleteAccount => 'Konto und alle Daten löschen';

  @override
  String get reauthReasonBiometrics => 'Biometrie einschalten';

  @override
  String contactRequestName(String name) {
    return '$name (unbekannt)';
  }

  @override
  String get pushMessageRequest =>
      'Nachrichtenanfrage von unbekanntem Absender';

  @override
  String get requestTitle => 'Nachrichtenanfrage';

  @override
  String requestBody(String name) {
    return '„$name“ ist nicht in deinen Kontakten. Name und Foto hat die Person selbst gewählt, sie ist also vielleicht nicht, wer sie vorgibt zu sein. Bis du annimmst, sieht sie nicht, dass du die Nachricht gelesen hast, und kann dich nicht anrufen.';
  }

  @override
  String requestLookalikeWarning(String name) {
    return 'Achtung: Dein Kontakt $name heißt genauso. Das ist ein anderer Schlüssel, also ein anderes Telefon oder eine andere Person. Prüfe das auf anderem Weg, bevor du antwortest (anrufen, persönlich treffen).';
  }

  @override
  String get requestAccept => 'Annehmen';

  @override
  String get requestAcceptTitle => 'Als Kontakt annehmen';

  @override
  String get requestAcceptBody =>
      'Benenne den Kontakt selbst. Der vom Absender gewählte Name wird nicht automatisch übernommen.';

  @override
  String get requestAcceptNameLabel => 'Kontaktname';

  @override
  String get requestNameEmpty => 'Gib einen Namen ein.';

  @override
  String get requestNameTaken =>
      'Ein anderer Kontakt heißt schon so (oder fast so). Wähle einen Namen, der nicht verwechselt werden kann.';

  @override
  String noticeIdentityChanged(String name) {
    return 'Der Sicherheitscode von $name hat sich geändert. Unter dieser Adresse meldet sich ein anderer Schlüssel: neues Telefon, Neuinstallation oder Fälschung. Die Verifizierung wurde aufgehoben. Vergleicht den Code erneut, bevor du etwas Sensibles sendest.';
  }

  @override
  String noticeLookalikeRequest(String claimed, String name) {
    return 'Ein unbekannter Absender nennt sich „$claimed“, was nach deinem Kontakt $name aussieht. Es ist nicht dieser Kontakt, die Nachricht kam von einem anderen Schlüssel. Du findest sie in den Chats als Nachrichtenanfrage.';
  }

  @override
  String get noticeVerifyAction => 'Code prüfen';

  @override
  String get noticePreview => 'Sicherheitshinweis';
}
