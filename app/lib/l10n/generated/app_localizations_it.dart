// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Šepot';

  @override
  String get settingsLanguage => 'Lingua dell\'app';

  @override
  String get languageSystem => 'Predefinita di sistema';

  @override
  String get commonUnknownContact => 'Sconosciuto';

  @override
  String get verifyVerified => 'Verificato';

  @override
  String get verifyUnverified => 'Non verificato';

  @override
  String get chatMenuVerifyContact => 'Verifica contatto';

  @override
  String get chatDisappearingMessages => 'Messaggi a scomparsa';

  @override
  String get chatMenuUnblockContact => 'Sblocca contatto';

  @override
  String get chatMenuBlockContact => 'Blocca contatto';

  @override
  String get reportAndBlock => 'Segnala e blocca';

  @override
  String errorGeneric(String error) {
    return 'Errore: $error';
  }

  @override
  String get groupsYouLeftGroup => 'Non sei più nel gruppo';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membri',
      one: '1 membro',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembers => 'Membri';

  @override
  String get groupsRename => 'Rinomina gruppo';

  @override
  String get groupsLeave => 'Abbandona il gruppo';

  @override
  String get groupsLeftBanner =>
      'Non sei più nel gruppo. La cronologia resta, i nuovi messaggi non arriveranno.';

  @override
  String groupsMembersWithCount(int count) {
    return 'Membri ($count)';
  }

  @override
  String get groupsYou => 'Tu';

  @override
  String get groupsFounder => 'Fondatore';

  @override
  String get groupsNameHint => 'Nome del gruppo';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonSave => 'Salva';

  @override
  String groupsRenameFailed(String error) {
    return 'Rinomina non riuscita: $error';
  }

  @override
  String get groupsLeaveConfirmTitle => 'Abbandonare il gruppo?';

  @override
  String get groupsLeaveConfirmBody =>
      'Gli altri vedranno che non sei più nel gruppo. La cronologia ti resterà, ma non riceverai più nuovi messaggi e per rientrare qualcuno dovrà invitarti.';

  @override
  String get groupsLeaveAction => 'Abbandona';

  @override
  String groupsLeaveFailed(String error) {
    return 'Uscita non riuscita: $error';
  }

  @override
  String get chatBlockedBanner =>
      'Il contatto è bloccato. Non ricevi i suoi messaggi e non puoi scrivergli.';

  @override
  String get chatUnblock => 'Sblocca';

  @override
  String chatContactBlocked(String name) {
    return 'Contatto $name bloccato';
  }

  @override
  String chatContactUnblocked(String name) {
    return 'Contatto $name sbloccato';
  }

  @override
  String reportAndBlockBody(String name) {
    return 'Bloccheremo il contatto $name e smetterai di ricevere i suoi messaggi. Poi ti proporremo un modulo per farci sapere cosa è successo — non vediamo il contenuto dei messaggi, quindi senza la tua descrizione non ne sappiamo nulla.';
  }

  @override
  String get chatEmptyEncrypted => 'I messaggi sono cifrati end-to-end.';

  @override
  String get chatEmptyNoOneElse => 'Nessun altro può leggerli.';

  @override
  String get commonToday => 'Oggi';

  @override
  String get commonYesterday => 'Ieri';

  @override
  String get chatMessageHint => 'Scrivi un messaggio…';

  @override
  String get chatDiscardRecording => 'Scarta';

  @override
  String get chatRecording => 'Registrazione…';

  @override
  String get chatMicPermissionMissing =>
      'Manca l\'autorizzazione per il microfono';

  @override
  String chatRecordingFailed(String error) {
    return 'Registrazione non riuscita: $error';
  }

  @override
  String chatVoiceSendFailed(String error) {
    return 'Invio del messaggio vocale non riuscito: $error';
  }

  @override
  String get chatDeletedMessagePreview => 'Messaggio eliminato';

  @override
  String get chatVoiceMessagePreview => '🎤 Messaggio vocale';

  @override
  String get chatPhotoPreview => '📷 Foto';

  @override
  String get chatAttachmentPreview => '📎 Allegato';

  @override
  String get chatEditingMessage => 'Modifica messaggio';

  @override
  String get chatReply => 'Risposta';

  @override
  String get chatActionReply => 'Rispondi';

  @override
  String get commonCopy => 'Copia';

  @override
  String get commonEdit => 'Modifica';

  @override
  String get chatDeleteForMe => 'Elimina per me';

  @override
  String get chatDeleteForEveryone => 'Elimina per tutti';

  @override
  String get commonOff => 'Disattivato';

  @override
  String get chatDisappearing30s => '30 secondi';

  @override
  String get chatDisappearing5m => '5 minuti';

  @override
  String get chatDisappearing1h => '1 ora';

  @override
  String get chatDisappearing1d => '1 giorno';

  @override
  String get chatDisappearing1w => '1 settimana';

  @override
  String get chatDisappearingDescription =>
      'I nuovi messaggi verranno eliminati allo scadere del tempo, sia per te che per l\'altra persona.';

  @override
  String get chatDisappearingDisabled => 'Messaggi a scomparsa disattivati';

  @override
  String chatDisappearingEnabled(String duration) {
    return 'I nuovi messaggi scompariranno dopo: $duration';
  }

  @override
  String get attachmentGallery => 'Foto dalla galleria';

  @override
  String get attachmentTakePhoto => 'Scatta foto';

  @override
  String get attachmentDocument => 'Documento';

  @override
  String attachmentTooLarge(int maxMb) {
    return 'Il file è troppo grande (max $maxMb MB)';
  }

  @override
  String attachmentPickFailed(String error) {
    return 'Selezione dell\'allegato non riuscita: $error';
  }

  @override
  String attachmentSendFailed(String error) {
    return 'Invio dell\'allegato non riuscito: $error';
  }

  @override
  String chatSendFailed(String error) {
    return 'Invio non riuscito: $error';
  }

  @override
  String get chatMessageDeleted => 'Messaggio eliminato';

  @override
  String get chatEdited => 'modificato';

  @override
  String get errorTrustRootChanged =>
      'Il trust root del relay è cambiato! Comunicazione rifiutata.';

  @override
  String get errorRelayUnavailable =>
      'Relay non disponibile (sender certificate)';

  @override
  String get errorNotYetRegistered =>
      'Šepot si sta ancora connettendo al relay — riprova a inviare tra un istante.';

  @override
  String get errorContactLinkIncomplete =>
      'Questo link è incompleto — l\'altra persona l\'ha creato prima di connettersi. Chiedile un nuovo link sepot://.';

  @override
  String errorAttachmentTooLarge(int maxMb) {
    return 'L\'allegato è troppo grande (max $maxMb MB)';
  }

  @override
  String get errorGroupNeedsMember => 'Il gruppo ha bisogno di almeno 1 membro';

  @override
  String errorGroupMaxMembers(int maxMembers) {
    return 'Il gruppo può avere al massimo $maxMembers membri';
  }

  @override
  String errorMemberNoDeliveryAddress(String displayName) {
    return '$displayName non ha un indirizzo di consegna — chiedi un nuovo link';
  }

  @override
  String get errorContactNoDeliveryAddress =>
      'Il contatto non ha un indirizzo di consegna — chiedigli un nuovo link sepot://';

  @override
  String get errorIdentityKeyMismatch =>
      'La chiave di identità dal relay NON corrisponde al contatto — possibile MITM! Messaggio non inviato.';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsSectionGeneral => 'Generali';

  @override
  String get settingsSectionSecurity => 'Sicurezza';

  @override
  String get settingsChangePinTitle => 'Cambia PIN';

  @override
  String get settingsChangePinSubtitle => 'PIN a 6 cifre per sbloccare';

  @override
  String get settingsAutoLockTitle => 'Blocco automatico';

  @override
  String get settingsAutoLock5min => 'Dopo 5 minuti';

  @override
  String get settingsDecoyPinTitle => 'PIN anti-coercizione';

  @override
  String get settingsDecoyPinSetSubtitle => 'Impostato — apre un\'app vuota';

  @override
  String get settingsDecoyPinUnsetSubtitle =>
      'Un secondo PIN che apre un\'app vuota';

  @override
  String get settingsSectionNotifications => 'Notifiche';

  @override
  String get settingsSectionConnection => 'Connessione';

  @override
  String get settingsSectionPrivacy => 'Privacy';

  @override
  String get settingsReadReceiptsTitle => 'Conferme di lettura';

  @override
  String get settingsReadReceiptsSubtitle =>
      'Mostra all\'altra persona quando leggi i messaggi (disattivato di default)';

  @override
  String get settingsScreenSecurityTitle => 'Sicurezza dello schermo';

  @override
  String get settingsScreenSecuritySubtitle =>
      'Blocca gli screenshot e nasconde il contenuto nelle app recenti';

  @override
  String get settingsSectionBackup => 'Backup delle chiavi';

  @override
  String get settingsSeedPhraseTitle => 'Frase di recupero';

  @override
  String get settingsSeedPhraseSubtitle =>
      '24 parole per ripristinare l\'identità';

  @override
  String get settingsBackupExportTitle => 'Backup della cronologia';

  @override
  String get settingsBackupExportSubtitle =>
      'File cifrato con contatti e messaggi';

  @override
  String get settingsBackupImportTitle => 'Ripristina da backup';

  @override
  String get settingsBackupImportSubtitle =>
      'Carica un backup (solo con la tua identità)';

  @override
  String get settingsSectionSafety => 'Protezione';

  @override
  String get settingsReportAbuseTitle => 'Segnala un abuso';

  @override
  String get settingsReportAbuseSubtitle =>
      'Molestie, truffe, minori in pericolo';

  @override
  String get settingsChildSafetyTitle => 'Standard di tutela dei minori';

  @override
  String get settingsChildSafetySubtitle =>
      'Come agiamo contro gli abusi sui minori';

  @override
  String get settingsSectionAbout => 'Informazioni';

  @override
  String get commonAppName => 'Šepot';

  @override
  String settingsVersion(String version) {
    return 'Versione $version';
  }

  @override
  String get settingsLicenseTitle => 'Licenza';

  @override
  String get settingsLicenseSubtitle => 'AGPL-3.0';

  @override
  String get settingsPrivacyPolicyTitle => 'Informativa sulla privacy';

  @override
  String get settingsPrivacyPolicySubtitle => 'Cosa sappiamo di te (e cosa no)';

  @override
  String get settingsTermsTitle => 'Termini di utilizzo';

  @override
  String get settingsTermsSubtitle => 'sepot.cz/podminky';

  @override
  String get settingsDataDeletionTitle => 'Eliminazione dei dati';

  @override
  String get settingsDataDeletionSubtitle => 'Come richiedere la cancellazione';

  @override
  String get settingsDeleteAllDataButton => 'Elimina tutti i dati';

  @override
  String settingsLicenseBody(String supportEmail) {
    return 'Šepot è distribuito sotto licenza GNU Affero General Public License versione 3 (AGPL-3.0). Usa la libreria libsignal, anch\'essa AGPL-3.0.\n\nPer ricevere il codice sorgente corrispondente a questa versione scrivi a $supportEmail e te lo invieremo.';
  }

  @override
  String get commonClose => 'Chiudi';

  @override
  String get settingsIdCopied => 'ID copiato';

  @override
  String settingsFingerprint(String fingerprint) {
    return 'Impronta: $fingerprint';
  }

  @override
  String get backupShareSubject => 'Šepot — backup cifrato';

  @override
  String backupExportFailed(String error) {
    return 'Backup non riuscito: $error';
  }

  @override
  String backupRestoredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ripristinate $count conversazioni dal backup',
      one: 'Ripristinata 1 conversazione dal backup',
    );
    return '$_temp0';
  }

  @override
  String backupImportFailed(String error) {
    return 'Ripristino dal backup non riuscito: $error';
  }

  @override
  String get settingsDecoyPinExplain =>
      'Inserendo questo PIN l\'app si apre vuota — senza i tuoi contatti e messaggi. Deve essere diverso dal PIN normale.';

  @override
  String get commonConfirm => 'Conferma';

  @override
  String get commonSet => 'Imposta';

  @override
  String get settingsDecoyPinEnabled => 'PIN anti-coercizione impostato';

  @override
  String get settingsDecoyPinConflict =>
      'Il PIN anti-coercizione deve essere diverso da quello normale';

  @override
  String get settingsDecoyPinDisabled => 'PIN anti-coercizione rimosso';

  @override
  String get settingsSeedPhraseNotFound => 'Frase di recupero non trovata';

  @override
  String get settingsSeedPhraseWarning =>
      'Queste parole sono l\'unico backup della tua identità. Non mostrarle a nessuno!';

  @override
  String settingsSeedWordChip(int index, String word) {
    return '$index. $word';
  }

  @override
  String get settingsAboutTagline => 'Šepot — Messenger privato';

  @override
  String get settingsAboutBody =>
      'Messenger cifrato E2E e open source.\n\nCrittografia:\n• X25519 (scambio di chiavi)\n• XChaCha20-Poly1305 (cifratura)\n• Ed25519 (firme)\n\n© 2026 ajtak.it';

  @override
  String get settingsDeleteAccountTitle =>
      'Eliminare l\'account e tutti i dati?';

  @override
  String get settingsDeleteAccountBody =>
      'Questa azione è irreversibile. Tutti i messaggi, i contatti e le chiavi verranno eliminati da questo dispositivo e l\'account verrà deregistrato dal server. Se non hai la frase di recupero, perderai la tua identità.';

  @override
  String get settingsDeleteAccountServerOffline =>
      'Il server al momento non è raggiungibile — i dati sul dispositivo sono stati eliminati, ma la registrazione sul server è rimasta. Scrivici a podpora@sepot.cz e cancelleremo il resto.';

  @override
  String get settingsDeleteAllConfirm => 'Elimina tutto';

  @override
  String groupsCreateFailed(String error) {
    return 'Impossibile creare il gruppo: $error';
  }

  @override
  String get groupsNewGroupTitle => 'Nuovo gruppo';

  @override
  String get groupsCreateAction => 'Crea';

  @override
  String groupsMembersCounter(int selectedCount, int maxMembers) {
    return 'Membri ($selectedCount/$maxMembers)';
  }

  @override
  String get groupsEmptyContactsHint =>
      'Prima aggiungi dei contatti — un gruppo è fatto di persone con cui puoi già scrivere.';

  @override
  String get groupsMemberMissingAddress =>
      'Manca l\'indirizzo di consegna — chiedi un nuovo link';

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
      'Download non riuscito — tocca per riprovare';

  @override
  String get attachmentDownloadFailed => 'Download non riuscito';

  @override
  String get attachmentDownloading => 'Download in corso…';

  @override
  String get attachmentSharedFileFallbackName => 'file';

  @override
  String attachmentOpenFailed(String error) {
    return 'Impossibile aprire l\'allegato: $error';
  }

  @override
  String get commonFile => 'File';

  @override
  String get chatListNewConversation => 'Nuova conversazione';

  @override
  String chatListPhotoWithCaptionPreview(String caption) {
    return '📷 $caption';
  }

  @override
  String chatListFilePreview(String fileName) {
    return '📎 $fileName';
  }

  @override
  String get chatListReadReceiptPreview => 'Letto';

  @override
  String get chatListTimeNow => 'adesso';

  @override
  String chatListTimeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get qrScanTitle => 'Scansiona codice QR';

  @override
  String get qrScanInstruction => 'Inquadra il codice QR del contatto';

  @override
  String get qrScanHint =>
      'Il codice QR contiene la chiave pubblica del contatto';

  @override
  String get qrNewContactTitle => 'Nuovo contatto';

  @override
  String qrContactAdded(String name) {
    return 'Contatto $name aggiunto';
  }

  @override
  String get commonAdd => 'Aggiungi';

  @override
  String get onboardingWelcomeTitle => 'Ti diamo il benvenuto in Šepot';

  @override
  String get onboardingWelcomeSubtitle =>
      'Un messenger privato con cifratura end-to-end.\nNessun numero di telefono. Nessuna email.\nSolo le tue chiavi.';

  @override
  String get onboardingStart => 'Inizia';

  @override
  String get onboardingRestoreExisting =>
      'Ho già un account — ripristina dalla frase di recupero';

  @override
  String get onboardingEncryptionTitle => 'I tuoi messaggi, le tue chiavi';

  @override
  String get onboardingFeatureSignalTitle => 'Protocollo Signal';

  @override
  String get onboardingFeatureSignalSubtitle =>
      'X3DH + Double Ratchet, forward secrecy';

  @override
  String get onboardingFeaturePqTitle => 'Protezione post-quantistica';

  @override
  String get onboardingFeaturePqSubtitle =>
      'Kyber (PQXDH) fin dal primo messaggio';

  @override
  String get onboardingFeatureLocalKeysTitle =>
      'Chiavi solo sul tuo dispositivo';

  @override
  String get onboardingFeatureLocalKeysSubtitle => 'Nessun server le possiede';

  @override
  String get onboardingFeatureDisappearingSubtitle =>
      'Si eliminano automaticamente';

  @override
  String get commonContinue => 'Continua';

  @override
  String get onboardingIdentityTitle => 'Crea la tua identità';

  @override
  String get onboardingIdentitySubtitle =>
      'Nessuna email né telefono. Solo un nome e chiavi crittografiche.';

  @override
  String get onboardingDisplayNameLabel => 'Nome visualizzato';

  @override
  String get onboardingDisplayNameHint => 'Es. Marco';

  @override
  String onboardingSeedPhraseWarning(int count) {
    return 'Annota queste $count parole. Sono l\'unico backup delle tue chiavi!';
  }

  @override
  String get onboardingSeedSavedConfirm =>
      'Confermo di aver salvato la frase in un luogo sicuro';

  @override
  String get onboardingGenerateKeys => 'Genera le chiavi';

  @override
  String get verifyMismatchTitle => 'I numeri NON corrispondono';

  @override
  String verifyMatchBody(String contactName) {
    return 'Le chiavi corrispondono. $contactName è un contatto verificato.';
  }

  @override
  String get verifyMismatchBody =>
      'I numeri di sicurezza non corrispondono. Qualcuno potrebbe intercettare la connessione (MITM), oppure stai scansionando il codice di un altro contatto. NON inviare messaggi sensibili e verificatevi di nuovo tramite un altro canale.';

  @override
  String get commonUnderstood => 'Ho capito';

  @override
  String get verifyManualConfirmTitle => 'Segnare come verificato?';

  @override
  String get verifyManualConfirmBody =>
      'Conferma solo se hai confrontato le cifre con l\'altra persona tramite un altro canale affidabile (di persona, con una chiamata…) e corrispondono.';

  @override
  String get verifyManualConfirmAction => 'Corrispondono, verifica';

  @override
  String get verifyTitle => 'Verifica del contatto';

  @override
  String get verifyContactVerifiedBanner => 'Il contatto è verificato';

  @override
  String verifyIntro(String contactName) {
    return 'Confronta questo numero con $contactName. Se corrisponde, nessuno sta intercettando la vostra cifratura. Il modo più rapido è scansionare a vicenda i codici QR.';
  }

  @override
  String get verifyScanButton => 'Scansiona il codice dell\'altra persona';

  @override
  String get verifyManualButton => 'Le cifre corrispondono — segna manualmente';

  @override
  String get verifyUnverifyButton => 'Rimuovi verifica';

  @override
  String get verifyScanScreenTitle => 'Scansiona il QR di verifica';

  @override
  String get reportTitle => 'Segnala';

  @override
  String get reportSubmitted => 'Segnalazione inviata';

  @override
  String get reportSubmittedChildSafety =>
      'Diamo priorità a queste segnalazioni. Se un minore è in pericolo immediato, chiama subito il 112 o il 114 (Emergenza Infanzia).';

  @override
  String get reportSubmittedThanks =>
      'Grazie. L\'esamineremo il prima possibile.';

  @override
  String get commonDone => 'Fatto';

  @override
  String get reportPanelE2eNotice =>
      'I messaggi sono cifrati end-to-end, quindi non possiamo vederne il contenuto nemmeno ora. Descrivi con parole tue cosa è successo. Non incollare qui il contenuto dei messaggi né link ad esso — non possiamo conservarlo e non ci serve per la valutazione.';

  @override
  String get reportPanelCsamWarning =>
      'NON inviarci materiale che mostra abusi su minori. Detenerlo è un reato anche per noi e non ci serve per la segnalazione. Il materiale va segnalato direttamente alla polizia o a una hotline dedicata alla protezione dei minori. Scrivici solo cosa è successo — bloccheremo l\'account e inoltreremo il caso.';

  @override
  String get reportPanelIpNotice =>
      'La segnalazione non passa dal relay ma dal nostro server web, che al momento dell\'invio vedrà il tuo indirizzo IP.';

  @override
  String get reportCategoryHeading => 'Oggetto della segnalazione';

  @override
  String get reportDescriptionHeading => 'Cosa è successo';

  @override
  String get reportAttachContactId => 'Allega l\'ID del contatto segnalato';

  @override
  String reportAttachContactIdNamed(String contactName) {
    return 'Allega l\'ID del contatto $contactName';
  }

  @override
  String get reportReplyToHeading => 'Come contattarti (facoltativo)';

  @override
  String get reportReplyToHint =>
      'email, nel caso avessimo bisogno di chiarimenti';

  @override
  String get reportSubmitButton => 'Invia segnalazione';

  @override
  String get contactsTitle => 'Contatti';

  @override
  String get contactsAddContact => 'Aggiungi contatto';

  @override
  String get contactsSearchHint => 'Cerca un contatto...';

  @override
  String get contactsEmpty => 'Ancora nessun contatto';

  @override
  String get contactsNoResults => 'Nessun risultato';

  @override
  String get contactsShareCardTitle => 'Condividi il tuo Šepot ID';

  @override
  String get contactsShareCardSubtitle => 'Mostra il codice QR o invia un link';

  @override
  String get contactsAddDialogPrompt =>
      'Incolla la stringa di condivisione (share string) del contatto:';

  @override
  String get contactsShareStringHint => 'Incolla la share string...';

  @override
  String get contactsInvalidShareString => 'Share string non valida';

  @override
  String contactsAdded(String name) {
    return 'Contatto $name aggiunto';
  }

  @override
  String get verifyContactSubtitle => 'Confronto del numero di sicurezza';

  @override
  String get contactsDeleteContact => 'Elimina contatto';

  @override
  String get pinConfirmTitle => 'Conferma il PIN';

  @override
  String get pinSetupTitle => 'Imposta il tuo PIN';

  @override
  String get pinConfirmSubtitle => 'Inserisci di nuovo il PIN per confermare';

  @override
  String get pinSetupSubtitle => 'PIN a 6 cifre per sbloccare l\'app';

  @override
  String get pinSetupFailed => 'Impostazione del PIN non riuscita. Riprova.';

  @override
  String get pinMismatchRetry => 'I PIN non corrispondono. Riprova.';

  @override
  String get pinChangeCurrentTitle => 'Inserisci il PIN attuale';

  @override
  String get pinChangeCurrentSubtitle => 'Lo verifichiamo sbloccando la chiave';

  @override
  String get pinChangeNewTitle => 'Inserisci il nuovo PIN';

  @override
  String get pinChangeNewSubtitle => '6 cifre';

  @override
  String get pinChangeConfirmTitle => 'Conferma il nuovo PIN';

  @override
  String get pinChangeConfirmSubtitle => 'Inseriscilo ancora una volta';

  @override
  String get pinWrong => 'PIN errato.';

  @override
  String get pinChangeMustDiffer =>
      'Il nuovo PIN deve essere diverso da quello attuale.';

  @override
  String get pinMismatch => 'I PIN non corrispondono.';

  @override
  String get pinDecoyConflict =>
      'Questo PIN appartiene già alla modalità anti-coercizione. Scegline un altro.';

  @override
  String get pinChangeFailed => 'Cambio del PIN non riuscito. Riprova.';

  @override
  String get pinChanged => 'PIN cambiato';

  @override
  String get errorCryptoInitTitle => 'Il motore di cifratura non si è avviato';

  @override
  String get errorStartupTitle => 'Šepot non si è avviato';

  @override
  String get errorScreenNotRenderedTitle =>
      'Questa schermata non è stata visualizzata';

  @override
  String get errorStartupBody =>
      'Qualcosa è andato storto subito all\'avvio. Inviami questo testo, per favore (tieni premuto e copia) — mi aiuterà a trovare l\'errore.';

  @override
  String get errorContactFooter => 'sepot.cz · contattami';

  @override
  String get pinUnlockTitle => 'Sblocca Šepot';

  @override
  String get pinEnterPin => 'Inserisci il PIN';

  @override
  String get pinUnlockWithBiometrics => 'Sblocca con biometria';

  @override
  String get pinWrong2 => 'PIN errato';

  @override
  String get pinUnlockError => 'Errore di sblocco';

  @override
  String get pushTitle => 'Notifiche push';

  @override
  String get pushModeOffDesc =>
      'I messaggi verranno scaricati solo all\'apertura dell\'app.';

  @override
  String get pushModeUp => 'UnifiedPush (consigliato)';

  @override
  String get pushModeUpDesc =>
      'Senza Google — richiede l\'app ntfy (F-Droid/Play).';

  @override
  String get pushModeFcm => 'Google (FCM)';

  @override
  String get pushModeFcmDesc =>
      'Affidabile senza altre app. Il token push del dispositivo va a Google; il contenuto dei messaggi mai.';

  @override
  String pushSetupFailed(String error) {
    return 'Configurazione delle notifiche push non riuscita: $error';
  }

  @override
  String get pushNoDistributorTitle => 'Nessun distributore';

  @override
  String get pushNoDistributorBody =>
      'Per notifiche senza Google installa un distributore UnifiedPush, ad es. ntfy (F-Droid o Play). Poi riattiva le notifiche push.';

  @override
  String get commonOk => 'OK';

  @override
  String get pushPickDistributorTitle => 'Scegli il distributore';

  @override
  String pushSubtitleUnifiedPush(String distributor) {
    return 'UnifiedPush · $distributor';
  }

  @override
  String get pushNoDistributorFallback => 'nessun distributore';

  @override
  String get pushSubtitleFcm => 'Google (FCM) — veloce, opt-in';

  @override
  String get restoreErrorNameRequired => 'Inserisci il nome visualizzato.';

  @override
  String restoreErrorWordCount(int wordCount, int requiredWords) {
    String _temp0 = intl.Intl.pluralLogic(
      wordCount,
      locale: localeName,
      other: 'La frase ha $wordCount parole, ne servono $requiredWords.',
      one: 'La frase ha 1 parola, ne servono $requiredWords.',
    );
    return '$_temp0';
  }

  @override
  String get restoreErrorInvalidPhrase =>
      'La frase non è valida — controlla le parole e il loro ordine.';

  @override
  String restoreErrorFailed(String error) {
    return 'Ripristino non riuscito: $error';
  }

  @override
  String get restoreTitle => 'Ripristina account';

  @override
  String get restoreHeading => 'Inserisci la tua frase di recupero';

  @override
  String restoreIntro(int wordCount) {
    return '$wordCount parole, dal backup fatto quando hai creato l\'account. Ripristina la tua identità (stesso codice SEP, i contatti continueranno a riconoscerti).';
  }

  @override
  String get restoreHistoryWarning =>
      'La cronologia dei messaggi non verrà ripristinata — è salvata solo sul dispositivo originale.';

  @override
  String get restorePhraseHint => 'parola1 parola2 parola3 …';

  @override
  String restoreWordCountHelper(int wordCount, int requiredWords) {
    return '$wordCount / $requiredWords parole';
  }

  @override
  String chatListArchivedCount(int count) {
    return 'Archiviate ($count)';
  }

  @override
  String get chatListEmptyTitle => 'Ancora nessuna conversazione';

  @override
  String get chatListEmptySubtitle =>
      'Aggiungi un contatto e inizia a sussurrare!';

  @override
  String get chatListUnmute => 'Riattiva notifiche';

  @override
  String get chatListMute => 'Silenzia';

  @override
  String get chatListArchive => 'Archivia';

  @override
  String get qrShareTitle => 'Il mio Šepot ID';

  @override
  String get qrShareConnectingTitle => 'Connessione al relay…';

  @override
  String get qrShareConnectingBody =>
      'Il tuo codice QR e il link appariranno appena Šepot si connette per la prima volta. Un istante — bastano pochi secondi.';

  @override
  String get qrIdentityNotFound => 'Identità non trovata';

  @override
  String get commonCopiedToClipboard => 'Copiato negli appunti';

  @override
  String qrShareInviteMessage(String shareString) {
    return 'Aggiungimi su Šepot!\n\n$shareString';
  }

  @override
  String get commonShare => 'Condividi';

  @override
  String get qrShareInfo =>
      'Il contatto scansiona il tuo codice QR o incolla la stringa di condivisione nell\'app.';

  @override
  String get reportCategoryChildSafety => 'Minore in pericolo';

  @override
  String get reportCategoryChildSafetyHint =>
      'Descrivi la situazione con parole tue. Non incollare il contenuto dei messaggi né link al materiale.';

  @override
  String get reportCategoryHarassment => 'Molestie o minacce';

  @override
  String get reportCategoryHarassmentHint =>
      'Qualcuno ti intimidisce, ti minaccia o ti molesta.';

  @override
  String get reportCategorySpam => 'Spam';

  @override
  String get reportCategorySpamHint => 'Messaggi indesiderati, invii di massa.';

  @override
  String get reportCategoryFraud => 'Truffa';

  @override
  String get reportCategoryFraudHint =>
      'Un tentativo di ottenere con l\'inganno denaro, chiavi o dati personali.';

  @override
  String get reportCategoryOther => 'Altro';

  @override
  String get reportCategoryOtherHint => 'Qualcos\'altro che dovremmo sapere.';

  @override
  String get reportErrorEmptyDescription =>
      'Scrivi cosa è successo, per favore.';

  @override
  String reportErrorConnection(String supportEmail) {
    return 'Impossibile contattare il server. Riprova, oppure scrivi a $supportEmail.';
  }

  @override
  String reportErrorRateLimited(String supportEmail) {
    return 'Troppe segnalazioni dalla tua rete. Riprova tra un\'ora, oppure scrivi a $supportEmail.';
  }

  @override
  String reportErrorServer(int statusCode, String supportEmail) {
    return 'Invio non riuscito (codice $statusCode). Scrivi a $supportEmail, per favore.';
  }

  @override
  String get settingsAutoLockNever => 'Mai';

  @override
  String get settingsAutoLock1min => 'Dopo 1 minuto';

  @override
  String get settingsAutoLock15min => 'Dopo 15 minuti';

  @override
  String torToggleFailed(String error) {
    return 'Impossibile cambiare lo stato di Tor: $error';
  }

  @override
  String get torConnectionTitle => 'Connessione via Tor';

  @override
  String get torDialogBody =>
      'Il traffico verso il server passerà dalla rete Tor (nasconde il tuo indirizzo IP). Richiede l\'app Orbot installata e in esecuzione, con proxy SOCKS attivo sulla porta 9050.\n\nSenza Orbot in esecuzione i messaggi non vengono né inviati né ricevuti. La connessione tende a essere più lenta.';

  @override
  String get commonTurnOn => 'Attiva';

  @override
  String get torSubtitleOff =>
      'Connessione cifrata diretta (WSS). Attiva per nascondere l\'IP via Tor.';

  @override
  String get torStatusConnected => 'Connesso via Tor (.onion).';

  @override
  String get torStatusConnecting =>
      'Connessione via Tor… (Orbot è in esecuzione?)';

  @override
  String get torStatusWaiting => 'Via Tor — in attesa di Orbot (SOCKS 9050).';

  @override
  String get biometricsPinRequiredFirst =>
      'Prima imposta un PIN — la biometria è solo un complemento.';

  @override
  String get biometricsStorageLocked =>
      'La memoria protetta è bloccata — sblocca l\'app con il PIN.';

  @override
  String get biometricsNotAvailable =>
      'Il dispositivo non ha la biometria configurata.';

  @override
  String get biometricsEnrollPromptReason =>
      'Conferma l\'attivazione dello sblocco biometrico';

  @override
  String biometricsSetupFailed(String error) {
    return 'Impossibile configurare la biometria: $error';
  }

  @override
  String get biometricsTileTitle => 'Biometria';

  @override
  String get biometricsTileSubtitle =>
      'Sblocco con impronta / volto (il PIN resta di riserva)';

  @override
  String get backupErrorCorruptedFile => 'File di backup danneggiato';

  @override
  String get backupErrorUnknownFormat => 'Formato di backup non riconosciuto';

  @override
  String get backupErrorWrongIdentity =>
      'Impossibile decifrare il backup — appartiene a un\'altra identità?';

  @override
  String attachmentSharedImageFilename(String ext) {
    return 'sepot-immagine.$ext';
  }

  @override
  String get attachmentDecryptFailed => 'Impossibile decifrare l\'allegato';

  @override
  String get pushActionOpen => 'Apri';

  @override
  String get pushChannelMessagesName => 'Messaggi';

  @override
  String get pushChannelMessagesDescription =>
      'Avvisi per i nuovi messaggi (senza contenuto)';

  @override
  String pushNewMessageFrom(String senderName) {
    return 'Nuovo messaggio da $senderName';
  }

  @override
  String get pushNewMessages => 'Hai nuovi messaggi';

  @override
  String get archiveTitle => 'Archiviate';

  @override
  String get archiveEmpty => 'Nessuna conversazione archiviata';

  @override
  String get archiveUnarchive => 'Rimuovi dall\'archivio';

  @override
  String restoreErrorMnemonicWordCount(int count, int expected) {
    return 'La frase ha $count parole, ne servono $expected';
  }

  @override
  String restoreErrorInvalidMnemonic(String message) {
    return 'Frase non valida: $message';
  }

  @override
  String get contactsErrorAlreadyExists => 'Il contatto esiste già';

  @override
  String get commonAppTagline => 'Messenger privato';

  @override
  String get commonE2eBadgeCompact => 'E2E';

  @override
  String get commonE2eBadgeFull => 'Cifrato end-to-end';

  @override
  String get photoPreviewCaptionHint => 'Aggiungi una didascalia…';

  @override
  String get photoPreviewDraw => 'Disegna';

  @override
  String get photoPreviewAddText => 'Aggiungi testo';

  @override
  String get photoPreviewRotate => 'Ruota';

  @override
  String get photoPreviewUndo => 'Annulla';

  @override
  String get photoPreviewSend => 'Invia';

  @override
  String get photoPreviewTextDialogTitle => 'Testo sulla foto';

  @override
  String get photoPreviewRemoveText => 'Rimuovi';

  @override
  String get photoPreviewDecodeFailed => 'Impossibile caricare la foto';
}
