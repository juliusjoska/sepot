// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class AppLocalizationsCs extends AppLocalizations {
  AppLocalizationsCs([String locale = 'cs']) : super(locale);

  @override
  String get appTitle => 'Šepot';

  @override
  String get settingsLanguage => 'Jazyk aplikace';

  @override
  String get languageSystem => 'Podle systému';

  @override
  String get commonUnknownContact => 'Neznámý';

  @override
  String get verifyVerified => 'Ověřeno';

  @override
  String get verifyUnverified => 'Neověřeno';

  @override
  String get chatMenuVerifyContact => 'Ověřit kontakt';

  @override
  String get chatDisappearingMessages => 'Mizící zprávy';

  @override
  String get chatMenuUnblockContact => 'Odblokovat kontakt';

  @override
  String get chatMenuBlockContact => 'Blokovat kontakt';

  @override
  String get reportAndBlock => 'Nahlásit a zablokovat';

  @override
  String errorGeneric(String error) {
    return 'Chyba: $error';
  }

  @override
  String get groupsYouLeftGroup => 'Už nejsi ve skupině';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count členů',
      many: '$count člena',
      few: '$count členové',
      one: '1 člen',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembers => 'Členové';

  @override
  String get groupsRename => 'Přejmenovat skupinu';

  @override
  String get groupsLeave => 'Opustit skupinu';

  @override
  String get groupsLeftBanner =>
      'Už nejsi ve skupině. Historie zůstává, nové zprávy nedorazí.';

  @override
  String groupsMembersWithCount(int count) {
    return 'Členové ($count)';
  }

  @override
  String get groupsYou => 'Ty';

  @override
  String get groupsFounder => 'Zakladatel';

  @override
  String get groupsNameHint => 'Název skupiny';

  @override
  String get commonCancel => 'Zrušit';

  @override
  String get commonSave => 'Uložit';

  @override
  String groupsRenameFailed(String error) {
    return 'Přejmenování selhalo: $error';
  }

  @override
  String get groupsLeaveConfirmTitle => 'Opustit skupinu?';

  @override
  String get groupsLeaveConfirmBody =>
      'Ostatní uvidí, že už ve skupině nejsi. Historie ti zůstane, ale nové zprávy už nedostaneš a zpět tě musí někdo pozvat.';

  @override
  String get groupsLeaveAction => 'Opustit';

  @override
  String groupsLeaveFailed(String error) {
    return 'Odchod selhal: $error';
  }

  @override
  String get chatBlockedBanner =>
      'Kontakt je zablokovaný. Nedostáváš od něj zprávy a nemůžeš mu psát.';

  @override
  String get chatUnblock => 'Odblokovat';

  @override
  String chatContactBlocked(String name) {
    return 'Kontakt $name je zablokovaný';
  }

  @override
  String chatContactUnblocked(String name) {
    return 'Kontakt $name je odblokovaný';
  }

  @override
  String reportAndBlockBody(String name) {
    return 'Kontakt $name zablokujeme a přestaneš od něj dostávat zprávy. Pak ti nabídneme formulář, kterým nám dáš vědět, co se stalo — obsah zpráv nevidíme, takže bez tvého popisu o tom nevíme.';
  }

  @override
  String get chatEmptyEncrypted => 'Zprávy jsou end-to-end šifrované.';

  @override
  String get chatEmptyNoOneElse => 'Nikdo jiný je nemůže číst.';

  @override
  String get commonToday => 'Dnes';

  @override
  String get commonYesterday => 'Včera';

  @override
  String get chatMessageHint => 'Napiš zprávu…';

  @override
  String get chatDiscardRecording => 'Zahodit';

  @override
  String get chatRecording => 'Nahrávám…';

  @override
  String get chatMicPermissionMissing => 'Chybí oprávnění k mikrofonu';

  @override
  String chatRecordingFailed(String error) {
    return 'Nahrávání selhalo: $error';
  }

  @override
  String chatVoiceSendFailed(String error) {
    return 'Odeslání hlasové zprávy selhalo: $error';
  }

  @override
  String get chatDeletedMessagePreview => 'Smazaná zpráva';

  @override
  String get chatVoiceMessagePreview => '🎤 Hlasová zpráva';

  @override
  String get chatPhotoPreview => '📷 Fotka';

  @override
  String get chatAttachmentPreview => '📎 Příloha';

  @override
  String get chatEditingMessage => 'Úprava zprávy';

  @override
  String get chatReply => 'Odpověď';

  @override
  String get chatActionReply => 'Odpovědět';

  @override
  String get commonCopy => 'Kopírovat';

  @override
  String get commonEdit => 'Upravit';

  @override
  String get chatDeleteForMe => 'Smazat u mě';

  @override
  String get chatDeleteForEveryone => 'Smazat pro všechny';

  @override
  String get commonOff => 'Vypnuto';

  @override
  String get chatDisappearing30s => '30 sekund';

  @override
  String get chatDisappearing5m => '5 minut';

  @override
  String get chatDisappearing1h => '1 hodina';

  @override
  String get chatDisappearing1d => '1 den';

  @override
  String get chatDisappearing1w => '1 týden';

  @override
  String get chatDisappearingDescription =>
      'Nové zprávy se po uplynutí doby smažou u tebe i u protistrany.';

  @override
  String get chatDisappearingDisabled => 'Mizící zprávy vypnuty';

  @override
  String chatDisappearingEnabled(String duration) {
    return 'Nové zprávy zmizí po: $duration';
  }

  @override
  String get attachmentGallery => 'Fotka z galerie';

  @override
  String get attachmentTakePhoto => 'Vyfotit';

  @override
  String get attachmentDocument => 'Dokument';

  @override
  String attachmentTooLarge(int maxMb) {
    return 'Soubor je příliš velký (max $maxMb MB)';
  }

  @override
  String attachmentPickFailed(String error) {
    return 'Výběr přílohy selhal: $error';
  }

  @override
  String attachmentSendFailed(String error) {
    return 'Odeslání přílohy selhalo: $error';
  }

  @override
  String chatSendFailed(String error) {
    return 'Odeslání selhalo: $error';
  }

  @override
  String get chatMessageDeleted => 'Zpráva smazána';

  @override
  String get chatEdited => 'upraveno';

  @override
  String get errorTrustRootChanged =>
      'Trust root relaye se změnil! Odmítám komunikovat.';

  @override
  String get errorRelayUnavailable => 'Relay nedostupný (sender certificate)';

  @override
  String get errorNotYetRegistered =>
      'Šepot se ještě připojuje k relayi — zkus zprávu poslat za chvíli.';

  @override
  String get errorContactLinkIncomplete =>
      'Odkaz je neúplný — protistrana ho vytvořila dřív, než se stihla připojit. Požádej ji o nový sepot:// odkaz.';

  @override
  String errorAttachmentTooLarge(int maxMb) {
    return 'Příloha je příliš velká (max $maxMb MB)';
  }

  @override
  String get errorGroupNeedsMember => 'Skupina potřebuje aspoň 1 člena';

  @override
  String errorGroupMaxMembers(int maxMembers) {
    return 'Skupina může mít nejvýš $maxMembers členů';
  }

  @override
  String errorMemberNoDeliveryAddress(String displayName) {
    return '$displayName nemá doručovací adresu — požádej o nový odkaz';
  }

  @override
  String get errorContactNoDeliveryAddress =>
      'Kontakt nemá doručovací adresu — požádej ho o nový sepot:// odkaz';

  @override
  String get errorIdentityKeyMismatch =>
      'Identity klíč z relaye NESEDÍ s kontaktem — možný MITM! Zpráva neodeslána.';

  @override
  String get settingsTitle => 'Nastavení';

  @override
  String get settingsSectionGeneral => 'Obecné';

  @override
  String get settingsSectionSecurity => 'Zabezpečení';

  @override
  String get settingsChangePinTitle => 'Změnit PIN';

  @override
  String get settingsChangePinSubtitle => '6místný PIN pro odemknutí';

  @override
  String get settingsAutoLockTitle => 'Automatický zámek';

  @override
  String get settingsAutoLock5min => 'Po 5 minutách';

  @override
  String get settingsDecoyPinTitle => 'Nátlakový PIN';

  @override
  String get settingsDecoyPinSetSubtitle =>
      'Nastaven — otevře prázdnou aplikaci';

  @override
  String get settingsDecoyPinUnsetSubtitle =>
      'Druhý PIN, který otevře prázdnou aplikaci';

  @override
  String get settingsSectionNotifications => 'Notifikace';

  @override
  String get settingsSectionConnection => 'Připojení';

  @override
  String get settingsSectionPrivacy => 'Soukromí';

  @override
  String get settingsReadReceiptsTitle => 'Potvrzení přečtení';

  @override
  String get settingsReadReceiptsSubtitle =>
      'Ukazovat protistraně přečtení zpráv (výchozí vypnuto)';

  @override
  String get settingsScreenSecurityTitle => 'Zabezpečení obrazovky';

  @override
  String get settingsScreenSecuritySubtitle =>
      'Blokovat screenshoty a skrýt obsah v přepínači aplikací';

  @override
  String get settingsSectionBackup => 'Záloha klíčů';

  @override
  String get settingsSeedPhraseTitle => 'Zálohovací fráze';

  @override
  String get settingsSeedPhraseSubtitle => '24 slov pro obnovu identity';

  @override
  String get settingsBackupExportTitle => 'Zálohovat historii';

  @override
  String get settingsBackupExportSubtitle =>
      'Šifrovaný soubor s kontakty a zprávami';

  @override
  String get settingsBackupImportTitle => 'Obnovit ze zálohy';

  @override
  String get settingsBackupImportSubtitle =>
      'Načíst zálohu (jen s tvojí identitou)';

  @override
  String get settingsSectionSafety => 'Bezpečnost';

  @override
  String get settingsReportAbuseTitle => 'Nahlásit zneužití';

  @override
  String get settingsReportAbuseSubtitle =>
      'Obtěžování, podvod, ohrožení dítěte';

  @override
  String get settingsChildSafetyTitle => 'Standardy ochrany dětí';

  @override
  String get settingsChildSafetySubtitle =>
      'Jak postupujeme proti zneužívání dětí';

  @override
  String get settingsSectionAbout => 'O aplikaci';

  @override
  String get commonAppName => 'Šepot';

  @override
  String settingsVersion(String version) {
    return 'Verze $version';
  }

  @override
  String get settingsLicenseTitle => 'Licence';

  @override
  String get settingsLicenseSubtitle => 'AGPL-3.0';

  @override
  String get settingsPrivacyPolicyTitle => 'Zásady ochrany soukromí';

  @override
  String get settingsPrivacyPolicySubtitle => 'Co o tobě víme (a co ne)';

  @override
  String get settingsTermsTitle => 'Podmínky použití';

  @override
  String get settingsTermsSubtitle => 'sepot.cz/podminky';

  @override
  String get settingsDataDeletionTitle => 'Smazání dat';

  @override
  String get settingsDataDeletionSubtitle => 'Jak požádat o výmaz';

  @override
  String get settingsDeleteAllDataButton => 'Smazat všechna data';

  @override
  String settingsLicenseBody(String supportEmail) {
    return 'Šepot je šířen pod licencí GNU Affero General Public License verze 3 (AGPL-3.0). Používá knihovnu libsignal, rovněž AGPL-3.0.\n\nO zdrojový kód odpovídající této verzi si můžeš napsat na $supportEmail a pošleme ti ho.';
  }

  @override
  String get commonClose => 'Zavřít';

  @override
  String get settingsIdCopied => 'ID zkopírováno';

  @override
  String settingsFingerprint(String fingerprint) {
    return 'Otisk: $fingerprint';
  }

  @override
  String get backupShareSubject => 'Šepot — šifrovaná záloha';

  @override
  String backupExportFailed(String error) {
    return 'Záloha selhala: $error';
  }

  @override
  String backupRestoredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Obnoveno $count konverzací ze zálohy',
      many: 'Obnoveno $count konverzace ze zálohy',
      few: 'Obnoveny $count konverzace ze zálohy',
      one: 'Obnovena 1 konverzace ze zálohy',
    );
    return '$_temp0';
  }

  @override
  String backupImportFailed(String error) {
    return 'Obnova ze zálohy selhala: $error';
  }

  @override
  String get settingsDecoyPinExplain =>
      'Zadáním tohoto PINu se aplikace otevře prázdná — bez tvých kontaktů a zpráv. Musí být jiný než běžný PIN.';

  @override
  String get commonConfirm => 'Potvrdit';

  @override
  String get commonSet => 'Nastavit';

  @override
  String get settingsDecoyPinEnabled => 'Nátlakový PIN nastaven';

  @override
  String get settingsDecoyPinConflict =>
      'Nátlakový PIN musí být jiný než běžný';

  @override
  String get settingsDecoyPinDisabled => 'Nátlakový PIN zrušen';

  @override
  String get settingsSeedPhraseNotFound => 'Zálohovací fráze nebyla nalezena';

  @override
  String get settingsSeedPhraseWarning =>
      'Tato slova jsou jedinou zálohou tvé identity. Nikomu je neukazuj!';

  @override
  String settingsSeedWordChip(int index, String word) {
    return '$index. $word';
  }

  @override
  String get settingsAboutTagline => 'Šepot — Soukromý Messenger';

  @override
  String get settingsAboutBody =>
      'E2E šifrovaný messenger s otevřeným zdrojovým kódem.\n\nKryptografie:\n• X25519 (výměna klíčů)\n• XChaCha20-Poly1305 (šifrování)\n• Ed25519 (podpisy)\n\n© 2026 ajtak.it';

  @override
  String get settingsDeleteAccountTitle => 'Smazat účet a všechna data?';

  @override
  String get settingsDeleteAccountBody =>
      'Tato akce je nevratná. Všechny zprávy, kontakty a klíče budou smazány z tohoto zařízení a účet bude odregistrován ze serveru. Pokud nemáš zálohovací frázi, přijdeš o svou identitu.';

  @override
  String get settingsDeleteAccountServerOffline =>
      'Server je teď nedostupný — data v zařízení jsou smazaná, registrace na serveru zůstala. Zbytek smažeme na podpora@sepot.cz.';

  @override
  String get settingsDeleteAllConfirm => 'Smazat vše';

  @override
  String groupsCreateFailed(String error) {
    return 'Skupinu se nepovedlo založit: $error';
  }

  @override
  String get groupsNewGroupTitle => 'Nová skupina';

  @override
  String get groupsCreateAction => 'Založit';

  @override
  String groupsMembersCounter(int selectedCount, int maxMembers) {
    return 'Členové ($selectedCount/$maxMembers)';
  }

  @override
  String get groupsEmptyContactsHint =>
      'Nejdřív si přidej kontakty — skupina se skládá z lidí, se kterými si už můžeš psát.';

  @override
  String get groupsMemberMissingAddress =>
      'Chybí doručovací adresa — požádej o nový odkaz';

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
      'Stažení selhalo — klepni pro opakování';

  @override
  String get attachmentDownloadFailed => 'Stažení selhalo';

  @override
  String get attachmentDownloading => 'Stahuji…';

  @override
  String get attachmentSharedFileFallbackName => 'soubor';

  @override
  String attachmentOpenFailed(String error) {
    return 'Otevření přílohy selhalo: $error';
  }

  @override
  String get commonFile => 'Soubor';

  @override
  String get chatListNewConversation => 'Nová konverzace';

  @override
  String chatListPhotoWithCaptionPreview(String caption) {
    return '📷 $caption';
  }

  @override
  String chatListFilePreview(String fileName) {
    return '📎 $fileName';
  }

  @override
  String get chatListReadReceiptPreview => 'Přečteno';

  @override
  String get chatListTimeNow => 'teď';

  @override
  String chatListTimeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get qrScanTitle => 'Skenovat QR kód';

  @override
  String get qrScanInstruction => 'Namiř kameru na QR kód kontaktu';

  @override
  String get qrScanHint => 'QR kód obsahuje veřejný klíč kontaktu';

  @override
  String get qrNewContactTitle => 'Nový kontakt';

  @override
  String qrContactAdded(String name) {
    return '$name přidán/a';
  }

  @override
  String get commonAdd => 'Přidat';

  @override
  String get onboardingWelcomeTitle => 'Vítej v Šepotu';

  @override
  String get onboardingWelcomeSubtitle =>
      'Soukromý messenger s end-to-end šifrováním.\nŽádné telefonní číslo. Žádný email.\nJen tvoje klíče.';

  @override
  String get onboardingStart => 'Začít';

  @override
  String get onboardingRestoreExisting =>
      'Už mám účet — obnovit ze zálohovací fráze';

  @override
  String get onboardingEncryptionTitle => 'Tvoje zprávy, tvoje klíče';

  @override
  String get onboardingFeatureSignalTitle => 'Signal protokol';

  @override
  String get onboardingFeatureSignalSubtitle =>
      'X3DH + Double Ratchet, forward secrecy';

  @override
  String get onboardingFeaturePqTitle => 'Post-kvantová ochrana';

  @override
  String get onboardingFeaturePqSubtitle => 'Kyber (PQXDH) od první zprávy';

  @override
  String get onboardingFeatureLocalKeysTitle => 'Klíče jen na tvém zařízení';

  @override
  String get onboardingFeatureLocalKeysSubtitle => 'Žádný server je nemá';

  @override
  String get onboardingFeatureDisappearingSubtitle => 'Automaticky se smaží';

  @override
  String get commonContinue => 'Pokračovat';

  @override
  String get onboardingIdentityTitle => 'Vytvoř svoji identitu';

  @override
  String get onboardingIdentitySubtitle =>
      'Žádný email ani telefon. Jen jméno a kryptografické klíče.';

  @override
  String get onboardingDisplayNameLabel => 'Zobrazované jméno';

  @override
  String get onboardingDisplayNameHint => 'Např. Jan';

  @override
  String onboardingSeedPhraseWarning(int count) {
    return 'Zapiš si těchto $count slov. Jsou jedinou zálohou tvých klíčů!';
  }

  @override
  String get onboardingSeedSavedConfirm =>
      'Potvrzuji, že jsem si frázi bezpečně uložil/a';

  @override
  String get onboardingGenerateKeys => 'Vygenerovat klíče';

  @override
  String get verifyMismatchTitle => 'Čísla NESOUHLASÍ';

  @override
  String verifyMatchBody(String contactName) {
    return 'Klíče si odpovídají. $contactName je ověřený kontakt.';
  }

  @override
  String get verifyMismatchBody =>
      'Bezpečnostní čísla nesedí. Někdo může odposlouchávat spojení (MITM), nebo skenuješ kód jiného kontaktu. NEposílej citlivé zprávy a ověřte se znovu jiným kanálem.';

  @override
  String get commonUnderstood => 'Rozumím';

  @override
  String get verifyManualConfirmTitle => 'Označit jako ověřené?';

  @override
  String get verifyManualConfirmBody =>
      'Potvrď jen v případě, že sis číslice porovnal/a s protistranou jiným důvěryhodným kanálem (osobně, hovorem…) a souhlasí.';

  @override
  String get verifyManualConfirmAction => 'Souhlasí, ověřit';

  @override
  String get verifyTitle => 'Ověření kontaktu';

  @override
  String get verifyContactVerifiedBanner => 'Kontakt je ověřený';

  @override
  String verifyIntro(String contactName) {
    return 'Porovnej toto číslo s $contactName. Když souhlasí, vaše šifrování nikdo neodposlouchává. Nejrychlejší je vzájemně si naskenovat QR kódy.';
  }

  @override
  String get verifyScanButton => 'Naskenovat kód protistrany';

  @override
  String get verifyManualButton => 'Číslice souhlasí — označit ručně';

  @override
  String get verifyUnverifyButton => 'Zrušit ověření';

  @override
  String get verifyScanScreenTitle => 'Naskenuj ověřovací QR';

  @override
  String get reportTitle => 'Nahlásit';

  @override
  String get reportSubmitted => 'Hlášení odesláno';

  @override
  String get reportSubmittedChildSafety =>
      'Hlášení řešíme přednostně. Pokud je dítě v bezprostředním ohrožení, zavolej 158 nebo linku 116 111.';

  @override
  String get reportSubmittedThanks => 'Díky. Podíváme se na to co nejdřív.';

  @override
  String get commonDone => 'Hotovo';

  @override
  String get reportPanelE2eNotice =>
      'Zprávy jsou end-to-end šifrované, takže jejich obsah nevidíme ani teď. Popiš prosím vlastními slovy, co se stalo. Nevkládej sem obsah zpráv ani odkazy na něj — nesmíme ho držet a k posouzení ho nepotřebujeme.';

  @override
  String get reportPanelCsamWarning =>
      'Materiál zobrazující zneužívání dítěte nám NEPOSÍLEJ. Jeho držení je trestné i pro nás a pro nahlášení ho nepotřebujeme. Materiál patří přímo na STOPonline.cz nebo Policii ČR (158). Nám napiš jen to, co se stalo — zablokujeme účet a předáme věc dál.';

  @override
  String get reportPanelIpNotice =>
      'Hlášení nejde přes relay, ale na náš webový server. Ten se při odeslání dozví tvou IP adresu.';

  @override
  String get reportCategoryHeading => 'Čeho se hlášení týká';

  @override
  String get reportDescriptionHeading => 'Co se stalo';

  @override
  String get reportAttachContactId => 'Přiložit ID nahlášeného kontaktu';

  @override
  String reportAttachContactIdNamed(String contactName) {
    return 'Přiložit ID kontaktu $contactName';
  }

  @override
  String get reportReplyToHeading => 'Kontakt na tebe (nepovinné)';

  @override
  String get reportReplyToHint => 'e-mail, kdybychom se potřebovali doptat';

  @override
  String get reportSubmitButton => 'Odeslat hlášení';

  @override
  String get contactsTitle => 'Kontakty';

  @override
  String get contactsAddContact => 'Přidat kontakt';

  @override
  String get contactsSearchHint => 'Hledat kontakt...';

  @override
  String get contactsEmpty => 'Zatím žádné kontakty';

  @override
  String get contactsNoResults => 'Žádné výsledky';

  @override
  String get contactsShareCardTitle => 'Sdílej svůj Šepot ID';

  @override
  String get contactsShareCardSubtitle => 'Ukaž QR kód nebo pošli odkaz';

  @override
  String get contactsAddDialogPrompt =>
      'Vlož sdílený řetězec (share string) kontaktu:';

  @override
  String get contactsShareStringHint => 'Vložit share string...';

  @override
  String get contactsInvalidShareString => 'Neplatný share string';

  @override
  String contactsAdded(String name) {
    return 'Kontakt $name přidán';
  }

  @override
  String get verifyContactSubtitle => 'Porovnání bezpečnostního čísla';

  @override
  String get contactsDeleteContact => 'Smazat kontakt';

  @override
  String get pinConfirmTitle => 'Potvrď PIN';

  @override
  String get pinSetupTitle => 'Nastav si PIN';

  @override
  String get pinConfirmSubtitle => 'Zadej PIN znovu pro potvrzení';

  @override
  String get pinSetupSubtitle => '6-místný PIN pro odemknutí aplikace';

  @override
  String get pinSetupFailed => 'Nastavení PINu selhalo. Zkus to znovu.';

  @override
  String get pinMismatchRetry => 'PINy se neshodují. Zkus to znovu.';

  @override
  String get pinChangeCurrentTitle => 'Zadej současný PIN';

  @override
  String get pinChangeCurrentSubtitle => 'Ověříme ho odemčením klíče';

  @override
  String get pinChangeNewTitle => 'Zadej nový PIN';

  @override
  String get pinChangeNewSubtitle => '6 číslic';

  @override
  String get pinChangeConfirmTitle => 'Potvrď nový PIN';

  @override
  String get pinChangeConfirmSubtitle => 'Zadej ho ještě jednou';

  @override
  String get pinWrong => 'Špatný PIN.';

  @override
  String get pinChangeMustDiffer => 'Nový PIN se musí lišit od současného.';

  @override
  String get pinMismatch => 'PINy se neshodují.';

  @override
  String get pinDecoyConflict =>
      'Tenhle PIN už patří nátlakovému režimu. Zvol jiný.';

  @override
  String get pinChangeFailed => 'Změna PINu selhala. Zkus to znovu.';

  @override
  String get pinChanged => 'PIN změněn';

  @override
  String get errorCryptoInitTitle => 'Šifrovací jádro se nespustilo';

  @override
  String get errorStartupTitle => 'Šepot se nespustil';

  @override
  String get errorScreenNotRenderedTitle => 'Tahle obrazovka se nevykreslila';

  @override
  String get errorStartupBody =>
      'Něco se pokazilo hned při startu. Pošli mi prosím tenhle text (podrž prst a zkopíruj) — pomůže mi to najít chybu.';

  @override
  String get errorContactFooter => 'sepot.cz · napiš mi na kontakt';

  @override
  String get pinUnlockTitle => 'Odemkni Šepot';

  @override
  String get pinEnterPin => 'Zadej PIN';

  @override
  String get pinUnlockWithBiometrics => 'Odemknout biometrií';

  @override
  String get pinWrong2 => 'Špatný PIN';

  @override
  String get pinUnlockError => 'Chyba odemčení';

  @override
  String get pushTitle => 'Push notifikace';

  @override
  String get pushModeOffDesc => 'Zprávy se stáhnou až po otevření appky.';

  @override
  String get pushModeUp => 'UnifiedPush (doporučeno)';

  @override
  String get pushModeUpDesc =>
      'Degooglované — potřebuje aplikaci ntfy (F-Droid/Play).';

  @override
  String get pushModeFcm => 'Google (FCM)';

  @override
  String get pushModeFcmDesc =>
      'Spolehlivé bez další aplikace. Push token zařízení jde Googlu; obsah zpráv nikdy.';

  @override
  String pushSetupFailed(String error) {
    return 'Nastavení pushů selhalo: $error';
  }

  @override
  String get pushHintOff =>
      'Zprávy ti přijdou, až Šepot otevřeš — budíčky nejsou nastavené.';

  @override
  String get pushHintFailed =>
      'Budíčky nefungují, zprávy uvidíš až po otevření Šepotu.';

  @override
  String get pushRegistrationFailed =>
      'Budíčky nechodí — distributor registraci odmítl. Zkus push vypnout a znovu zapnout.';

  @override
  String get pushNoDistributorTitle => 'Žádný distributor';

  @override
  String get pushNoDistributorBody =>
      'Pro degooglované notifikace nainstaluj UnifiedPush distributor, např. ntfy (F-Droid nebo Play). Pak push zapni znovu.';

  @override
  String get commonOk => 'OK';

  @override
  String get pushPickDistributorTitle => 'Vyber distributora';

  @override
  String pushSubtitleUnifiedPush(String distributor) {
    return 'UnifiedPush · $distributor';
  }

  @override
  String get pushNoDistributorFallback => 'bez distributora';

  @override
  String get pushSubtitleFcm => 'Google (FCM) — rychlé, opt-in';

  @override
  String get restoreErrorNameRequired => 'Zadej zobrazované jméno.';

  @override
  String restoreErrorWordCount(int wordCount, int requiredWords) {
    String _temp0 = intl.Intl.pluralLogic(
      wordCount,
      locale: localeName,
      other: 'Fráze má $wordCount slov, potřebuji $requiredWords.',
      many: 'Fráze má $wordCount slova, potřebuji $requiredWords.',
      few: 'Fráze má $wordCount slova, potřebuji $requiredWords.',
      one: 'Fráze má 1 slovo, potřebuji $requiredWords.',
    );
    return '$_temp0';
  }

  @override
  String get restoreErrorInvalidPhrase =>
      'Fráze není platná — zkontroluj slova i jejich pořadí.';

  @override
  String restoreErrorFailed(String error) {
    return 'Obnova selhala: $error';
  }

  @override
  String get restoreTitle => 'Obnovit účet';

  @override
  String get restoreHeading => 'Zadej svoji zálohovací frázi';

  @override
  String restoreIntro(int wordCount) {
    return '$wordCount slov, ze zálohy vytvořené při zakládání účtu. Obnoví tvoji identitu (stejný SEP kód, kontakty tě dál poznají).';
  }

  @override
  String get restoreHistoryWarning =>
      'Historie zpráv se neobnoví — je uložená jen na původním zařízení.';

  @override
  String get restorePhraseHint => 'slovo1 slovo2 slovo3 …';

  @override
  String restoreWordCountHelper(int wordCount, int requiredWords) {
    return '$wordCount / $requiredWords slov';
  }

  @override
  String chatListArchivedCount(int count) {
    return 'Archivované ($count)';
  }

  @override
  String get chatListEmptyTitle => 'Zatím žádné konverzace';

  @override
  String get chatListEmptySubtitle => 'Přidej kontakt a začni šeptat!';

  @override
  String get chatListUnmute => 'Zrušit ztlumení';

  @override
  String get chatListMute => 'Ztlumit';

  @override
  String get chatListArchive => 'Archivovat';

  @override
  String get qrShareTitle => 'Můj Šepot ID';

  @override
  String get qrShareConnectingTitle => 'Připojuji k relayi…';

  @override
  String get qrShareConnectingBody =>
      'Až se Šepot poprvé připojí, objeví se tvůj QR kód a odkaz. Chvilku strpení — stačí pár sekund.';

  @override
  String get qrIdentityNotFound => 'Identita nebyla nalezena';

  @override
  String get commonCopiedToClipboard => 'Zkopírováno do schránky';

  @override
  String qrShareInviteMessage(String shareString) {
    return 'Přidej mě na Šepotu!\n\n$shareString';
  }

  @override
  String get commonShare => 'Sdílet';

  @override
  String get qrShareInfo =>
      'Kontakt naskenuje tvůj QR kód nebo vloží sdílený řetězec do aplikace.';

  @override
  String get reportCategoryChildSafety => 'Ohrožení dítěte';

  @override
  String get reportCategoryChildSafetyHint =>
      'Popiš situaci vlastními slovy. Nevkládej obsah zpráv ani odkazy na materiál.';

  @override
  String get reportCategoryHarassment => 'Obtěžování nebo výhrůžky';

  @override
  String get reportCategoryHarassmentHint =>
      'Někdo tě zastrašuje, vyhrožuje nebo obtěžuje.';

  @override
  String get reportCategorySpam => 'Spam';

  @override
  String get reportCategorySpamHint =>
      'Nevyžádané zprávy, hromadné rozesílání.';

  @override
  String get reportCategoryFraud => 'Podvod';

  @override
  String get reportCategoryFraudHint =>
      'Pokus vylákat peníze, klíče nebo osobní údaje.';

  @override
  String get reportCategoryOther => 'Jiné';

  @override
  String get reportCategoryOtherHint => 'Něco jiného, co bychom měli vědět.';

  @override
  String get reportErrorEmptyDescription => 'Napiš prosím, co se stalo.';

  @override
  String reportErrorConnection(String supportEmail) {
    return 'Nepodařilo se spojit se serverem. Zkus to znovu, nebo napiš na $supportEmail.';
  }

  @override
  String reportErrorRateLimited(String supportEmail) {
    return 'Z tvé sítě přišlo příliš mnoho hlášení. Zkus to za hodinu, nebo napiš na $supportEmail.';
  }

  @override
  String reportErrorServer(int statusCode, String supportEmail) {
    return 'Odeslání selhalo (kód $statusCode). Napiš prosím na $supportEmail.';
  }

  @override
  String get settingsAutoLockNever => 'Nikdy';

  @override
  String get settingsAutoLock1min => 'Po 1 minutě';

  @override
  String get settingsAutoLock15min => 'Po 15 minutách';

  @override
  String torToggleFailed(String error) {
    return 'Přepnutí Toru selhalo: $error';
  }

  @override
  String get torConnectionTitle => 'Připojení přes Tor';

  @override
  String get torDialogBody =>
      'Provoz na server půjde přes síť Tor (skryje tvou IP adresu). Vyžaduje nainstalovanou a spuštěnou aplikaci Orbot s aktivním SOCKS proxy na portu 9050.\n\nBez běžícího Orbotu se zprávy neodešlou ani nepřijmou. Spojení bývá pomalejší.';

  @override
  String get commonTurnOn => 'Zapnout';

  @override
  String get torSubtitleOff =>
      'Přímé šifrované spojení (WSS). Zapni pro skrytí IP přes Tor.';

  @override
  String get torStatusConnected => 'Připojeno přes Tor (.onion).';

  @override
  String get torStatusConnecting => 'Připojuji přes Tor… (běží Orbot?)';

  @override
  String get torStatusWaiting => 'Přes Tor — čekám na Orbot (SOCKS 9050).';

  @override
  String get biometricsPinRequiredFirst =>
      'Nejdřív nastav PIN — biometrie ho jen doplňuje.';

  @override
  String get biometricsStorageLocked =>
      'Úložiště je zamčené — odemkni appku PINem.';

  @override
  String get biometricsNotAvailable => 'Zařízení nemá nastavenou biometrii.';

  @override
  String get biometricsEnrollPromptReason =>
      'Potvrď zapnutí biometrického odemčení';

  @override
  String biometricsSetupFailed(String error) {
    return 'Biometrii se nepodařilo nastavit: $error';
  }

  @override
  String get biometricsTileTitle => 'Biometrie';

  @override
  String get biometricsTileSubtitle =>
      'Odemknutí otiskem prstu / obličejem (PIN zůstává záloha)';

  @override
  String get backupErrorCorruptedFile => 'Poškozený soubor zálohy';

  @override
  String get backupErrorUnknownFormat => 'Nerozpoznaný formát zálohy';

  @override
  String get backupErrorWrongIdentity =>
      'Zálohu nelze dešifrovat — patří k jiné identitě?';

  @override
  String attachmentSharedImageFilename(String ext) {
    return 'sepot-obrazek.$ext';
  }

  @override
  String get attachmentDecryptFailed => 'Přílohu se nepodařilo dešifrovat';

  @override
  String get pushActionOpen => 'Otevřít';

  @override
  String get pushChannelMessagesName => 'Zprávy';

  @override
  String get pushChannelMessagesDescription =>
      'Upozornění na nové zprávy (bez obsahu)';

  @override
  String pushNewMessageFrom(String senderName) {
    return 'Nová zpráva od $senderName';
  }

  @override
  String get pushNewMessages => 'Máš nové zprávy';

  @override
  String get archiveTitle => 'Archivované';

  @override
  String get archiveEmpty => 'Žádné archivované konverzace';

  @override
  String get archiveUnarchive => 'Zrušit archivaci';

  @override
  String restoreErrorMnemonicWordCount(int count, int expected) {
    return 'Fráze má $count slov, očekávám $expected';
  }

  @override
  String restoreErrorInvalidMnemonic(String message) {
    return 'Neplatná fráze: $message';
  }

  @override
  String get contactsErrorAlreadyExists => 'Kontakt již existuje';

  @override
  String get commonAppTagline => 'Soukromý messenger';

  @override
  String get commonE2eBadgeCompact => 'E2E';

  @override
  String get commonE2eBadgeFull => 'End-to-end šifrováno';

  @override
  String get photoPreviewCaptionHint => 'Přidat popisek…';

  @override
  String get photoPreviewDraw => 'Kreslit';

  @override
  String get photoPreviewAddText => 'Přidat text';

  @override
  String get photoPreviewRotate => 'Otočit';

  @override
  String get photoPreviewUndo => 'Zpět';

  @override
  String get photoPreviewSend => 'Poslat';

  @override
  String get photoPreviewTextDialogTitle => 'Text na fotce';

  @override
  String get photoPreviewRemoveText => 'Odebrat';

  @override
  String get photoPreviewDecodeFailed => 'Fotku se nepodařilo načíst';
}
