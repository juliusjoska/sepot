import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_cs.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('cs'),
    Locale('de'),
    Locale('en'),
    Locale('it'),
    Locale('ru'),
  ];

  /// Název aplikace — značka, nepřekládá se.
  ///
  /// In cs, this message translates to:
  /// **'Šepot'**
  String get appTitle;

  /// Nastavení: titulek dlaždice a dialogu pro volbu jazyka rozhraní.
  ///
  /// In cs, this message translates to:
  /// **'Jazyk aplikace'**
  String get settingsLanguage;

  /// Volba jazyka: řídit se jazykem zařízení.
  ///
  /// In cs, this message translates to:
  /// **'Podle systému'**
  String get languageSystem;

  /// Titulek AppBar chatu, když kontakt nebyl nalezen | Fallback displayName nově založeného kontaktu z rosteru skupinové pozvánky (_handleGroupInvite), když člen nemá jméno — objeví se jako jméno kontaktu v seznamu kontaktů a chatu. | Fallback displayName v _findOrCreateContact pro neznámého odesílatele bez jména v profilu — identický text jako ř. 967, stejný klíč.
  ///
  /// In cs, this message translates to:
  /// **'Neznámý'**
  String get commonUnknownContact;

  /// Stav ověření kontaktu pod jménem v AppBar chatu (klepnutí vede na safety number) | Titulek AlertDialogu po skenu QR, když bezpečnostní čísla souhlasí
  ///
  /// In cs, this message translates to:
  /// **'Ověřeno'**
  String get verifyVerified;

  /// Stav ověření kontaktu pod jménem v AppBar chatu
  ///
  /// In cs, this message translates to:
  /// **'Neověřeno'**
  String get verifyUnverified;

  /// Položka popup menu (⋮) v chatu 1:1 | Titulek položky v bottom sheetu (long-press na kontakt) — vede na obrazovku ověření safety number
  ///
  /// In cs, this message translates to:
  /// **'Ověřit kontakt'**
  String get chatMenuVerifyContact;

  /// Položka popup menu chatu 1:1; stejný text i ve skupinovém menu (ř. 350) a jako titulek SimpleDialog (ř. 1125) — jeden klíč | Položka popup menu skupinového chatu — sdílený klíč s ř. 173 | Titulek SimpleDialog výběru TTL — sdílený klíč s ř. 173/350
  ///
  /// In cs, this message translates to:
  /// **'Mizící zprávy'**
  String get chatDisappearingMessages;

  /// Položka popup menu chatu, když je kontakt blokovaný
  ///
  /// In cs, this message translates to:
  /// **'Odblokovat kontakt'**
  String get chatMenuUnblockContact;

  /// Položka popup menu chatu
  ///
  /// In cs, this message translates to:
  /// **'Blokovat kontakt'**
  String get chatMenuBlockContact;

  /// Položka popup menu chatu (červená); stejný text = titulek dialogu (ř. 637) a potvrzovací tlačítko (ř. 649) | Titulek AlertDialogu nahlášení — sdílený klíč s ř. 188 a 649 | Potvrzovací tlačítko dialogu nahlášení (červené) — sdílený klíč
  ///
  /// In cs, this message translates to:
  /// **'Nahlásit a zablokovat'**
  String get reportAndBlock;

  /// Chybový stav při načítání konverzace (1:1 chat, střed obrazovky) | Chybový stav při načítání konverzace (skupinový chat) — sdílený klíč s ř. 250 | SnackBar — obecná chyba při nastavování nátlakového PINu; kandidát na sdílený klíč napříč appkou
  ///
  /// In cs, this message translates to:
  /// **'Chyba: {error}'**
  String errorGeneric(String error);

  /// Podtitulek AppBar skupinového chatu po opuštění skupiny; POZOR gender (opustil/opustila)
  ///
  /// In cs, this message translates to:
  /// **'Už nejsi ve skupině'**
  String get groupsYouLeftGroup;

  /// Podtitulek AppBar skupinového chatu — počet členů, klepnutí otevře seznam.
  ///
  /// In cs, this message translates to:
  /// **'{count, plural, one{1 člen} few{{count} členové} many{{count} člena} other{{count} členů}}'**
  String groupsMemberCount(int count);

  /// Položka popup menu skupinového chatu
  ///
  /// In cs, this message translates to:
  /// **'Členové'**
  String get groupsMembers;

  /// Položka popup menu skupiny; stejný text = titulek dialogu přejmenování (ř. 522) — jeden klíč | Titulek AlertDialog přejmenování skupiny — sdílený klíč s ř. 348
  ///
  /// In cs, this message translates to:
  /// **'Přejmenovat skupinu'**
  String get groupsRename;

  /// Položka popup menu skupiny (červená)
  ///
  /// In cs, this message translates to:
  /// **'Opustit skupinu'**
  String get groupsLeave;

  /// Banner místo input baru ve skupině, kterou uživatel opustil; POZOR gender
  ///
  /// In cs, this message translates to:
  /// **'Už nejsi ve skupině. Historie zůstává, nové zprávy nedorazí.'**
  String get groupsLeftBanner;

  /// Fallback jména vlastního avataru v seznamu členů skupiny | Titulek ListTile vlastní osoby v seznamu členů skupiny — stejný klíč jako ř. 486
  ///
  /// In cs, this message translates to:
  /// **'Ty'**
  String get groupsYou;

  /// Subtitle člena, který skupinu založil, v seznamu členů
  ///
  /// In cs, this message translates to:
  /// **'Zakladatel'**
  String get groupsFounder;

  /// Odznak správce skupiny u člena v seznamu členů
  ///
  /// In cs, this message translates to:
  /// **'Správce'**
  String get groupsAdmin;

  /// Akce v nabídce člena: udělit roli správce
  ///
  /// In cs, this message translates to:
  /// **'Udělat správcem'**
  String get groupsMakeAdmin;

  /// Akce v nabídce člena: odebrat roli správce
  ///
  /// In cs, this message translates to:
  /// **'Odebrat roli správce'**
  String get groupsDismissAdmin;

  /// Akce v nabídce člena: odebrat ze skupiny
  ///
  /// In cs, this message translates to:
  /// **'Odebrat ze skupiny'**
  String get groupsRemoveMember;

  /// Titulek potvrzení odebrání člena
  ///
  /// In cs, this message translates to:
  /// **'Odebrat {name} ze skupiny?'**
  String groupsRemoveMemberConfirmTitle(String name);

  /// Text potvrzení odebrání člena
  ///
  /// In cs, this message translates to:
  /// **'Přestanou mu chodit nové zprávy skupiny. Dosavadní historie mu zůstane.'**
  String get groupsRemoveMemberConfirmBody;

  /// Potvrzovací tlačítko odebrání člena
  ///
  /// In cs, this message translates to:
  /// **'Odebrat'**
  String get groupsRemoveAction;

  /// Akce v nabídce člena: otevřít profil kontaktu
  ///
  /// In cs, this message translates to:
  /// **'Zobrazit kontakt'**
  String get groupsViewContact;

  /// Vysvětlení pod seznamem členů pro ne-správce ve vynucené skupině
  ///
  /// In cs, this message translates to:
  /// **'Jméno, členy a správce skupiny mění jen správci.'**
  String get groupsAdminOnlyHint;

  /// Vysvětlení pro ne-správce, dokud je ve skupině člen se starší verzí aplikace
  ///
  /// In cs, this message translates to:
  /// **'Jméno a správce mění jen správci. Přidávat lidi zatím může každý, protože někdo ve skupině má starší verzi Šepotu.'**
  String get groupsAdminOnlyCompatHint;

  /// SnackBar při selhání správcovské akce
  ///
  /// In cs, this message translates to:
  /// **'Změna se nepovedla: {error}'**
  String groupsAdminActionFailed(String error);

  /// Upozornění v profilu skupiny, když chybí mezistav od správce
  ///
  /// In cs, this message translates to:
  /// **'Stav skupiny se srovnává se správcem. Změny členů se můžou chvíli opozdit.'**
  String get groupsResyncNotice;

  /// Upozornění v profilu skupiny po odmítnuté neoprávněné změně
  ///
  /// In cs, this message translates to:
  /// **'Někdo bez oprávnění zkusil skupinu změnit. Změna se neprovedla.'**
  String get groupsRejectedChangeNotice;

  /// Chyba: akci smí udělat jen správce skupiny
  ///
  /// In cs, this message translates to:
  /// **'Tohle může udělat jen správce skupiny.'**
  String get errorGroupNotAdmin;

  /// Chyba: poslední správce se nemůže vzdát role
  ///
  /// In cs, this message translates to:
  /// **'Jsi jediný správce. Nejdřív udělej správcem někoho dalšího.'**
  String get errorGroupLastAdmin;

  /// hintText TextFieldu v dialogu přejmenování skupiny | labelText textového pole pro jméno skupiny (max 64 znaků)
  ///
  /// In cs, this message translates to:
  /// **'Název skupiny'**
  String get groupsNameHint;

  /// Tlačítko zrušení v dialogu přejmenování skupiny | Tlačítko zrušení v dialogu opuštění skupiny — sdílený klíč | Tlačítko zrušení v dialogu nahlášení — sdílený klíč
  ///
  /// In cs, this message translates to:
  /// **'Zrušit'**
  String get commonCancel;

  /// Potvrzovací tlačítko dialogu přejmenování skupiny
  ///
  /// In cs, this message translates to:
  /// **'Uložit'**
  String get commonSave;

  /// SnackBar při selhání přejmenování skupiny
  ///
  /// In cs, this message translates to:
  /// **'Přejmenování selhalo: {error}'**
  String groupsRenameFailed(String error);

  /// Titulek potvrzovacího AlertDialogu opuštění skupiny
  ///
  /// In cs, this message translates to:
  /// **'Opustit skupinu?'**
  String get groupsLeaveConfirmTitle;

  /// Obsah potvrzovacího dialogu opuštění skupiny. POZOR: adjacentní literály přes 2 řádky (558-559) — sloučit do jednoho klíče; gender ('odešel')
  ///
  /// In cs, this message translates to:
  /// **'Ostatní uvidí, že už ve skupině nejsi. Historie ti zůstane, ale nové zprávy už nedostaneš a zpět tě musí někdo pozvat.'**
  String get groupsLeaveConfirmBody;

  /// Destruktivní potvrzovací tlačítko dialogu opuštění skupiny
  ///
  /// In cs, this message translates to:
  /// **'Opustit'**
  String get groupsLeaveAction;

  /// SnackBar při selhání opuštění skupiny
  ///
  /// In cs, this message translates to:
  /// **'Odchod selhal: {error}'**
  String groupsLeaveFailed(String error);

  /// Banner místo input baru u blokovaného kontaktu
  ///
  /// In cs, this message translates to:
  /// **'Kontakt je zablokovaný. Nedostáváš od něj zprávy a nemůžeš mu psát.'**
  String get chatBlockedBanner;

  /// Tlačítko v banneru blokovaného kontaktu
  ///
  /// In cs, this message translates to:
  /// **'Odblokovat'**
  String get chatUnblock;

  /// SnackBar po zablokování kontaktu; POZOR gender ('byl') — přeformulovat neutrálně nebo ICU select
  ///
  /// In cs, this message translates to:
  /// **'Kontakt {name} je zablokovaný'**
  String chatContactBlocked(String name);

  /// SnackBar po odblokování kontaktu; POZOR gender
  ///
  /// In cs, this message translates to:
  /// **'Kontakt {name} je odblokovaný'**
  String chatContactUnblocked(String name);

  /// Obsah dialogu nahlášení kontaktu. POZOR: adjacentní literály přes 3 řádky (639-641) — sloučit do jednoho klíče; gender ('bude zablokován')
  ///
  /// In cs, this message translates to:
  /// **'Kontakt {name} zablokujeme a přestaneš od něj dostávat zprávy. Pak ti nabídneme formulář, kterým nám dáš vědět, co se stalo — obsah zpráv nevidíme, takže bez tvého popisu o tom nevíme.'**
  String reportAndBlockBody(String name);

  /// Prázdný stav chatu (žádné zprávy), první řádek pod E2E badge
  ///
  /// In cs, this message translates to:
  /// **'Zprávy jsou end-to-end šifrované.'**
  String get chatEmptyEncrypted;

  /// Prázdný stav chatu, druhý řádek — navazuje na chatEmptyEncrypted
  ///
  /// In cs, this message translates to:
  /// **'Nikdo jiný je nemůže číst.'**
  String get chatEmptyNoOneElse;

  /// Datumový oddělovač mezi zprávami pro dnešní den — pravděpodobně sdílený i s chat listem
  ///
  /// In cs, this message translates to:
  /// **'Dnes'**
  String get commonToday;

  /// Datumový oddělovač mezi zprávami pro včerejší den
  ///
  /// In cs, this message translates to:
  /// **'Včera'**
  String get commonYesterday;

  /// hintText vstupního pole pro psaní zprávy
  ///
  /// In cs, this message translates to:
  /// **'Napiš zprávu…'**
  String get chatMessageHint;

  /// Tooltip tlačítka koše v liště nahrávání hlasové zprávy
  ///
  /// In cs, this message translates to:
  /// **'Zahodit'**
  String get chatDiscardRecording;

  /// Text v liště během nahrávání hlasové zprávy; gender OK (1. os.), ale ověřit pro ru/it
  ///
  /// In cs, this message translates to:
  /// **'Nahrávám…'**
  String get chatRecording;

  /// SnackBar když aplikace nemá oprávnění k mikrofonu při startu nahrávání
  ///
  /// In cs, this message translates to:
  /// **'Chybí oprávnění k mikrofonu'**
  String get chatMicPermissionMissing;

  /// SnackBar při selhání startu nahrávání hlasové zprávy
  ///
  /// In cs, this message translates to:
  /// **'Nahrávání selhalo: {error}'**
  String chatRecordingFailed(String error);

  /// SnackBar při selhání odeslání hlasové zprávy
  ///
  /// In cs, this message translates to:
  /// **'Odeslání hlasové zprávy selhalo: {error}'**
  String chatVoiceSendFailed(String error);

  /// Náhled citované zprávy v compose banneru (odpověď na smazanou zprávu); stejný text v _buildQuote ř. 1486 — jeden klíč | Náhled citované smazané zprávy v quote bloku bubliny — sdílený klíč s ř. 952
  ///
  /// In cs, this message translates to:
  /// **'Smazaná zpráva'**
  String get chatDeletedMessagePreview;

  /// Náhled citované hlasové zprávy v compose banneru; stejný text ř. 1488 — jeden klíč | Náhled citované hlasové zprávy v quote bloku bubliny — sdílený klíč s ř. 954 | Náhled poslední zprávy v dlaždici, když je poslední zpráva hlasová (audio příloha); emoji je součást textu
  ///
  /// In cs, this message translates to:
  /// **'🎤 Hlasová zpráva'**
  String get chatVoiceMessagePreview;

  /// Náhled citovaného obrázku v compose banneru; stejný text ř. 1491 — jeden klíč | Náhled citovaného obrázku v quote bloku bubliny — sdílený klíč s ř. 958 | Náhled poslední zprávy v dlaždici — fotka bez popisku; emoji je součást textu
  ///
  /// In cs, this message translates to:
  /// **'📷 Fotka'**
  String get chatPhotoPreview;

  /// Náhled citované přílohy v compose banneru; stejný text ř. 1491 — jeden klíč | Náhled citované přílohy v quote bloku bubliny — sdílený klíč s ř. 959
  ///
  /// In cs, this message translates to:
  /// **'📎 Příloha'**
  String get chatAttachmentPreview;

  /// Titulek compose banneru v režimu úpravy zprávy
  ///
  /// In cs, this message translates to:
  /// **'Úprava zprávy'**
  String get chatEditingMessage;

  /// Titulek compose banneru v režimu odpovědi
  ///
  /// In cs, this message translates to:
  /// **'Odpověď'**
  String get chatReply;

  /// Položka akčního bottom sheetu zprávy (long-press)
  ///
  /// In cs, this message translates to:
  /// **'Odpovědět'**
  String get chatActionReply;

  /// Akce v nabídce po podržení zprávy
  ///
  /// In cs, this message translates to:
  /// **'Přeposlat'**
  String get chatActionForward;

  /// Nadpis panelu výběru chatu pro přeposlání
  ///
  /// In cs, this message translates to:
  /// **'Přeposlat do…'**
  String get forwardTitle;

  /// Nápověda v poli hledání panelu přeposlání
  ///
  /// In cs, this message translates to:
  /// **'Hledat kontakt nebo skupinu'**
  String get forwardSearchHint;

  /// Prázdný výsledek hledání v panelu přeposlání
  ///
  /// In cs, this message translates to:
  /// **'Nic tu není'**
  String get forwardEmpty;

  /// SnackBar po přeposlání zprávy
  ///
  /// In cs, this message translates to:
  /// **'Přeposláno: {name}'**
  String forwardDone(String name);

  /// SnackBar při chybě přeposlání
  ///
  /// In cs, this message translates to:
  /// **'Přeposlání se nepovedlo: {error}'**
  String forwardFailed(String error);

  /// Položka akčního bottom sheetu zprávy — kopírování textu do schránky | Popisek OutlinedButton.icon pro zkopírování Šepot ID do schránky
  ///
  /// In cs, this message translates to:
  /// **'Kopírovat'**
  String get commonCopy;

  /// Položka akčního bottom sheetu vlastní textové zprávy
  ///
  /// In cs, this message translates to:
  /// **'Upravit'**
  String get commonEdit;

  /// Položka akčního bottom sheetu — lokální smazání zprávy
  ///
  /// In cs, this message translates to:
  /// **'Smazat u mě'**
  String get chatDeleteForMe;

  /// Položka akčního bottom sheetu vlastní zprávy (červená) — smazání u obou stran
  ///
  /// In cs, this message translates to:
  /// **'Smazat pro všechny'**
  String get chatDeleteForEveryone;

  /// Volba v dialogu mizících zpráv (TTL vypnuto); text se používá i v potvrzovacím SnackBaru přes placeholder ř. 1167 | Label volby 'off' v dialogu výběru režimu pushů. Stejný text jako subtitle ListTile pro vypnutý stav (ř. 168) → stejný klíč. | Subtitle ListTile v nastavení, když jsou pushe vypnuté — stejný text a klíč jako label volby v dialogu (ř. 46)
  ///
  /// In cs, this message translates to:
  /// **'Vypnuto'**
  String get commonOff;

  /// Volba TTL v dialogu mizících zpráv; české skloňování zapečené ve fixním labelu — samostatný klíč, ne ICU
  ///
  /// In cs, this message translates to:
  /// **'30 sekund'**
  String get chatDisappearing30s;

  /// Volba TTL v dialogu mizících zpráv
  ///
  /// In cs, this message translates to:
  /// **'5 minut'**
  String get chatDisappearing5m;

  /// Volba TTL v dialogu mizících zpráv
  ///
  /// In cs, this message translates to:
  /// **'1 hodina'**
  String get chatDisappearing1h;

  /// Volba TTL v dialogu mizících zpráv
  ///
  /// In cs, this message translates to:
  /// **'1 den'**
  String get chatDisappearing1d;

  /// Volba TTL v dialogu mizících zpráv
  ///
  /// In cs, this message translates to:
  /// **'1 týden'**
  String get chatDisappearing1w;

  /// Vysvětlující text v dialogu mizících zpráv
  ///
  /// In cs, this message translates to:
  /// **'Nové zprávy se po uplynutí doby smažou u tebe i u protistrany.'**
  String get chatDisappearingDescription;

  /// SnackBar po vypnutí mizících zpráv
  ///
  /// In cs, this message translates to:
  /// **'Mizící zprávy vypnuty'**
  String get chatDisappearingDisabled;

  /// SnackBar po nastavení TTL mizících zpráv. POZOR: adjacentní literály (1166-1167) + placeholder je lokalizovaný label volby (chatDisappearing*) — v kódu dosazovat už přeložený string
  ///
  /// In cs, this message translates to:
  /// **'Nové zprávy zmizí po: {duration}'**
  String chatDisappearingEnabled(String duration);

  /// Položka bottom sheetu výběru přílohy
  ///
  /// In cs, this message translates to:
  /// **'Fotka z galerie'**
  String get attachmentGallery;

  /// Položka bottom sheetu výběru přílohy — kamera
  ///
  /// In cs, this message translates to:
  /// **'Vyfotit'**
  String get attachmentTakePhoto;

  /// Položka bottom sheetu výběru přílohy — file picker
  ///
  /// In cs, this message translates to:
  /// **'Dokument'**
  String get attachmentDocument;

  /// SnackBar (_showError) když vybraný dokument překročí limit velikosti. POZOR: adjacentní literály (1227-1228) — sloučit
  ///
  /// In cs, this message translates to:
  /// **'Soubor je příliš velký (max {maxMb} MB)'**
  String attachmentTooLarge(int maxMb);

  /// Titulek dialogu před odesláním obrázku jako dokumentu, když z něj nejde odstranit EXIF (HEIC, RAW)
  ///
  /// In cs, this message translates to:
  /// **'Fotka odejde i s polohou'**
  String get attachmentKeepsMetadataTitle;

  /// Text téhož dialogu
  ///
  /// In cs, this message translates to:
  /// **'Tenhle formát fotky (třeba HEIC) neumím zbavit metadat. Odešla by v originále včetně polohy, kde vznikla, a údajů o telefonu. Bezpečnější je poslat ji přes Galerii, kde se metadata odstraní.'**
  String get attachmentKeepsMetadataBody;

  /// Potvrzovací tlačítko téhož dialogu
  ///
  /// In cs, this message translates to:
  /// **'Poslat originál'**
  String get attachmentSendOriginal;

  /// SnackBar (_showError) při selhání výběru přílohy
  ///
  /// In cs, this message translates to:
  /// **'Výběr přílohy selhal: {error}'**
  String attachmentPickFailed(String error);

  /// SnackBar (_showError) při selhání odeslání přílohy
  ///
  /// In cs, this message translates to:
  /// **'Odeslání přílohy selhalo: {error}'**
  String attachmentSendFailed(String error);

  /// SnackBar při selhání odeslání/úpravy textové zprávy
  ///
  /// In cs, this message translates to:
  /// **'Odeslání selhalo: {error}'**
  String chatSendFailed(String error);

  /// Text v bublině smazané zprávy (kurzíva s ikonou block) | Náhled poslední zprávy v dlaždici, když byla poslední zpráva smazána
  ///
  /// In cs, this message translates to:
  /// **'Zpráva smazána'**
  String get chatMessageDeleted;

  /// Malý štítek v patičce bubliny upravené zprávy, vedle času
  ///
  /// In cs, this message translates to:
  /// **'upraveno'**
  String get chatEdited;

  /// StateError z _refreshSenderCert při neshodě pinovaného trust rootu (možný MITM/jiný relay); propaguje se přes _senderCertificate do sendText/sendAttachment — chybu zobrazuje chat UI (SnackBar / failed stav zprávy).
  ///
  /// In cs, this message translates to:
  /// **'Trust root relaye se změnil! Odmítám komunikovat.'**
  String get errorTrustRootChanged;

  /// StateError z _senderCertificate, když se nepodařilo získat sender certificate (offline relay); propaguje se do odesílací cesty, zobrazuje chat UI při selhání odeslání.
  ///
  /// In cs, this message translates to:
  /// **'Relay nedostupný (sender certificate)'**
  String get errorRelayUnavailable;

  /// NotYetRegisteredError z _sendContent, když vlastní registrace na relay ještě nedoběhla (čerstvá instalace). 'Šepot' je značka, nepřekládat.
  ///
  /// In cs, this message translates to:
  /// **'Šepot se ještě připojuje k relayi — zkus zprávu poslat za chvíli.'**
  String get errorNotYetRegistered;

  /// ContactLinkIncompleteError při přidání kontaktu z odkazu/QR bez routingu (aid+da). 'sepot://' je schéma odkazu, zachovat.
  ///
  /// In cs, this message translates to:
  /// **'Odkaz je neúplný — protistrana ho vytvořila dřív, než se stihla připojit. Požádej ji o nový sepot:// odkaz.'**
  String get errorContactLinkIncomplete;

  /// StateError z _prepareAttachment při překročení limitu velikosti přílohy; zobrazuje UI výběru/odeslání přílohy. POZOR: v kódu jde o dva adjacentní literály 'Příloha je příliš velká ' (ř. 448) + '(max ${…} MB)' (ř. 449) — sloučit do jednoho klíče.
  ///
  /// In cs, this message translates to:
  /// **'Příloha je příliš velká (max {maxMb} MB)'**
  String errorAttachmentTooLarge(int maxMb);

  /// StateError z createGroup při prázdném seznamu členů; zobrazuje UI zakládání skupiny.
  ///
  /// In cs, this message translates to:
  /// **'Skupina potřebuje aspoň 1 člena'**
  String get errorGroupNeedsMember;

  /// Chyba při přeposlání přílohy, která už byla smazána nebo nestažena
  ///
  /// In cs, this message translates to:
  /// **'Příloha už v telefonu není'**
  String get errorAttachmentUnavailable;

  /// StateError z createGroup při překročení max. počtu členů; zobrazuje UI zakládání skupiny. Počet v textu + české skloňování (člen/členové/členů) → ICU plural. | StateError z addGroupMembers — identický text jako v createGroup (ř. 583), stejný klíč. ICU plural.
  ///
  /// In cs, this message translates to:
  /// **'Skupina může mít nejvýš {maxMembers} členů'**
  String errorGroupMaxMembers(int maxMembers);

  /// StateError z createGroup pro člena bez routingu (aid/da); zobrazuje UI zakládání skupiny. Víceřádkový throw, literál na ř. 589. | StateError z addGroupMembers — identický text jako v createGroup (ř. 589), stejný klíč.
  ///
  /// In cs, this message translates to:
  /// **'{displayName} nemá doručovací adresu — požádej o nový odkaz'**
  String errorMemberNoDeliveryAddress(String displayName);

  /// StateError z _sendContent, když protějšek nemá accountId/deliveryAddress; propaguje se do sendText/sendAttachment/fanoutu — zobrazuje chat UI při selhání odeslání. 'sepot://' je schéma odkazu, v překladu zachovat.
  ///
  /// In cs, this message translates to:
  /// **'Kontakt nemá doručovací adresu — požádej ho o nový sepot:// odkaz'**
  String get errorContactNoDeliveryAddress;

  /// StateError z _sendContent při X3DH bootstrapu, když identity klíč z bundle relaye nesedí s klíčem kontaktu (anti-MITM); zobrazuje chat UI. POZOR: dva adjacentní literály 'Identity klíč z relaye NESEDÍ s kontaktem — možný MITM! ' (ř. 1013) + 'Zpráva neodeslána.' (ř. 1014) — sloučit do jednoho klíče.
  ///
  /// In cs, this message translates to:
  /// **'Identity klíč z relaye NESEDÍ s kontaktem — možný MITM! Zpráva neodeslána.'**
  String get errorIdentityKeyMismatch;

  /// Titulek AppBaru obrazovky Nastavení
  ///
  /// In cs, this message translates to:
  /// **'Nastavení'**
  String get settingsTitle;

  /// Hlavička sekce v nastavení (jazyk)
  ///
  /// In cs, this message translates to:
  /// **'Obecné'**
  String get settingsSectionGeneral;

  /// Hlavička sekce v nastavení (PIN, biometrie, zámek)
  ///
  /// In cs, this message translates to:
  /// **'Zabezpečení'**
  String get settingsSectionSecurity;

  /// Titulek dlaždice — otevře změnu PINu | Titulek AppBaru obrazovky změny PINu (vstup z dlaždice v Nastavení)
  ///
  /// In cs, this message translates to:
  /// **'Změnit PIN'**
  String get settingsChangePinTitle;

  /// Podtitulek dlaždice Změnit PIN
  ///
  /// In cs, this message translates to:
  /// **'6místný PIN pro odemknutí'**
  String get settingsChangePinSubtitle;

  /// Titulek dlaždice auto-zámku; STEJNÝ text i jako title SimpleDialogu na ř. 263 — jeden klíč | Title SimpleDialogu s výběrem intervalu auto-zámku — stejný klíč jako dlaždice ř. 67
  ///
  /// In cs, this message translates to:
  /// **'Automatický zámek'**
  String get settingsAutoLockTitle;

  /// Fallback podtitulek dlaždice auto-zámku, když mapa AutoLockNotifier.moznosti nemá hodnotu — mapa samotná je v settings_provider.dart a musí se lokalizovat tam, stejný text tam nejspíš existuje → sdílet klíč | Volba automatického zámku (300 s, výchozí) v nastavení
  ///
  /// In cs, this message translates to:
  /// **'Po 5 minutách'**
  String get settingsAutoLock5min;

  /// Titulek dlaždice nátlakového PINu; STEJNÝ text jako title AlertDialogu ř. 445 a labelText TextFieldu ř. 461 — jeden klíč | Title AlertDialogu nastavení nátlakového PINu — stejný klíč jako dlaždice ř. 75 | labelText prvního TextFieldu (zadání decoy PINu) — stejný klíč
  ///
  /// In cs, this message translates to:
  /// **'Nátlakový PIN'**
  String get settingsDecoyPinTitle;

  /// Podtitulek dlaždice, když nátlakový PIN JE nastaven
  ///
  /// In cs, this message translates to:
  /// **'Nastaven — otevře prázdnou aplikaci'**
  String get settingsDecoyPinSetSubtitle;

  /// Podtitulek dlaždice, když nátlakový PIN NENÍ nastaven
  ///
  /// In cs, this message translates to:
  /// **'Druhý PIN, který otevře prázdnou aplikaci'**
  String get settingsDecoyPinUnsetSubtitle;

  /// Hlavička sekce v nastavení (push)
  ///
  /// In cs, this message translates to:
  /// **'Notifikace'**
  String get settingsSectionNotifications;

  /// Hlavička sekce v nastavení (Tor) — jen Android
  ///
  /// In cs, this message translates to:
  /// **'Připojení'**
  String get settingsSectionConnection;

  /// Hlavička sekce v nastavení (potvrzení přečtení, screen security)
  ///
  /// In cs, this message translates to:
  /// **'Soukromí'**
  String get settingsSectionPrivacy;

  /// Titulek dlaždice se switchem
  ///
  /// In cs, this message translates to:
  /// **'Potvrzení přečtení'**
  String get settingsReadReceiptsTitle;

  /// Podtitulek dlaždice Potvrzení přečtení; tykání, mužský rod ('přečetl') — v překladu volit genderově neutrální formulaci
  ///
  /// In cs, this message translates to:
  /// **'Ukazovat protistraně přečtení zpráv (výchozí vypnuto)'**
  String get settingsReadReceiptsSubtitle;

  /// Titulek dlaždice se switchem (FLAG_SECURE)
  ///
  /// In cs, this message translates to:
  /// **'Zabezpečení obrazovky'**
  String get settingsScreenSecurityTitle;

  /// Podtitulek dlaždice Zabezpečení obrazovky
  ///
  /// In cs, this message translates to:
  /// **'Blokovat screenshoty a skrýt obsah v přepínači aplikací'**
  String get settingsScreenSecuritySubtitle;

  /// Hlavička sekce v nastavení (seed fráze, export/import)
  ///
  /// In cs, this message translates to:
  /// **'Záloha klíčů'**
  String get settingsSectionBackup;

  /// Titulek dlaždice; STEJNÝ text jako title AlertDialogu ř. 542 — jeden klíč | Title AlertDialogu se seed frází — stejný klíč jako dlaždice ř. 138 | Nadpis sekce se seed frází po vygenerování klíčů
  ///
  /// In cs, this message translates to:
  /// **'Zálohovací fráze'**
  String get settingsSeedPhraseTitle;

  /// Podtitulek dlaždice Zálohovací fráze
  ///
  /// In cs, this message translates to:
  /// **'24 slov pro obnovu identity'**
  String get settingsSeedPhraseSubtitle;

  /// Titulek dlaždice exportu zálohy
  ///
  /// In cs, this message translates to:
  /// **'Zálohovat historii'**
  String get settingsBackupExportTitle;

  /// Podtitulek dlaždice Zálohovat historii
  ///
  /// In cs, this message translates to:
  /// **'Šifrovaný soubor s kontakty a zprávami'**
  String get settingsBackupExportSubtitle;

  /// Titulek dlaždice importu zálohy
  ///
  /// In cs, this message translates to:
  /// **'Obnovit ze zálohy'**
  String get settingsBackupImportTitle;

  /// Podtitulek dlaždice Obnovit ze zálohy
  ///
  /// In cs, this message translates to:
  /// **'Načíst zálohu (jen s tvojí identitou)'**
  String get settingsBackupImportSubtitle;

  /// Hlavička sekce v nastavení (nahlášení zneužití, ochrana dětí) — odlišit od settingsSectionSecurity ('Zabezpečení')
  ///
  /// In cs, this message translates to:
  /// **'Bezpečnost'**
  String get settingsSectionSafety;

  /// Titulek dlaždice — otevře /report
  ///
  /// In cs, this message translates to:
  /// **'Nahlásit zneužití'**
  String get settingsReportAbuseTitle;

  /// Podtitulek dlaždice Nahlásit zneužití
  ///
  /// In cs, this message translates to:
  /// **'Obtěžování, podvod, ohrožení dítěte'**
  String get settingsReportAbuseSubtitle;

  /// Titulek dlaždice — otevře externí URL childSafetyUrl | TextButton dole na formuláři — otevírá AppConstants.childSafetyUrl v externím prohlížeči
  ///
  /// In cs, this message translates to:
  /// **'Standardy ochrany dětí'**
  String get settingsChildSafetyTitle;

  /// Podtitulek dlaždice Standardy ochrany dětí
  ///
  /// In cs, this message translates to:
  /// **'Jak postupujeme proti zneužívání dětí'**
  String get settingsChildSafetySubtitle;

  /// Hlavička sekce v nastavení
  ///
  /// In cs, this message translates to:
  /// **'O aplikaci'**
  String get settingsSectionAbout;

  /// Titulek dlaždice O aplikaci — název produktu; napříč jazyky pravděpodobně zůstává 'Šepot' (brand), ale klíč založit, ať jde rozhodnout centrálně | Titulek AppBaru hlavní obrazovky — název aplikace (brand; zvážit nepřekládat) | Titulek lokální notifikace (showMessageNotification). Je to název aplikace/brand — rozhodnout, zda zůstává 'Šepot' ve všech jazycích; doporučeno nepřekládat, ale klíč zavést kvůli konzistenci. Duplicitně na řádcích 60 a 83.
  ///
  /// In cs, this message translates to:
  /// **'Šepot'**
  String get commonAppName;

  /// Podtitulek dlaždice O aplikaci; STEJNÝ text i v about dialogu ř. 596 — jeden klíč | Verze v about dialogu — stejný klíč jako ř. 181
  ///
  /// In cs, this message translates to:
  /// **'Verze {version}'**
  String settingsVersion(String version);

  /// Titulek dlaždice; STEJNÝ text jako title AlertDialogu ř. 241 — jeden klíč
  ///
  /// In cs, this message translates to:
  /// **'Licence'**
  String get settingsLicenseTitle;

  /// Podtitulek dlaždice Licence — název licence, ve všech jazycích stejný; klíč založit kvůli konzistenci extrakce (nebo ponechat literál — rozhodnutí orchestrátora)
  ///
  /// In cs, this message translates to:
  /// **'AGPL-3.0'**
  String get settingsLicenseSubtitle;

  /// Titulek dlaždice — otevře privacyUrl
  ///
  /// In cs, this message translates to:
  /// **'Zásady ochrany soukromí'**
  String get settingsPrivacyPolicyTitle;

  /// Podtitulek dlaždice Zásady ochrany soukromí; tykání
  ///
  /// In cs, this message translates to:
  /// **'Co o tobě víme (a co ne)'**
  String get settingsPrivacyPolicySubtitle;

  /// Titulek dlaždice — otevře termsUrl
  ///
  /// In cs, this message translates to:
  /// **'Podmínky použití'**
  String get settingsTermsTitle;

  /// Podtitulek dlaždice Podmínky použití — zobrazená lidsky čitelná URL; POZOR: cesta /podminky je česká, pro en/de/ru/it zvážit lokalizované URL nebo neutrální text
  ///
  /// In cs, this message translates to:
  /// **'sepot.cz/podminky'**
  String get settingsTermsSubtitle;

  /// Titulek dlaždice — otevře deletionUrl
  ///
  /// In cs, this message translates to:
  /// **'Smazání dat'**
  String get settingsDataDeletionTitle;

  /// Podtitulek dlaždice Smazání dat
  ///
  /// In cs, this message translates to:
  /// **'Jak požádat o výmaz'**
  String get settingsDataDeletionSubtitle;

  /// Červené OutlinedButton dole na obrazovce — otevře potvrzovací dialog smazání účtu
  ///
  /// In cs, this message translates to:
  /// **'Smazat všechna data'**
  String get settingsDeleteAllDataButton;

  /// Obsah AlertDialogu Licence (plní nabídku zdrojáku dle AGPL § 6); v kódu 3 adjacentní literály přes ř. 243-246 — sloučit do jednoho klíče s placeholder supportEmail
  ///
  /// In cs, this message translates to:
  /// **'Šepot je šířen pod licencí GNU Affero General Public License verze 3 (AGPL-3.0). Používá knihovnu libsignal, rovněž AGPL-3.0.\n\nO zdrojový kód odpovídající této verzi si můžeš napsat na {supportEmail} a pošleme ti ho.'**
  String settingsLicenseBody(String supportEmail);

  /// Tlačítko zavření dialogu Licence; stejný text ř. 574 (seed fráze) a ř. 619 (about) — jeden common klíč | Tlačítko zavření dialogu seed fráze — společný klíč | Tlačítko zavření about dialogu — společný klíč
  ///
  /// In cs, this message translates to:
  /// **'Zavřít'**
  String get commonClose;

  /// SnackBar po tapnutí na Šepot ID v profilové kartě (kopie do schránky)
  ///
  /// In cs, this message translates to:
  /// **'ID zkopírováno'**
  String get settingsIdCopied;

  /// Kryptografický otisk identity v profilové kartě nahoře | Řádek s bezpečnostním otiskem (fingerprint) identity v potvrzovacím dialogu nového kontaktu. | Popisek kryptografického otisku pod jménem uživatele (monospace styl)
  ///
  /// In cs, this message translates to:
  /// **'Otisk: {fingerprint}'**
  String settingsFingerprint(String fingerprint);

  /// Subject share_plus při sdílení souboru zálohy — vidí uživatel v systémovém share sheetu / e-mailu
  ///
  /// In cs, this message translates to:
  /// **'Šepot — šifrovaná záloha'**
  String get backupShareSubject;

  /// SnackBar při chybě exportu zálohy
  ///
  /// In cs, this message translates to:
  /// **'Záloha selhala: {error}'**
  String backupExportFailed(String error);

  /// SnackBar po úspěšném importu zálohy historie.
  ///
  /// In cs, this message translates to:
  /// **'{count, plural, one{Obnovena 1 konverzace ze zálohy} few{Obnoveny {count} konverzace ze zálohy} many{Obnoveno {count} konverzace ze zálohy} other{Obnoveno {count} konverzací ze zálohy}}'**
  String backupRestoredCount(int count);

  /// SnackBar při chybě importu zálohy
  ///
  /// In cs, this message translates to:
  /// **'Obnova ze zálohy selhala: {error}'**
  String backupImportFailed(String error);

  /// Vysvětlující text v dialogu nastavení nátlakového PINu; v kódu 2 adjacentní literály ř. 450-451 — sloučit
  ///
  /// In cs, this message translates to:
  /// **'Zadáním tohoto PINu se aplikace otevře prázdná — bez tvých kontaktů a zpráv. Musí být jiný než běžný PIN.'**
  String get settingsDecoyPinExplain;

  /// labelText druhého TextFieldu (potvrzení decoy PINu)
  ///
  /// In cs, this message translates to:
  /// **'Potvrdit'**
  String get commonConfirm;

  /// Potvrzovací tlačítko dialogu nátlakového PINu (uloží PIN)
  ///
  /// In cs, this message translates to:
  /// **'Nastavit'**
  String get commonSet;

  /// SnackBar po úspěšném nastavení nátlakového PINu
  ///
  /// In cs, this message translates to:
  /// **'Nátlakový PIN nastaven'**
  String get settingsDecoyPinEnabled;

  /// SnackBar při DecoyPinConflict (decoy PIN == hlavní PIN); výjimka sama je v secure_storage.dart, hláška ale vzniká tady v UI
  ///
  /// In cs, this message translates to:
  /// **'Nátlakový PIN musí být jiný než běžný'**
  String get settingsDecoyPinConflict;

  /// SnackBar po deaktivaci nátlakového PINu
  ///
  /// In cs, this message translates to:
  /// **'Nátlakový PIN zrušen'**
  String get settingsDecoyPinDisabled;

  /// SnackBar, když storage nevrátí seed frázi
  ///
  /// In cs, this message translates to:
  /// **'Zálohovací fráze nebyla nalezena'**
  String get settingsSeedPhraseNotFound;

  /// Varování v dialogu seed fráze; 2 adjacentní literály ř. 547-548 — sloučit; POZOR gramatická chyba v originálu: správně 'Tato slova' — v cs ARB opravit
  ///
  /// In cs, this message translates to:
  /// **'Tato slova jsou jedinou zálohou tvé identity. Nikomu je neukazuj!'**
  String get settingsSeedPhraseWarning;

  /// Label Chipu s jedním slovem seed fráze ve formátu '1. slovo'; formát je jazykově neutrální — možno ponechat i bez ARB, ale pro RU/DE typografii raději klíč s placeholders
  ///
  /// In cs, this message translates to:
  /// **'{index}. {word}'**
  String settingsSeedWordChip(int index, String word);

  /// Nadpis v about dialogu; 'Šepot' je brand, podtitul 'Soukromý Messenger' se překládá
  ///
  /// In cs, this message translates to:
  /// **'Šepot — Soukromý Messenger'**
  String get settingsAboutTagline;

  /// Tělo about dialogu; 6 adjacentních literálů ř. 601-606 — sloučit do jednoho víceřádkového klíče; názvy algoritmů a copyright zůstávají, překládají se jen popisky v závorkách a úvodní věta
  ///
  /// In cs, this message translates to:
  /// **'E2E šifrovaný messenger s otevřeným zdrojovým kódem.\n\nKryptografie:\n• X25519 (výměna klíčů)\n• XChaCha20-Poly1305 (šifrování)\n• Ed25519 (podpisy)\n\n© 2026 ajtak.it'**
  String get settingsAboutBody;

  /// Title potvrzovacího AlertDialogu smazání účtu
  ///
  /// In cs, this message translates to:
  /// **'Smazat účet a všechna data?'**
  String get settingsDeleteAccountTitle;

  /// Tělo potvrzovacího dialogu smazání účtu; 3 adjacentní literály ř. 632-634 — sloučit; tykání
  ///
  /// In cs, this message translates to:
  /// **'Tato akce je nevratná. Všechny zprávy, kontakty a klíče budou smazány z tohoto zařízení a účet bude odregistrován ze serveru. Pokud nemáš zálohovací frázi, přijdeš o svou identitu.'**
  String get settingsDeleteAccountBody;

  /// SnackBar (8 s) po smazání dat, když serverová deregistrace selhala; 3 adjacentní literály ř. 657-659 — sloučit; obsahuje natvrdo e-mail podpora@sepot.cz — zvážit placeholder z AppConstants.supportEmail místo literálu
  ///
  /// In cs, this message translates to:
  /// **'Server je teď nedostupný — data v zařízení jsou smazaná, registrace na serveru zůstala. Zbytek smažeme na podpora@sepot.cz.'**
  String get settingsDeleteAccountServerOffline;

  /// Červené potvrzovací tlačítko dialogu smazání účtu — provede nevratné smazání
  ///
  /// In cs, this message translates to:
  /// **'Smazat vše'**
  String get settingsDeleteAllConfirm;

  /// SnackBar po neúspěšném založení skupiny (výjimka z createGroup) — $e je surová výjimka, překladatel překládá jen úvod věty
  ///
  /// In cs, this message translates to:
  /// **'Skupinu se nepovedlo založit: {error}'**
  String groupsCreateFailed(String error);

  /// Titulek AppBaru obrazovky založení skupiny | Tooltip ikony (group_add) v AppBaru — otevře vytvoření skupiny
  ///
  /// In cs, this message translates to:
  /// **'Nová skupina'**
  String get groupsNewGroupTitle;

  /// Akční tlačítko v AppBaru — potvrzení založení skupiny (sloveso, krátké)
  ///
  /// In cs, this message translates to:
  /// **'Založit'**
  String get groupsCreateAction;

  /// Nadpis sekce seznamu kontaktů s počítadlem vybraných členů vs. maxima, formát 'Členové (3/15)'. Počet je jen v závorce jako poměr — slovo 'Členové' se neskloňuje podle počtu, ICU plural není nutný, stačí dva placeholdery.
  ///
  /// In cs, this message translates to:
  /// **'Členové ({selectedCount}/{maxMembers})'**
  String groupsMembersCounter(int selectedCount, int maxMembers);

  /// Prázdný stav — uživatel nemá žádné (neblokované) kontakty, ze kterých by šlo skupinu složit. POZOR: v kódu dva adjacentní literály na řádcích 121–122, sloučit do jednoho klíče (text zde už sloučený, mezera je na konci prvního literálu).
  ///
  /// In cs, this message translates to:
  /// **'Nejdřív si přidej kontakty — skupina se skládá z lidí, se kterými si už můžeš psát.'**
  String get groupsEmptyContactsHint;

  /// Podtitulek zašedlého (nevybratelného) kontaktu v seznamu — kontakt nemá routing (accountId/deliveryAddress), nelze ho přidat do skupiny
  ///
  /// In cs, this message translates to:
  /// **'Chybí doručovací adresa — požádej o nový odkaz'**
  String get groupsMemberMissingAddress;

  /// Velikost přílohy-dokumentu na kartě v chatu, varianta pod 1 kB (např. '512 B')
  ///
  /// In cs, this message translates to:
  /// **'{bytes} B'**
  String attachmentSizeBytes(int bytes);

  /// Velikost přílohy-dokumentu na kartě v chatu, varianta kB (např. '38 kB'). Ruština používá 'КБ'.
  ///
  /// In cs, this message translates to:
  /// **'{kilobytes} kB'**
  String attachmentSizeKb(String kilobytes);

  /// Velikost přílohy-dokumentu na kartě v chatu, varianta MB (např. '2.3 MB'). Ruština používá 'МБ'; desetinný oddělovač by měl respektovat locale.
  ///
  /// In cs, this message translates to:
  /// **'{megabytes} MB'**
  String attachmentSizeMb(String megabytes);

  /// Overlay přes thumbnail obrázkové přílohy, když stažení blobu selhalo; klepnutí spustí retry. STEJNÝ text i na ř. 464 (karta dokumentu) → jeden klíč. | Podtitulek karty dokumentu ve stavu failed (jinak se zobrazuje velikost formatBytes). Duplikát textu z ř. 134 → stejný klíč.
  ///
  /// In cs, this message translates to:
  /// **'Stažení selhalo — klepni pro opakování'**
  String get attachmentDownloadFailedTapToRetry;

  /// Řádek hlasové zprávy v bublině, když stažení audio blobu selhalo (stav failed)
  ///
  /// In cs, this message translates to:
  /// **'Stažení selhalo'**
  String get attachmentDownloadFailed;

  /// Řádek hlasové zprávy v bublině během stahování blobu (stav pending/downloading), vedle spinneru
  ///
  /// In cs, this message translates to:
  /// **'Stahuji…'**
  String get attachmentDownloading;

  /// Fallback název souboru (malé písmeno) předaný do XFile.fromData při sdílení dokumentu přes systémový share sheet (share_plus) — uživatel ho vidí jako název sdíleného souboru
  ///
  /// In cs, this message translates to:
  /// **'soubor'**
  String get attachmentSharedFileFallbackName;

  /// SnackBar při výjimce během dešifrování/sdílení dokumentové přílohy
  ///
  /// In cs, this message translates to:
  /// **'Otevření přílohy selhalo: {error}'**
  String attachmentOpenFailed(String error);

  /// Fallback názvu dokumentu na kartě přílohy, když meta.name je null. Stejný text jako fallback v chat_list_tile.dart ř. 169 → sdílený common klíč. | Fallback názvu souboru vnořený v interpolaci na ř. 169, když msg.fileName je null. Stejný text jako attachment_content.dart ř. 452 → sdílený common klíč.
  ///
  /// In cs, this message translates to:
  /// **'Soubor'**
  String get commonFile;

  /// Náhled poslední zprávy v dlaždici seznamu chatů, když konverzace zatím nemá žádnou zprávu
  ///
  /// In cs, this message translates to:
  /// **'Nová konverzace'**
  String get chatListNewConversation;

  /// Náhled poslední zprávy v dlaždici pro zprávu typu readReceipt (potvrzení o přečtení)
  ///
  /// In cs, this message translates to:
  /// **'Přečteno'**
  String get chatListReadReceiptPreview;

  /// Předpona náhledu v seznamu chatů, když je v chatu rozepsaná zpráva
  ///
  /// In cs, this message translates to:
  /// **'Koncept'**
  String get chatListDraft;

  /// Název chatu se sebou samým (seznam chatů, hlavička, kontakty, přeposlání)
  ///
  /// In cs, this message translates to:
  /// **'Poznámky pro sebe'**
  String get notesTitle;

  /// Podtitulek poznámek pro sebe — nic se neodesílá na server
  ///
  /// In cs, this message translates to:
  /// **'Jen v tomto telefonu, šifrovaně'**
  String get notesSubtitle;

  /// Tlačítko hlasového hovoru v hlavičce chatu
  ///
  /// In cs, this message translates to:
  /// **'Zavolat'**
  String get callVoice;

  /// Tlačítko videohovoru v hlavičce chatu
  ///
  /// In cs, this message translates to:
  /// **'Videohovor'**
  String get callVideo;

  /// Stav odchozího hovoru, dokud protistrana nezvedne
  ///
  /// In cs, this message translates to:
  /// **'Vyzvání…'**
  String get callStatusRinging;

  /// Stav příchozího hlasového hovoru
  ///
  /// In cs, this message translates to:
  /// **'Příchozí hovor'**
  String get callIncomingVoice;

  /// Stav příchozího videohovoru
  ///
  /// In cs, this message translates to:
  /// **'Příchozí videohovor'**
  String get callIncomingVideo;

  /// Stav po přijetí, než naběhne spojení
  ///
  /// In cs, this message translates to:
  /// **'Spojuji…'**
  String get callStatusConnecting;

  /// Krátce po konci hovoru
  ///
  /// In cs, this message translates to:
  /// **'Hovor skončil'**
  String get callEnded;

  /// Protistrana má jiný hovor
  ///
  /// In cs, this message translates to:
  /// **'Obsazeno'**
  String get callEndedBusy;

  /// Hovor byl odmítnut
  ///
  /// In cs, this message translates to:
  /// **'Hovor odmítnut'**
  String get callEndedRejected;

  /// Odchozí hovor vypršel bez odpovědi
  ///
  /// In cs, this message translates to:
  /// **'Nikdo to nevzal'**
  String get callEndedUnanswered;

  /// Hovor se nepodařilo spojit
  ///
  /// In cs, this message translates to:
  /// **'Spojení se nepodařilo'**
  String get callEndedFailed;

  /// Podtitulek na obrazovce hovoru
  ///
  /// In cs, this message translates to:
  /// **'Šifrováno end-to-end'**
  String get callEncrypted;

  /// Přijetí příchozího hovoru
  ///
  /// In cs, this message translates to:
  /// **'Přijmout'**
  String get callAccept;

  /// Odmítnutí příchozího hovoru
  ///
  /// In cs, this message translates to:
  /// **'Odmítnout'**
  String get callReject;

  /// Přepínač mikrofonu (popisek pro čtečku)
  ///
  /// In cs, this message translates to:
  /// **'Ztlumit mikrofon'**
  String get callMute;

  /// Přepínač hlasitého odposlechu
  ///
  /// In cs, this message translates to:
  /// **'Reproduktor'**
  String get callSpeaker;

  /// Přepínač kamery ve videohovoru
  ///
  /// In cs, this message translates to:
  /// **'Vypnout kameru'**
  String get callCamera;

  /// Přední/zadní kamera
  ///
  /// In cs, this message translates to:
  /// **'Přepnout kameru'**
  String get callSwitchCamera;

  /// Ukončení hovoru
  ///
  /// In cs, this message translates to:
  /// **'Zavěsit'**
  String get callHangUp;

  /// Záznam v chatu
  ///
  /// In cs, this message translates to:
  /// **'Zmeškaný hovor'**
  String get callLogMissed;

  /// Odchozí hovor, který protistrana nevzala
  ///
  /// In cs, this message translates to:
  /// **'Nepřijatý hovor'**
  String get callLogUnanswered;

  /// Záznam v chatu
  ///
  /// In cs, this message translates to:
  /// **'Odmítnutý hovor'**
  String get callLogRejected;

  /// Záznam v chatu — protistrana měla jiný hovor
  ///
  /// In cs, this message translates to:
  /// **'Obsazeno'**
  String get callLogBusy;

  /// Záznam v chatu
  ///
  /// In cs, this message translates to:
  /// **'Hovor se nespojil'**
  String get callLogFailed;

  /// Záznam proběhlého hlasového hovoru s délkou
  ///
  /// In cs, this message translates to:
  /// **'Hovor · {duration}'**
  String callLogVoice(String duration);

  /// Záznam proběhlého videohovoru s délkou
  ///
  /// In cs, this message translates to:
  /// **'Videohovor · {duration}'**
  String callLogVideo(String duration);

  /// Relativní čas poslední zprávy v dlaždici, méně než 1 minuta
  ///
  /// In cs, this message translates to:
  /// **'teď'**
  String get chatListTimeNow;

  /// Relativní čas poslední zprávy v dlaždici, méně než hodina (např. '12 min'). Zkratka 'min' se česky neskloňuje, ale doporučuji ICU plural pro jistotu jiných jazyků (ru).
  ///
  /// In cs, this message translates to:
  /// **'{minutes} min'**
  String chatListTimeMinutes(int minutes);

  /// Titulek AppBaru obrazovky QR skeneru pro přidání kontaktu. | Tooltip ikony QR skeneru v AppBaru kontaktů
  ///
  /// In cs, this message translates to:
  /// **'Skenovat QR kód'**
  String get qrScanTitle;

  /// Hlavní instrukce ve spodním panelu skeneru (tykání — sjednotit tón napříč appkou).
  ///
  /// In cs, this message translates to:
  /// **'Namiř kameru na QR kód kontaktu'**
  String get qrScanInstruction;

  /// Sekundární vysvětlující text pod instrukcí ve spodním panelu skeneru.
  ///
  /// In cs, this message translates to:
  /// **'QR kód obsahuje veřejný klíč kontaktu'**
  String get qrScanHint;

  /// Titulek potvrzovacího AlertDialogu po naskenování platného QR kódu kontaktu.
  ///
  /// In cs, this message translates to:
  /// **'Nový kontakt'**
  String get qrNewContactTitle;

  /// SnackBar po úspěšném přidání kontaktu z QR. POZOR: gender tvar „přidán/a“ — v EN/DE/RU/IT přeformulovat neutrálně (např. „Kontakt {name} přidán“ / „{name} added“).
  ///
  /// In cs, this message translates to:
  /// **'{name} přidán/a'**
  String qrContactAdded(String name);

  /// Potvrzovací tlačítko (ElevatedButton) v dialogu nového kontaktu — obecné „Přidat“, vhodný common klíč. | Potvrzovací ElevatedButton dialogu Přidat kontakt — obecné 'Přidat', kandidát na common klíč
  ///
  /// In cs, this message translates to:
  /// **'Přidat'**
  String get commonAdd;

  /// Nadpis 1. onboarding stránky (uvítání) pod logem
  ///
  /// In cs, this message translates to:
  /// **'Vítej v Šepotu'**
  String get onboardingWelcomeTitle;

  /// Podtitulek 1. onboarding stránky; v kódu 3 adjacentní literály s \n (ř. 97–99), sloučit do jednoho klíče
  ///
  /// In cs, this message translates to:
  /// **'Soukromý messenger s end-to-end šifrováním.\nŽádné telefonní číslo. Žádný email.\nJen tvoje klíče.'**
  String get onboardingWelcomeSubtitle;

  /// Hlavní tlačítko na 1. onboarding stránce — přejde na stránku o šifrování
  ///
  /// In cs, this message translates to:
  /// **'Začít'**
  String get onboardingStart;

  /// TextButton pod Začít, vede na /restore (obnova účtu ze seed fráze)
  ///
  /// In cs, this message translates to:
  /// **'Už mám účet — obnovit ze zálohovací fráze'**
  String get onboardingRestoreExisting;

  /// Nadpis 2. onboarding stránky (vysvětlení šifrování)
  ///
  /// In cs, this message translates to:
  /// **'Tvoje zprávy, tvoje klíče'**
  String get onboardingEncryptionTitle;

  /// Titulek feature řádku 1 na stránce o šifrování
  ///
  /// In cs, this message translates to:
  /// **'Signal protokol'**
  String get onboardingFeatureSignalTitle;

  /// Podtitulek feature řádku 1 (technické termíny, částečně nepřekládat)
  ///
  /// In cs, this message translates to:
  /// **'X3DH + Double Ratchet, forward secrecy'**
  String get onboardingFeatureSignalSubtitle;

  /// Titulek feature řádku 2
  ///
  /// In cs, this message translates to:
  /// **'Post-kvantová ochrana'**
  String get onboardingFeaturePqTitle;

  /// Podtitulek feature řádku 2
  ///
  /// In cs, this message translates to:
  /// **'Kyber (PQXDH) od první zprávy'**
  String get onboardingFeaturePqSubtitle;

  /// Titulek feature řádku 3
  ///
  /// In cs, this message translates to:
  /// **'Klíče jen na tvém zařízení'**
  String get onboardingFeatureLocalKeysTitle;

  /// Podtitulek feature řádku 3 (odkazuje na klíče z titulku)
  ///
  /// In cs, this message translates to:
  /// **'Žádný server je nemá'**
  String get onboardingFeatureLocalKeysSubtitle;

  /// Podtitulek feature řádku 4 (podmět = zprávy z titulku)
  ///
  /// In cs, this message translates to:
  /// **'Automaticky se smaží'**
  String get onboardingFeatureDisappearingSubtitle;

  /// Tlačítko na 2. onboarding stránce; stejný text i na ř. 351 — sdílený common klíč | Tlačítko po potvrzení uložení seed fráze — pokračuje na /pin-setup; sdílené s ř. 185
  ///
  /// In cs, this message translates to:
  /// **'Pokračovat'**
  String get commonContinue;

  /// Nadpis 3. onboarding stránky (vytvoření identity)
  ///
  /// In cs, this message translates to:
  /// **'Vytvoř svoji identitu'**
  String get onboardingIdentityTitle;

  /// Podtitulek 3. onboarding stránky
  ///
  /// In cs, this message translates to:
  /// **'Žádný email ani telefon. Jen jméno a kryptografické klíče.'**
  String get onboardingIdentitySubtitle;

  /// labelText TextFieldu pro jméno uživatele při vytváření identity | labelText pole pro jméno na obrazovce obnovy. Pravděpodobně stejný text i na setup obrazovce — kandidát na common klíč (commonDisplayName), sjednotit s inventurou onboardingu.
  ///
  /// In cs, this message translates to:
  /// **'Zobrazované jméno'**
  String get onboardingDisplayNameLabel;

  /// hintText TextFieldu pro jméno — lokalizovat na typické místní jméno | hintText pole pro jméno (příklad jména — pro každý jazyk zvolit lokální jméno, např. 'e.g. John')
  ///
  /// In cs, this message translates to:
  /// **'Např. Jan'**
  String get onboardingDisplayNameHint;

  /// Varování nad mřížkou seed slov; adjacentní literály ř. 281–282 sloučit; počet slov se česky skloňuje (slovo/slova/slov)
  ///
  /// In cs, this message translates to:
  /// **'Zapiš si těchto {count} slov. Jsou jedinou zálohou tvých klíčů!'**
  String onboardingSeedPhraseWarning(int count);

  /// Titulek CheckboxListTile — potvrzení uložení seed fráze; gender-neutrální tvar uložil/a, řešit i v překladech
  ///
  /// In cs, this message translates to:
  /// **'Potvrzuji, že jsem si frázi bezpečně uložil/a'**
  String get onboardingSeedSavedConfirm;

  /// Tlačítko generování identity (disabled dokud není jméno); text tlačítka referencován i v komentáři ř. 265
  ///
  /// In cs, this message translates to:
  /// **'Vygenerovat klíče'**
  String get onboardingGenerateKeys;

  /// Titulek AlertDialogu po skenu QR, když čísla nesouhlasí (varování, CAPS záměrně)
  ///
  /// In cs, this message translates to:
  /// **'Čísla NESOUHLASÍ'**
  String get verifyMismatchTitle;

  /// Obsah dialogu při shodě bezpečnostních čísel
  ///
  /// In cs, this message translates to:
  /// **'Klíče si odpovídají. {contactName} je ověřený kontakt.'**
  String verifyMatchBody(String contactName);

  /// Obsah dialogu při neshodě — varování před MITM; adjacentní literály ř. 91–93 sloučit do jednoho klíče
  ///
  /// In cs, this message translates to:
  /// **'Bezpečnostní čísla nesedí. Někdo může odposlouchávat spojení (MITM), nebo skenuješ kód jiného kontaktu. NEposílej citlivé zprávy a ověřte se znovu jiným kanálem.'**
  String get verifyMismatchBody;

  /// Potvrzovací tlačítko dialogu s výsledkem ověření (shoda i neshoda)
  ///
  /// In cs, this message translates to:
  /// **'Rozumím'**
  String get commonUnderstood;

  /// Titulek potvrzovacího dialogu při ručním označení kontaktu jako ověřeného
  ///
  /// In cs, this message translates to:
  /// **'Označit jako ověřené?'**
  String get verifyManualConfirmTitle;

  /// Obsah potvrzovacího dialogu ručního ověření; adjacentní literály ř. 111–112 sloučit; gender tvar porovnal/a
  ///
  /// In cs, this message translates to:
  /// **'Potvrď jen v případě, že sis číslice porovnal/a s protistranou jiným důvěryhodným kanálem (osobně, hovorem…) a souhlasí.'**
  String get verifyManualConfirmBody;

  /// Potvrzovací FilledButton dialogu ručního ověření
  ///
  /// In cs, this message translates to:
  /// **'Souhlasí, ověřit'**
  String get verifyManualConfirmAction;

  /// AppBar titulek obrazovky ověření kontaktu (loading fallback stav) | AppBar titulek hlavního stavu obrazovky — stejný klíč jako ř. 140
  ///
  /// In cs, this message translates to:
  /// **'Ověření kontaktu'**
  String get verifyTitle;

  /// Zelený banner nahoře na obrazovce, když je kontakt už ověřený
  ///
  /// In cs, this message translates to:
  /// **'Kontakt je ověřený'**
  String get verifyContactVerifiedBanner;

  /// Úvodní vysvětlující text obrazovky nad QR kódem; adjacentní literály ř. 177–179 sloučit
  ///
  /// In cs, this message translates to:
  /// **'Porovnej toto číslo s {contactName}. Když souhlasí, vaše šifrování nikdo neodposlouchává. Nejrychlejší je vzájemně si naskenovat QR kódy.'**
  String verifyIntro(String contactName);

  /// FilledButton — otevře skener QR kódu protistrany
  ///
  /// In cs, this message translates to:
  /// **'Naskenovat kód protistrany'**
  String get verifyScanButton;

  /// OutlinedButton — otevře dialog ručního potvrzení shody číslic
  ///
  /// In cs, this message translates to:
  /// **'Číslice souhlasí — označit ručně'**
  String get verifyManualButton;

  /// TextButton viditelný jen u ověřeného kontaktu — zruší stav ověření
  ///
  /// In cs, this message translates to:
  /// **'Zrušit ověření'**
  String get verifyUnverifyButton;

  /// AppBar titulek minimalistické skener obrazovky (_VerifyScanScreen)
  ///
  /// In cs, this message translates to:
  /// **'Naskenuj ověřovací QR'**
  String get verifyScanScreenTitle;

  /// Titulek AppBaru obrazovky nahlášení zneužití
  ///
  /// In cs, this message translates to:
  /// **'Nahlásit'**
  String get reportTitle;

  /// Nadpis úspěšné obrazovky po odeslání hlášení
  ///
  /// In cs, this message translates to:
  /// **'Hlášení odesláno'**
  String get reportSubmitted;

  /// Text pod nadpisem úspěchu, jen pro kategorii ohrožení dítěte; obsahuje česká čísla tísňových linek (158, 116 111) — překladatel musí zvážit lokální ekvivalenty
  ///
  /// In cs, this message translates to:
  /// **'Hlášení řešíme přednostně. Pokud je dítě v bezprostředním ohrožení, zavolej 158 nebo linku 116 111.'**
  String get reportSubmittedChildSafety;

  /// Text pod nadpisem úspěchu pro běžné kategorie hlášení
  ///
  /// In cs, this message translates to:
  /// **'Díky. Podíváme se na to co nejdřív.'**
  String get reportSubmittedThanks;

  /// Tlačítko zavírající úspěšnou obrazovku hlášení; obecný text, pravděpodobně sdílený s dalšími obrazovkami
  ///
  /// In cs, this message translates to:
  /// **'Hotovo'**
  String get commonDone;

  /// Informační panel nahoře ve formuláři hlášení — vysvětluje, že provozovatel obsah zpráv nevidí; adjacentní literály ř. 133-136
  ///
  /// In cs, this message translates to:
  /// **'Zprávy jsou end-to-end šifrované, takže jejich obsah nevidíme ani teď. Popiš prosím vlastními slovy, co se stalo. Nevkládej sem obsah zpráv ani odkazy na něj — nesmíme ho držet a k posouzení ho nepotřebujeme.'**
  String get reportPanelE2eNotice;

  /// Varovný panel zobrazený jen při kategorii ohrožení dítěte; odkazuje na české instituce (STOPonline.cz, Policie ČR 158) — překladatel musí zvážit lokalizaci hotline; adjacentní literály ř. 143-147
  ///
  /// In cs, this message translates to:
  /// **'Materiál zobrazující zneužívání dítěte nám NEPOSÍLEJ. Jeho držení je trestné i pro nás a pro nahlášení ho nepotřebujeme. Materiál patří přímo na STOPonline.cz nebo Policii ČR (158). Nám napiš jen to, co se stalo — zablokujeme účet a předáme věc dál.'**
  String get reportPanelCsamWarning;

  /// Panel upozorňující, že odeslání hlášení odhalí IP adresu (jde mimo relay); adjacentní literály ř. 154-155
  ///
  /// In cs, this message translates to:
  /// **'Hlášení nejde přes relay, ale na náš webový server. Ten se při odeslání dozví tvou IP adresu.'**
  String get reportPanelIpNotice;

  /// Nadpis sekce s výběrem kategorie hlášení (radio volby)
  ///
  /// In cs, this message translates to:
  /// **'Čeho se hlášení týká'**
  String get reportCategoryHeading;

  /// Nadpis sekce nad textovým polem popisu incidentu
  ///
  /// In cs, this message translates to:
  /// **'Co se stalo'**
  String get reportDescriptionHeading;

  /// Titulek přepínače SwitchListTile — varianta bez jména kontaktu (reportedName == null)
  ///
  /// In cs, this message translates to:
  /// **'Přiložit ID nahlášeného kontaktu'**
  String get reportAttachContactId;

  /// Titulek přepínače SwitchListTile — varianta se jménem nahlášeného kontaktu; společně s reportAttachContactId tvoří pár, v ARB dva samostatné klíče
  ///
  /// In cs, this message translates to:
  /// **'Přiložit ID kontaktu {contactName}'**
  String reportAttachContactIdNamed(String contactName);

  /// Nadpis sekce nad nepovinným polem pro kontaktní e-mail oznamovatele
  ///
  /// In cs, this message translates to:
  /// **'Kontakt na tebe (nepovinné)'**
  String get reportReplyToHeading;

  /// hintText TextFieldu pro kontaktní e-mail oznamovatele
  ///
  /// In cs, this message translates to:
  /// **'e-mail, kdybychom se potřebovali doptat'**
  String get reportReplyToHint;

  /// Hlavní FilledButton odesílající formulář hlášení
  ///
  /// In cs, this message translates to:
  /// **'Odeslat hlášení'**
  String get reportSubmitButton;

  /// Titulek AppBaru obrazovky kontaktů
  ///
  /// In cs, this message translates to:
  /// **'Kontakty'**
  String get contactsTitle;

  /// Tooltip ikony person_add v AppBaru; STEJNÝ text je i titulek dialogu na ř. 210 — použít jeden klíč | Titulek AlertDialogu pro ruční přidání kontaktu — stejný klíč jako tooltip na ř. 49
  ///
  /// In cs, this message translates to:
  /// **'Přidat kontakt'**
  String get contactsAddContact;

  /// hintText vyhledávacího TextFieldu nad seznamem kontaktů
  ///
  /// In cs, this message translates to:
  /// **'Hledat kontakt...'**
  String get contactsSearchHint;

  /// Prázdný stav seznamu, když uživatel nemá žádné kontakty (a nehledá)
  ///
  /// In cs, this message translates to:
  /// **'Zatím žádné kontakty'**
  String get contactsEmpty;

  /// Prázdný stav při aktivním vyhledávání bez shody
  ///
  /// In cs, this message translates to:
  /// **'Žádné výsledky'**
  String get contactsNoResults;

  /// Titulek karty nad seznamem kontaktů — proklik na sdílení vlastního QR. Pozor: 'Šepot' je název aplikace, v překladech zůstává 'Šepot ID'
  ///
  /// In cs, this message translates to:
  /// **'Sdílej svůj Šepot ID'**
  String get contactsShareCardTitle;

  /// Podtitulek karty sdílení vlastního Šepot ID
  ///
  /// In cs, this message translates to:
  /// **'Ukaž QR kód nebo pošli odkaz'**
  String get contactsShareCardSubtitle;

  /// Instrukční text v těle dialogu Přidat kontakt
  ///
  /// In cs, this message translates to:
  /// **'Vlož sdílený řetězec (share string) kontaktu:'**
  String get contactsAddDialogPrompt;

  /// hintText TextFieldu v dialogu Přidat kontakt (vkládá se share string)
  ///
  /// In cs, this message translates to:
  /// **'Vložit share string...'**
  String get contactsShareStringHint;

  /// SnackBar, když se vložený text nepodaří parsovat jako PublicIdentity share string
  ///
  /// In cs, this message translates to:
  /// **'Neplatný share string'**
  String get contactsInvalidShareString;

  /// SnackBar po úspěšném přidání kontaktu. Pozor pro překladatele: 'přidán' je mužský rod od slova kontakt (ne gender osoby) — v en/de/ru/it bez problému
  ///
  /// In cs, this message translates to:
  /// **'Kontakt {name} přidán'**
  String contactsAdded(String name);

  /// Podtitulek položky Ověřit kontakt v bottom sheetu
  ///
  /// In cs, this message translates to:
  /// **'Porovnání bezpečnostního čísla'**
  String get verifyContactSubtitle;

  /// Destruktivní položka v bottom sheetu (long-press na kontakt) — smaže kontakt bez potvrzení
  ///
  /// In cs, this message translates to:
  /// **'Smazat kontakt'**
  String get contactsDeleteContact;

  /// Titulek obrazovky nastavení PINu ve fázi potvrzení (druhé zadání PINu při onboardingu)
  ///
  /// In cs, this message translates to:
  /// **'Potvrď PIN'**
  String get pinConfirmTitle;

  /// Titulek obrazovky nastavení PINu při prvním zadání (onboarding)
  ///
  /// In cs, this message translates to:
  /// **'Nastav si PIN'**
  String get pinSetupTitle;

  /// Podtitulek pod titulkem ve fázi potvrzení PINu
  ///
  /// In cs, this message translates to:
  /// **'Zadej PIN znovu pro potvrzení'**
  String get pinConfirmSubtitle;

  /// Podtitulek při prvním zadání PINu — vysvětluje účel (odemknutí aplikace, 6 číslic)
  ///
  /// In cs, this message translates to:
  /// **'6-místný PIN pro odemknutí aplikace'**
  String get pinSetupSubtitle;

  /// Červená chybová hláška pod PIN tečkami, když enablePin() (Argon2id wrap DEK) vyhodí výjimku
  ///
  /// In cs, this message translates to:
  /// **'Nastavení PINu selhalo. Zkus to znovu.'**
  String get pinSetupFailed;

  /// Červená chybová hláška pod PIN tečkami, když se potvrzovací PIN liší od prvního zadání (onboarding). Pozor: change_pin_screen má kratší variantu 'PINy se neshodují.' — jiný klíč.
  ///
  /// In cs, this message translates to:
  /// **'PINy se neshodují. Zkus to znovu.'**
  String get pinMismatchRetry;

  /// Titulek kroku 1 změny PINu (ověření starého PINu) — z konstantní mapy _titulky, record (titulek, popis)
  ///
  /// In cs, this message translates to:
  /// **'Zadej současný PIN'**
  String get pinChangeCurrentTitle;

  /// Podtitulek kroku 1 změny PINu — vysvětluje, že se PIN ověřuje unwrapem DEK, ne hashem
  ///
  /// In cs, this message translates to:
  /// **'Ověříme ho odemčením klíče'**
  String get pinChangeCurrentSubtitle;

  /// Titulek kroku 2 změny PINu (zadání nového PINu)
  ///
  /// In cs, this message translates to:
  /// **'Zadej nový PIN'**
  String get pinChangeNewTitle;

  /// Podtitulek kroku 2 změny PINu — délka PINu. Pozn.: obsahuje číslovku 6 napevno v textu (není interpolovaná), česky '6 číslic' — ICU plural není nutný, číslo je fixní.
  ///
  /// In cs, this message translates to:
  /// **'6 číslic'**
  String get pinChangeNewSubtitle;

  /// Titulek kroku 3 změny PINu (potvrzení nového PINu)
  ///
  /// In cs, this message translates to:
  /// **'Potvrď nový PIN'**
  String get pinChangeConfirmTitle;

  /// Podtitulek kroku 3 změny PINu
  ///
  /// In cs, this message translates to:
  /// **'Zadej ho ještě jednou'**
  String get pinChangeConfirmSubtitle;

  /// Červená chybová hláška, když verifyPin() (krok 1) selže — starý PIN neodemkl klíč. Stejný text i na řádku 119 (WrongPinException při changePin) — jeden klíč. | Duplicitní výskyt — WrongPinException při changePin(); stejný klíč jako řádek 76.
  ///
  /// In cs, this message translates to:
  /// **'Špatný PIN.'**
  String get pinWrong;

  /// Červená chybová hláška v kroku 2, když nový PIN == starý PIN
  ///
  /// In cs, this message translates to:
  /// **'Nový PIN se musí lišit od současného.'**
  String get pinChangeMustDiffer;

  /// Červená chybová hláška v kroku 3, když potvrzení != nový PIN. Pozor: pin_setup_screen má delší variantu 'PINy se neshodují. Zkus to znovu.' (pinMismatchRetry) — jiný klíč.
  ///
  /// In cs, this message translates to:
  /// **'PINy se neshodují.'**
  String get pinMismatch;

  /// Červená chybová hláška při DecoyPinConflict — nový PIN koliduje s decoy/nátlakovým PINem. Citlivá formulace (bezpečnostní funkce), překlad musí zachovat význam 'duress/decoy mode'.
  ///
  /// In cs, this message translates to:
  /// **'Tenhle PIN už patří nátlakovému režimu. Zvol jiný.'**
  String get pinDecoyConflict;

  /// Červená chybová hláška při obecné výjimce z changePin()
  ///
  /// In cs, this message translates to:
  /// **'Změna PINu selhala. Zkus to znovu.'**
  String get pinChangeFailed;

  /// SnackBar po úspěšné změně PINu, těsně před context.pop()
  ///
  /// In cs, this message translates to:
  /// **'PIN změněn'**
  String get pinChanged;

  /// Titulek celoobrazovkové chybové obrazovky (_ChybaApp), když selže init libsignal při startu
  ///
  /// In cs, this message translates to:
  /// **'Šifrovací jádro se nespustilo'**
  String get errorCryptoInitTitle;

  /// Titulek celoobrazovkové chybové obrazovky (_ChybaApp) při neodchycené chybě startu
  ///
  /// In cs, this message translates to:
  /// **'Šepot se nespustil'**
  String get errorStartupTitle;

  /// Nadpis náhradní ErrorWidget plochy (_ChybovaPlocha) v release buildu, když build() nějakého widgetu spadne
  ///
  /// In cs, this message translates to:
  /// **'Tahle obrazovka se nevykreslila'**
  String get errorScreenNotRenderedTitle;

  /// Vysvětlující text pod titulkem chybové obrazovky _ChybaApp; žádá uživatele o zkopírování detailu chyby. POZOR: v kódu jsou to DVA adjacentní literály (ř. 209–210: '…tenhle text ' + '(podrž prst…') — sloučit do jednoho klíče.
  ///
  /// In cs, this message translates to:
  /// **'Něco se pokazilo hned při startu. Pošli mi prosím tenhle text (podrž prst a zkopíruj) — pomůže mi to najít chybu.'**
  String get errorStartupBody;

  /// Patička chybové obrazovky _ChybaApp s kontaktem; 'sepot.cz' je doména — v překladech ponechat, přeložit jen výzvu
  ///
  /// In cs, this message translates to:
  /// **'sepot.cz · napiš mi na kontakt'**
  String get errorContactFooter;

  /// localizedReason systémové biometrické výzvy (local_auth) — zobrazuje OS v nativním dialogu otisku/Face. Stejný text jako nadpis obrazovky (ř. 63) → stejný klíč. | Nadpis odemykací obrazovky s PINem
  ///
  /// In cs, this message translates to:
  /// **'Odemkni Šepot'**
  String get pinUnlockTitle;

  /// Podtitulek odemykací obrazovky pod nadpisem
  ///
  /// In cs, this message translates to:
  /// **'Zadej PIN'**
  String get pinEnterPin;

  /// Label TextButton pod numpadem — ruční znovuvyvolání biometrické výzvy (viditelné jen se zapnutou biometrií)
  ///
  /// In cs, this message translates to:
  /// **'Odemknout biometrií'**
  String get pinUnlockWithBiometrics;

  /// Červená chybová hláška na odemykací obrazovce po zadání špatného PINu (WrongPinException)
  ///
  /// In cs, this message translates to:
  /// **'Špatný PIN'**
  String get pinWrong2;

  /// Červená chybová hláška na odemykací obrazovce při jiné chybě odemčení než špatný PIN
  ///
  /// In cs, this message translates to:
  /// **'Chyba odemčení'**
  String get pinUnlockError;

  /// Hláška na odemykací obrazovce po sérii špatných PINů; {seconds} = počet sekund do dalšího pokusu
  ///
  /// In cs, this message translates to:
  /// **'Příliš mnoho pokusů. Zkus to za {seconds} s.'**
  String pinLockedFor(int seconds);

  /// Titulek SimpleDialog výběru režimu pushů. Stejný text jako title ListTile v nastavení (ř. 184) → stejný klíč. | Title ListTile v nastavení — stejný text a klíč jako titulek dialogu (ř. 44)
  ///
  /// In cs, this message translates to:
  /// **'Push notifikace'**
  String get pushTitle;

  /// Popisek volby 'Vypnuto' v dialogu výběru režimu pushů
  ///
  /// In cs, this message translates to:
  /// **'Zprávy se stáhnou až po otevření appky.'**
  String get pushModeOffDesc;

  /// Label volby 'up' v dialogu výběru režimu pushů ('UnifiedPush' je název technologie — nepřekládat, přeložit jen '(bez Googlu)')
  ///
  /// In cs, this message translates to:
  /// **'UnifiedPush (bez Googlu)'**
  String get pushModeUp;

  /// Popisek volby UnifiedPush v dialogu výběru režimu pushů ('ntfy', 'F-Droid', 'Play' jsou názvy — nepřekládat)
  ///
  /// In cs, this message translates to:
  /// **'Degooglované — potřebuje aplikaci ntfy (F-Droid/Play).'**
  String get pushModeUpDesc;

  /// Label volby 'fcm' v dialogu výběru režimu pushů (vlastní název — pravděpodobně shodný ve všech jazycích, ale klíč mít)
  ///
  /// In cs, this message translates to:
  /// **'Google (FCM, výchozí)'**
  String get pushModeFcm;

  /// Popisek volby Google (FCM) v dialogu výběru režimu pushů. POZOR: v kódu DVA adjacentní literály (ř. 51–52: '…jde ' + 'Googlu; obsah…') — sloučit do jednoho klíče.
  ///
  /// In cs, this message translates to:
  /// **'Spolehlivé bez další aplikace. Push token zařízení jde Googlu; obsah zpráv nikdy.'**
  String get pushModeFcmDesc;

  /// SnackBar v nastavení, když přepnutí režimu pushů skončí výjimkou
  ///
  /// In cs, this message translates to:
  /// **'Nastavení pushů selhalo: {error}'**
  String pushSetupFailed(String error);

  /// Proužek nad seznamem chatů, když push není vůbec zapnutý.
  ///
  /// In cs, this message translates to:
  /// **'Zprávy ti přijdou, až Šepot otevřeš — budíčky nejsou nastavené.'**
  String get pushHintOff;

  /// Proužek nad seznamem chatů, když distributor registraci odmítl.
  ///
  /// In cs, this message translates to:
  /// **'Budíčky nefungují, zprávy uvidíš až po otevření Šepotu.'**
  String get pushHintFailed;

  /// Podtitulek dlaždice Push v Nastavení, když distributor odmítl registraci. Bez téhle hlášky uživatel vidí push jako zapnutý, ale zprávy mu chodí až po otevření appky.
  ///
  /// In cs, this message translates to:
  /// **'Budíčky nechodí — distributor registraci odmítl. Zkus push vypnout a znovu zapnout.'**
  String get pushRegistrationFailed;

  /// Titulek AlertDialog, když v systému není nainstalovaný žádný UnifiedPush distributor
  ///
  /// In cs, this message translates to:
  /// **'Žádný distributor'**
  String get pushNoDistributorTitle;

  /// Obsah AlertDialog 'Žádný distributor'. POZOR: v kódu DVA adjacentní literály (ř. 131–132) — sloučit do jednoho klíče. Názvy ntfy/UnifiedPush/F-Droid/Play nepřekládat.
  ///
  /// In cs, this message translates to:
  /// **'Pro degooglované notifikace nainstaluj UnifiedPush distributor, např. ntfy (F-Droid nebo Play). Pak push zapni znovu.'**
  String get pushNoDistributorBody;

  /// Potvrzovací tlačítko AlertDialog 'Žádný distributor' — obecné, sdílet napříč appkou
  ///
  /// In cs, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Titulek SimpleDialog výběru UnifiedPush distributora (položky jsou názvy balíčků z systému — nelokalizují se)
  ///
  /// In cs, this message translates to:
  /// **'Vyber distributora'**
  String get pushPickDistributorTitle;

  /// Subtitle ListTile v nastavení, když je aktivní režim UnifiedPush. SKLÁDANÝ TEXT: interpolace s vnořeným fallback literálem — placeholder distributor, fallback řešit buď předvyhodnocením (distributor ?? l10n.pushNoDistributorFallback) nebo ICU select. Nutné sloučení do jednoho klíče + samostatný klíč pro fallback.
  ///
  /// In cs, this message translates to:
  /// **'UnifiedPush · {distributor}'**
  String pushSubtitleUnifiedPush(String distributor);

  /// Vnořený fallback literál uvnitř subtitle 'UnifiedPush · …', když není vybraný žádný distributor — vyhodnotit před dosazením do pushSubtitleUnifiedPush
  ///
  /// In cs, this message translates to:
  /// **'bez distributora'**
  String get pushNoDistributorFallback;

  /// Subtitle ListTile v nastavení, když je aktivní režim FCM
  ///
  /// In cs, this message translates to:
  /// **'Google (FCM)'**
  String get pushSubtitleFcm;

  /// Validační chyba pod formulářem obnovy účtu, když je jméno prázdné
  ///
  /// In cs, this message translates to:
  /// **'Zadej zobrazované jméno.'**
  String get restoreErrorNameRequired;

  /// Chyba při obnově účtu: špatný počet slov v zadané frázi.
  ///
  /// In cs, this message translates to:
  /// **'{wordCount, plural, one{Fráze má 1 slovo, potřebuji {requiredWords}.} few{Fráze má {wordCount} slova, potřebuji {requiredWords}.} many{Fráze má {wordCount} slova, potřebuji {requiredWords}.} other{Fráze má {wordCount} slov, potřebuji {requiredWords}.}}'**
  String restoreErrorWordCount(int wordCount, int requiredWords);

  /// Validační chyba obnovy účtu — mnemonic checksum nesedí
  ///
  /// In cs, this message translates to:
  /// **'Fráze není platná — zkontroluj slova i jejich pořadí.'**
  String get restoreErrorInvalidPhrase;

  /// Chyba zobrazená pod formulářem, když recoverIdentity vyhodí výjimku
  ///
  /// In cs, this message translates to:
  /// **'Obnova selhala: {error}'**
  String restoreErrorFailed(String error);

  /// Titulek AppBaru obrazovky obnovy účtu (stejný text jako tlačítko na ř. 193 — sdílet jeden klíč) | Text hlavního tlačítka obnovy (identický s AppBar titulkem na ř. 87 — jeden klíč)
  ///
  /// In cs, this message translates to:
  /// **'Obnovit účet'**
  String get restoreTitle;

  /// Hlavní nadpis obrazovky obnovy účtu
  ///
  /// In cs, this message translates to:
  /// **'Zadej svoji zálohovací frázi'**
  String get restoreHeading;

  /// Podnadpis pod nadpisem obrazovky obnovy. Adjacentní literály přes 3 řádky (104-106). Pozor na mužský rod 'sis uložil' — přeformulovat neutrálně.
  ///
  /// In cs, this message translates to:
  /// **'{wordCount} slov, ze zálohy vytvořené při zakládání účtu. Obnoví tvoji identitu (stejný SEP kód, kontakty tě dál poznají).'**
  String restoreIntro(int wordCount);

  /// Žlutý varovný box na obrazovce obnovy účtu. Adjacentní literály přes 2 řádky (130-131).
  ///
  /// In cs, this message translates to:
  /// **'Historie zpráv se neobnoví — je uložená jen na původním zařízení.'**
  String get restoreHistoryWarning;

  /// hintText pole zálohovací fráze — ukázkový formát zadání
  ///
  /// In cs, this message translates to:
  /// **'slovo1 slovo2 slovo3 …'**
  String get restorePhraseHint;

  /// helperText pod polem fráze — průběžné počítadlo zadaných slov (mění barvu při dosažení 24)
  ///
  /// In cs, this message translates to:
  /// **'{wordCount} / {requiredWords} slov'**
  String restoreWordCountHelper(int wordCount, int requiredWords);

  /// První řádek seznamu konverzací — odkaz na archiv s počtem archivovaných konverzací
  ///
  /// In cs, this message translates to:
  /// **'Archivované ({count})'**
  String chatListArchivedCount(int count);

  /// Nadpis empty state, když uživatel nemá žádné konverzace
  ///
  /// In cs, this message translates to:
  /// **'Zatím žádné konverzace'**
  String get chatListEmptyTitle;

  /// Podnadpis empty state — 'šeptat' je slovní hříčka s názvem appky, v překladu volit ekvivalent (whisper/flüstern…)
  ///
  /// In cs, this message translates to:
  /// **'Přidej kontakt a začni šeptat!'**
  String get chatListEmptySubtitle;

  /// Položka bottom sheetu akcí konverzace (long-press), zobrazí se když je konverzace ztlumená. Ternár na jednom řádku se 'Ztlumit'.
  ///
  /// In cs, this message translates to:
  /// **'Zrušit ztlumení'**
  String get chatListUnmute;

  /// Položka bottom sheetu akcí konverzace (long-press), zobrazí se když konverzace ztlumená není
  ///
  /// In cs, this message translates to:
  /// **'Ztlumit'**
  String get chatListMute;

  /// Položka bottom sheetu akcí konverzace (long-press) — přesune konverzaci do archivu; kandidát na sdílení s archive feature (archiveAction)
  ///
  /// In cs, this message translates to:
  /// **'Archivovat'**
  String get chatListArchive;

  /// AppBar titulek obrazovky sdílení vlastního QR/Šepot ID
  ///
  /// In cs, this message translates to:
  /// **'Můj Šepot ID'**
  String get qrShareTitle;

  /// Titulek na QR obrazovce, když vlastní registrace na relay ještě nedoběhla — routing (aid+da) není hotový, QR by byl neúplný.
  ///
  /// In cs, this message translates to:
  /// **'Připojuji k relayi…'**
  String get qrShareConnectingTitle;

  /// Vysvětlení pod titulkem qrShareConnectingTitle. 'Šepot' je značka, nepřekládat.
  ///
  /// In cs, this message translates to:
  /// **'Až se Šepot poprvé připojí, objeví se tvůj QR kód a odkaz. Chvilku strpení — stačí pár sekund.'**
  String get qrShareConnectingBody;

  /// Text uprostřed obrazovky, když identityProvider vrátí null (nemělo by běžně nastat)
  ///
  /// In cs, this message translates to:
  /// **'Identita nebyla nalezena'**
  String get qrIdentityNotFound;

  /// SnackBar po stisku tlačítka Kopírovat (zkopírování share stringu) — pravděpodobně sdílené i jinde v appce
  ///
  /// In cs, this message translates to:
  /// **'Zkopírováno do schránky'**
  String get commonCopiedToClipboard;

  /// Text sdílený přes share_plus (Share.share) — pozvánka s identitním řetězcem; obsahuje dva \n
  ///
  /// In cs, this message translates to:
  /// **'Přidej mě na Šepotu!\n\n{shareString}'**
  String qrShareInviteMessage(String shareString);

  /// Popisek ElevatedButton.icon, který otevře systémový share sheet
  ///
  /// In cs, this message translates to:
  /// **'Sdílet'**
  String get commonShare;

  /// Informační box (ikona info) pod tlačítky — vysvětluje, jak protistrana kontakt přidá
  ///
  /// In cs, this message translates to:
  /// **'Kontakt naskenuje tvůj QR kód nebo vloží sdílený řetězec do aplikace.'**
  String get qrShareInfo;

  /// Label kategorie nahlášení — zobrazuje report screen ve výběru kategorií (ReportCategory.label)
  ///
  /// In cs, this message translates to:
  /// **'Ohrožení dítěte'**
  String get reportCategoryChildSafety;

  /// Hint kategorie Ohrožení dítěte — zobrazuje report screen; právně citlivý text (CSAM — odrazuje od vkládání obsahu, viz komentář § 192), překlad musí zachovat význam
  ///
  /// In cs, this message translates to:
  /// **'Popiš situaci vlastními slovy. Nevkládej obsah zpráv ani odkazy na materiál.'**
  String get reportCategoryChildSafetyHint;

  /// Label kategorie nahlášení — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Obtěžování nebo výhrůžky'**
  String get reportCategoryHarassment;

  /// Hint kategorie Obtěžování — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Někdo tě zastrašuje, vyhrožuje nebo obtěžuje.'**
  String get reportCategoryHarassmentHint;

  /// Label kategorie nahlášení — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Spam'**
  String get reportCategorySpam;

  /// Hint kategorie Spam — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Nevyžádané zprávy, hromadné rozesílání.'**
  String get reportCategorySpamHint;

  /// Label kategorie nahlášení — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Podvod'**
  String get reportCategoryFraud;

  /// Hint kategorie Podvod — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Pokus vylákat peníze, klíče nebo osobní údaje.'**
  String get reportCategoryFraudHint;

  /// Label kategorie nahlášení — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Jiné'**
  String get reportCategoryOther;

  /// Hint kategorie Jiné — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Něco jiného, co bychom měli vědět.'**
  String get reportCategoryOtherHint;

  /// ReportFailure při prázdném popisu — UI (report screen) zobrazuje message jako chybu/SnackBar
  ///
  /// In cs, this message translates to:
  /// **'Napiš prosím, co se stalo.'**
  String get reportErrorEmptyDescription;

  /// ReportFailure při síťové chybě/timeoutu odesílání hlášení — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Nepodařilo se spojit se serverem. Zkus to znovu, nebo napiš na {supportEmail}.'**
  String reportErrorConnection(String supportEmail);

  /// ReportFailure při HTTP 429 (rate limit) — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Z tvé sítě přišlo příliš mnoho hlášení. Zkus to za hodinu, nebo napiš na {supportEmail}.'**
  String reportErrorRateLimited(String supportEmail);

  /// ReportFailure při jiném HTTP kódu — zobrazuje report screen
  ///
  /// In cs, this message translates to:
  /// **'Odeslání selhalo (kód {statusCode}). Napiš prosím na {supportEmail}.'**
  String reportErrorServer(int statusCode, String supportEmail);

  /// Volba automatického zámku (0 s) v nastavení — popisek v nabídce AutoLockNotifier.moznosti, zobrazuje settings UI
  ///
  /// In cs, this message translates to:
  /// **'Nikdy'**
  String get settingsAutoLockNever;

  /// Volba automatického zámku (60 s) v nastavení; v EN/DE/RU/IT zvážit jednotný vzor 'After X minutes' — česky je tvar minutě/minutách nepravidelný, proto samostatné klíče místo ICU pluralu s pevnými hodnotami
  ///
  /// In cs, this message translates to:
  /// **'Po 1 minutě'**
  String get settingsAutoLock1min;

  /// Volba automatického zámku (900 s) v nastavení
  ///
  /// In cs, this message translates to:
  /// **'Po 15 minutách'**
  String get settingsAutoLock15min;

  /// SnackBar když selže zapnutí/vypnutí Toru (výjimka z torProvider.set); $e je výjimka
  ///
  /// In cs, this message translates to:
  /// **'Přepnutí Toru selhalo: {error}'**
  String torToggleFailed(String error);

  /// Titulek potvrzovacího AlertDialogu před zapnutím Toru; STEJNÝ text i jako title ListTile na ř. 101 — sdílet jeden klíč
  ///
  /// In cs, this message translates to:
  /// **'Připojení přes Tor'**
  String get torConnectionTitle;

  /// Obsah potvrzovacího dialogu před zapnutím Toru — vysvětluje závislost na Orbotu. POZOR: ve zdrojáku 4 adjacentní literály (ř. 47–51) slepené kompilátorem, mezi 'portu 9050.' a 'Bez běžícího' je \n\n; přeložit jako jeden celek. 'Orbot', 'Tor', 'SOCKS' a port 9050 jsou vlastní jména/konstanty — nepřekládat
  ///
  /// In cs, this message translates to:
  /// **'Provoz na server půjde přes síť Tor (skryje tvou IP adresu). Vyžaduje nainstalovanou a spuštěnou aplikaci Orbot s aktivním SOCKS proxy na portu 9050.\n\nBez běžícího Orbotu se zprávy neodešlou ani nepřijmou. Spojení bývá pomalejší.'**
  String get torDialogBody;

  /// Potvrzovací tlačítko dialogu (zapne Tor) — obecné 'Zapnout', kandidát na sdílený klíč pro jiné přepínače
  ///
  /// In cs, this message translates to:
  /// **'Zapnout'**
  String get commonTurnOn;

  /// Subtitle dlaždice v nastavení když je Tor VYPNUTÝ
  ///
  /// In cs, this message translates to:
  /// **'Přímé šifrované spojení (WSS). Zapni pro skrytí IP přes Tor.'**
  String get torSubtitleOff;

  /// Subtitle dlaždice když je Tor zapnutý a relay spojení navázané (RelayConnectionState.connected)
  ///
  /// In cs, this message translates to:
  /// **'Připojeno přes Tor (.onion).'**
  String get torStatusConnected;

  /// Subtitle dlaždice když je Tor zapnutý a spojení se navazuje — nápověda, že možná neběží Orbot; obsahuje výpustku …
  ///
  /// In cs, this message translates to:
  /// **'Připojuji přes Tor… (běží Orbot?)'**
  String get torStatusConnecting;

  /// Subtitle dlaždice když je Tor zapnutý a spojení není navázané ani se nenavazuje (default větev switch) — čeká se na Orbot
  ///
  /// In cs, this message translates to:
  /// **'Přes Tor — čekám na Orbot (SOCKS 9050).'**
  String get torStatusWaiting;

  /// SnackBar v nastavení při pokusu zapnout biometrii bez nastaveného PINu
  ///
  /// In cs, this message translates to:
  /// **'Nejdřív nastav PIN — biometrie ho jen doplňuje.'**
  String get biometricsPinRequiredFirst;

  /// SnackBar v nastavení při pokusu zapnout biometrii se zamčeným úložištěm; NENÍ to devInternal StateError, je to věta pro uživatele
  ///
  /// In cs, this message translates to:
  /// **'Úložiště je zamčené — odemkni appku PINem.'**
  String get biometricsStorageLocked;

  /// SnackBar když LocalAuthentication.isDeviceSupported() vrátí false
  ///
  /// In cs, this message translates to:
  /// **'Zařízení nemá nastavenou biometrii.'**
  String get biometricsNotAvailable;

  /// localizedReason systémové biometrické výzvy (local_auth) při zapínání biometrie — zobrazí OS v nativním dialogu
  ///
  /// In cs, this message translates to:
  /// **'Potvrď zapnutí biometrického odemčení'**
  String get biometricsEnrollPromptReason;

  /// SnackBar v catch bloku při selhání zapnutí/vypnutí biometrie; $e je zachycená výjimka
  ///
  /// In cs, this message translates to:
  /// **'Biometrii se nepodařilo nastavit: {error}'**
  String biometricsSetupFailed(String error);

  /// Titulek ListTile přepínače biometrie v nastavení
  ///
  /// In cs, this message translates to:
  /// **'Biometrie'**
  String get biometricsTileTitle;

  /// Podtitulek ListTile přepínače biometrie v nastavení
  ///
  /// In cs, this message translates to:
  /// **'Odemknutí otiskem prstu / obličejem (PIN zůstává záloha)'**
  String get biometricsTileSubtitle;

  /// FormatException z BackupService.import() při příliš krátkém souboru — zobrazí obrazovka obnovy zálohy (SnackBar/dialog)
  ///
  /// In cs, this message translates to:
  /// **'Poškozený soubor zálohy'**
  String get backupErrorCorruptedFile;

  /// FormatException z BackupService.import() při chybějícím magic headeru SEPOTBK1 — zobrazí obrazovka obnovy zálohy
  ///
  /// In cs, this message translates to:
  /// **'Nerozpoznaný formát zálohy'**
  String get backupErrorUnknownFormat;

  /// FormatException z BackupService.import() při selhání GCM autentizace (klíč odvozený z jiné identity) — zobrazí obrazovka obnovy zálohy
  ///
  /// In cs, this message translates to:
  /// **'Zálohu nelze dešifrovat — patří k jiné identitě?'**
  String get backupErrorWrongIdentity;

  /// Název souboru předaný do XFile.fromData při sdílení obrázku přes systémový share sheet — uživatel jej vidí v cíli sdílení; držet bez diakritiky a mezer (je to filename)
  ///
  /// In cs, this message translates to:
  /// **'sepot-obrazek.{ext}'**
  String attachmentSharedImageFilename(String ext);

  /// Chybový text uprostřed fullscreen prohlížeče obrázku, když se přílohu nepodaří načíst/dešifrovat
  ///
  /// In cs, this message translates to:
  /// **'Přílohu se nepodařilo dešifrovat'**
  String get attachmentDecryptFailed;

  /// Výchozí název akce lokální notifikace na Linuxu (LinuxInitializationSettings.defaultActionName)
  ///
  /// In cs, this message translates to:
  /// **'Otevřít'**
  String get pushActionOpen;

  /// Název Android notifikačního kanálu — uživatel ho vidí v systémovém nastavení notifikací. Duplicitně na řádcích 50 a 73 (showMessageNotification i showWakeNotification) — sloučit do jednoho klíče. Pozor: channel name se překládá podle jazyka při PRVNÍM vytvoření kanálu. | Druhý výskyt názvu kanálu (showWakeNotification) — stejný klíč jako řádek 50.
  ///
  /// In cs, this message translates to:
  /// **'Zprávy'**
  String get pushChannelMessagesName;

  /// Popis Android notifikačního kanálu v systémovém nastavení. Duplicitně na řádcích 51 a 74 — sloučit do jednoho klíče. | Druhý výskyt popisu kanálu (showWakeNotification) — stejný klíč jako řádek 51.
  ///
  /// In cs, this message translates to:
  /// **'Upozornění na nové zprávy (bez obsahu)'**
  String get pushChannelMessagesDescription;

  /// Tělo notifikace o přijaté zprávě, když appka běží na pozadí — zobrazuje jen jméno odesílatele, nikdy obsah zprávy.
  ///
  /// In cs, this message translates to:
  /// **'Nová zpráva od {senderName}'**
  String pushNewMessageFrom(String senderName);

  /// Tělo generické wake notifikace po push budíčku v killed-state — DB je zamčená, obsah nelze dešifrovat, proto záměrně bez detailů. Neformální tykání ('Máš') — držet tón i v překladech.
  ///
  /// In cs, this message translates to:
  /// **'Máš nové zprávy'**
  String get pushNewMessages;

  /// Titulek AppBaru obrazovky archivovaných konverzací.
  ///
  /// In cs, this message translates to:
  /// **'Archivované'**
  String get archiveTitle;

  /// Empty state uprostřed obrazovky, když nejsou žádné archivované konverzace.
  ///
  /// In cs, this message translates to:
  /// **'Žádné archivované konverzace'**
  String get archiveEmpty;

  /// Položka v modal bottom sheetu po long-pressu na archivovanou konverzaci — odarchivuje ji.
  ///
  /// In cs, this message translates to:
  /// **'Zrušit archivaci'**
  String get archiveUnarchive;

  /// FormatException z SepotMnemonic.decode() při špatném počtu slov — zobrazuje obnovovací obrazovka (restore flow) jako chybovou hlášku při zadání mnemonic fráze.
  ///
  /// In cs, this message translates to:
  /// **'Fráze má {count} slov, očekávám {expected}'**
  String restoreErrorMnemonicWordCount(int count, int expected);

  /// FormatException z SepotMnemonic.decode() při neznámém slovu / špatném checksumu (ArgumentError větev z bip39) — zobrazuje restore UI. POZOR: ${e.message} je interní anglická hláška knihovny bip39 — zvážit, zda ji vůbec zobrazovat, nebo nahradit generickou lokalizovanou hláškou. | Identický text jako řádek 53, jen StateError větev (bip39 hlásí chyby dvěma typy výjimek). Stejný ARB klíč restoreErrorInvalidMnemonic — sloučit.
  ///
  /// In cs, this message translates to:
  /// **'Neplatná fráze: {message}'**
  String restoreErrorInvalidMnemonic(String message);

  /// Exception z ContactsNotifier.addContact() při pokusu přidat duplicitní kontakt (stejná identita) — zachytává a zobrazuje UI přidávání kontaktu (typicky SnackBar po skenu QR / zadání Šepot ID).
  ///
  /// In cs, this message translates to:
  /// **'Kontakt již existuje'**
  String get contactsErrorAlreadyExists;

  /// Tagline pod názvem aplikace v logu (splash/onboarding obrazovky, showText=true).
  ///
  /// In cs, this message translates to:
  /// **'Soukromý messenger'**
  String get commonAppTagline;

  /// Kompaktní varianta badge šifrování (ikona zámku + 'E2E'). Zkratka end-to-end — ve většině jazyků zůstane 'E2E'.
  ///
  /// In cs, this message translates to:
  /// **'E2E'**
  String get commonE2eBadgeCompact;

  /// Plná varianta badge šifrování (ikona zámku + text), zobrazuje se např. v hlavičce chatu / onboardingu.
  ///
  /// In cs, this message translates to:
  /// **'End-to-end šifrováno'**
  String get commonE2eBadgeFull;

  /// hintText pole popisku na obrazovce náhledu fotky před odesláním
  ///
  /// In cs, this message translates to:
  /// **'Přidat popisek…'**
  String get photoPreviewCaptionHint;

  /// Tooltip nástroje kreslení prstem na náhledu fotky
  ///
  /// In cs, this message translates to:
  /// **'Kreslit'**
  String get photoPreviewDraw;

  /// Tooltip nástroje přidání textu na fotku
  ///
  /// In cs, this message translates to:
  /// **'Přidat text'**
  String get photoPreviewAddText;

  /// Tooltip otočení fotky o 90°
  ///
  /// In cs, this message translates to:
  /// **'Otočit'**
  String get photoPreviewRotate;

  /// Tooltip vrácení posledního tahu kreslení
  ///
  /// In cs, this message translates to:
  /// **'Zpět'**
  String get photoPreviewUndo;

  /// Tooltip tlačítka odeslání fotky z náhledu
  ///
  /// In cs, this message translates to:
  /// **'Poslat'**
  String get photoPreviewSend;

  /// Titulek dialogu pro zadání/úpravu textu na fotce
  ///
  /// In cs, this message translates to:
  /// **'Text na fotce'**
  String get photoPreviewTextDialogTitle;

  /// Tlačítko odebrání textu z fotky v dialogu úpravy
  ///
  /// In cs, this message translates to:
  /// **'Odebrat'**
  String get photoPreviewRemoveText;

  /// SnackBar, když se vybraná fotka nedá dekódovat — náhled se zavře bez odeslání
  ///
  /// In cs, this message translates to:
  /// **'Fotku se nepodařilo načíst'**
  String get photoPreviewDecodeFailed;

  /// Položka v nabídce zprávy — detail doručení a přečtení.
  ///
  /// In cs, this message translates to:
  /// **'Info o zprávě'**
  String get chatActionInfo;

  /// Info o zprávě: řádek času odeslání.
  ///
  /// In cs, this message translates to:
  /// **'Odesláno'**
  String get messageInfoSent;

  /// Info o zprávě: řádek času doručení.
  ///
  /// In cs, this message translates to:
  /// **'Doručeno'**
  String get messageInfoDelivered;

  /// Info o zprávě: řádek času přečtení.
  ///
  /// In cs, this message translates to:
  /// **'Přečteno'**
  String get messageInfoRead;

  /// Info o zprávě: událost ještě nenastala.
  ///
  /// In cs, this message translates to:
  /// **'zatím ne'**
  String get messageInfoPending;

  /// Info o zprávě: vysvětlení, proč chybí čas přečtení.
  ///
  /// In cs, this message translates to:
  /// **'Kdy si zprávu přečetli, uvidíš, jen když sám sdílíš potvrzení přečtení (Nastavení).'**
  String get messageInfoReadReceiptsOff;

  /// Řádek pod poslední odeslanou zprávou — čas přečtení.
  ///
  /// In cs, this message translates to:
  /// **'Přečteno {time}'**
  String chatStatusReadAt(String time);

  /// Řádek pod poslední odeslanou zprávou — čas doručení.
  ///
  /// In cs, this message translates to:
  /// **'Doručeno {time}'**
  String chatStatusDeliveredAt(String time);

  /// Nabídka skupiny a titulek obrazovky pro přidání lidí.
  ///
  /// In cs, this message translates to:
  /// **'Přidat členy'**
  String get groupsAddMembers;

  /// Potvrzovací tlačítko v AppBaru při přidávání členů.
  ///
  /// In cs, this message translates to:
  /// **'Přidat'**
  String get groupsAddMembersAction;

  /// Chyba při přidávání členů.
  ///
  /// In cs, this message translates to:
  /// **'Přidání se nepovedlo: {error}'**
  String groupsAddMembersFailed(String error);

  /// Prázdný výběr — všechny kontakty už ve skupině jsou.
  ///
  /// In cs, this message translates to:
  /// **'Všechny tvoje kontakty už ve skupině jsou. Nového člověka nejdřív přidej do kontaktů přes QR kód.'**
  String get groupsNoContactsToAdd;

  /// Karta spodní navigace a nadpis seznamu chatů.
  ///
  /// In cs, this message translates to:
  /// **'Chaty'**
  String get navChats;

  /// Tlačítko pro zahájení nového chatu.
  ///
  /// In cs, this message translates to:
  /// **'Nový chat'**
  String get chatListNewChat;

  /// Placeholder hledání v seznamu chatů.
  ///
  /// In cs, this message translates to:
  /// **'Hledat v chatech a zprávách'**
  String get chatListSearchHint;

  /// Filtr seznamu chatů — vše.
  ///
  /// In cs, this message translates to:
  /// **'Vše'**
  String get chatFilterAll;

  /// Filtr seznamu chatů — nepřečtené.
  ///
  /// In cs, this message translates to:
  /// **'Nepřečtené'**
  String get chatFilterUnread;

  /// Filtr seznamu chatů — skupiny.
  ///
  /// In cs, this message translates to:
  /// **'Skupiny'**
  String get chatFilterGroups;

  /// Odkaz na archiv v řádku filtrů.
  ///
  /// In cs, this message translates to:
  /// **'Archiv'**
  String get chatFilterArchive;

  /// Hledání v chatech nic nenašlo.
  ///
  /// In cs, this message translates to:
  /// **'Nic nenalezeno.'**
  String get chatListNoResults;

  /// Vybraný filtr je prázdný.
  ///
  /// In cs, this message translates to:
  /// **'Tady zatím nic není.'**
  String get chatListFilterEmpty;

  /// Akce: připnout chat nahoru.
  ///
  /// In cs, this message translates to:
  /// **'Připnout'**
  String get chatListPin;

  /// Akce: odepnout chat.
  ///
  /// In cs, this message translates to:
  /// **'Odepnout'**
  String get chatListUnpin;

  /// Hlavička chatu / menu: otevřít profil kontaktu.
  ///
  /// In cs, this message translates to:
  /// **'Zobrazit profil'**
  String get chatOpenProfile;

  /// Menu skupinového chatu: profil skupiny.
  ///
  /// In cs, this message translates to:
  /// **'Profil skupiny'**
  String get groupsProfile;

  /// Hledání v jedné konverzaci — placeholder a popisek tlačítka.
  ///
  /// In cs, this message translates to:
  /// **'Hledat v konverzaci'**
  String get chatSearchHint;

  /// Hledání v konverzaci bez výsledku (krátce, vedle pole).
  ///
  /// In cs, this message translates to:
  /// **'Nic'**
  String get chatSearchNoMatches;

  /// Pořadí aktuální shody hledání, např. „2 z 5“.
  ///
  /// In cs, this message translates to:
  /// **'{current} z {total}'**
  String chatSearchCounter(int current, int total);

  /// Tlačítko: předchozí (starší) shoda.
  ///
  /// In cs, this message translates to:
  /// **'Starší shoda'**
  String get chatSearchOlder;

  /// Tlačítko: další (novější) shoda.
  ///
  /// In cs, this message translates to:
  /// **'Novější shoda'**
  String get chatSearchNewer;

  /// Oddělovač nad první nepřečtenou zprávou.
  ///
  /// In cs, this message translates to:
  /// **'{count, plural, one{1 nová zpráva} few{{count} nové zprávy} other{{count} nových zpráv}}'**
  String chatUnreadDivider(int count);

  /// Tlačítko: skok na nejnovější zprávy.
  ///
  /// In cs, this message translates to:
  /// **'Na nejnovější zprávy'**
  String get chatJumpToLatest;

  /// Tlačítko přílohy v poli pro psaní.
  ///
  /// In cs, this message translates to:
  /// **'Přiložit'**
  String get chatAttach;

  /// Tlačítko odeslat.
  ///
  /// In cs, this message translates to:
  /// **'Odeslat'**
  String get chatSend;

  /// Tlačítko nahrát hlasovou zprávu.
  ///
  /// In cs, this message translates to:
  /// **'Nahrát hlasovou zprávu'**
  String get chatRecordVoice;

  /// Karta sdílených fotek v profilu.
  ///
  /// In cs, this message translates to:
  /// **'Sdílená média'**
  String get profileSharedMedia;

  /// Akce profilu: napsat zprávu.
  ///
  /// In cs, this message translates to:
  /// **'Zpráva'**
  String get profileMessage;

  /// Akce profilu: hledat v konverzaci.
  ///
  /// In cs, this message translates to:
  /// **'Hledat'**
  String get profileSearch;

  /// Akce profilu: zrušit ztlumení (krátce).
  ///
  /// In cs, this message translates to:
  /// **'Zvuk'**
  String get profileUnmute;

  /// Akce profilu: mizící zprávy (krátce).
  ///
  /// In cs, this message translates to:
  /// **'Mizení'**
  String get profileDisappearing;

  /// Karta společných skupin v profilu kontaktu.
  ///
  /// In cs, this message translates to:
  /// **'Společné skupiny'**
  String get profileCommonGroups;

  /// Řádek profilu: bezpečnostní číslo.
  ///
  /// In cs, this message translates to:
  /// **'Bezpečnostní číslo'**
  String get profileSafetyNumber;

  /// Podtitulek bezpečnostního čísla u neověřeného kontaktu.
  ///
  /// In cs, this message translates to:
  /// **'Porovnejte osobně nebo QR kódem'**
  String get profileSafetyNumberHint;

  /// Stav ověřeného kontaktu v hlavičce profilu.
  ///
  /// In cs, this message translates to:
  /// **'Ověřeno osobně'**
  String get profileVerifiedInPerson;

  /// Tlačítko v profilu neověřeného kontaktu.
  ///
  /// In cs, this message translates to:
  /// **'Ověřit kontakt'**
  String get profileVerifyNow;

  /// Akce profilu skupiny: přidat členy (krátce).
  ///
  /// In cs, this message translates to:
  /// **'Přidat'**
  String get profileAdd;

  /// Podtitulek profilu skupiny: počet členů · datum založení.
  ///
  /// In cs, this message translates to:
  /// **'Skupina · {members} · založena {date}'**
  String profileGroupSubtitle(String members, String date);

  /// Počet členů ze stropu skupiny, např. „4 ze 128“.
  ///
  /// In cs, this message translates to:
  /// **'{count} ze {max}'**
  String profileMembersOfMax(int count, int max);

  /// Podtitulek chatu / náhled v seznamu: protistrana píše.
  ///
  /// In cs, this message translates to:
  /// **'píše…'**
  String get chatTyping;

  /// Skupina: kdo píše (křestní jméno).
  ///
  /// In cs, this message translates to:
  /// **'{name} píše…'**
  String chatTypingNamed(String name);

  /// Skupina: píše víc lidí najednou.
  ///
  /// In cs, this message translates to:
  /// **'Několik lidí píše…'**
  String get chatTypingSeveral;

  /// Nastavení: přepínač „píše…“.
  ///
  /// In cs, this message translates to:
  /// **'Ukazovat, že píšu'**
  String get settingsTypingTitle;

  /// Popis přepínače „píše…“.
  ///
  /// In cs, this message translates to:
  /// **'Oboustranné — kdo nesdílí, nevidí (výchozí vypnuto)'**
  String get settingsTypingSubtitle;

  /// Položka nabídky příloh: vytvořit anketu.
  ///
  /// In cs, this message translates to:
  /// **'Anketa'**
  String get pollAttach;

  /// Nadpis formuláře nové ankety.
  ///
  /// In cs, this message translates to:
  /// **'Nová anketa'**
  String get pollCreateTitle;

  /// Pole otázky ankety.
  ///
  /// In cs, this message translates to:
  /// **'Otázka'**
  String get pollQuestion;

  /// Placeholder možnosti ankety s pořadím.
  ///
  /// In cs, this message translates to:
  /// **'Možnost {number}'**
  String pollOptionHint(int number);

  /// Tlačítko: přidat možnost do ankety.
  ///
  /// In cs, this message translates to:
  /// **'Přidat možnost'**
  String get pollAddOption;

  /// Tlačítko: odebrat možnost.
  ///
  /// In cs, this message translates to:
  /// **'Odebrat možnost'**
  String get pollRemoveOption;

  /// Přepínač: víc odpovědí na osobu.
  ///
  /// In cs, this message translates to:
  /// **'Povolit víc odpovědí'**
  String get pollAllowMultiple;

  /// Hlavička ankety s jednou volbou.
  ///
  /// In cs, this message translates to:
  /// **'Anketa'**
  String get pollSingle;

  /// Hlavička ankety s více volbami.
  ///
  /// In cs, this message translates to:
  /// **'Anketa, více voleb'**
  String get pollMulti;

  /// Počet hlasujících v anketě.
  ///
  /// In cs, this message translates to:
  /// **'{count, plural, =0{zatím bez hlasů} one{1 hlas} few{{count} hlasy} other{{count} hlasů}}'**
  String pollVoters(int count);

  /// Záložní text ankety pro starší verze appky — první řádek.
  ///
  /// In cs, this message translates to:
  /// **'Anketa: {question}'**
  String pollFallback(String question);

  /// Záložní text ankety — výzva k aktualizaci.
  ///
  /// In cs, this message translates to:
  /// **'Hlasovat jde v aktuální verzi Šepotu.'**
  String get pollFallbackUpdate;

  /// Popisek avataru v Nastavení (čtečka obrazovky).
  ///
  /// In cs, this message translates to:
  /// **'Změnit profilovou fotku'**
  String get profilePhotoEdit;

  /// Akce: vybrat profilovou fotku z galerie.
  ///
  /// In cs, this message translates to:
  /// **'Vybrat fotku'**
  String get profilePhotoPick;

  /// Akce: odebrat profilovou fotku.
  ///
  /// In cs, this message translates to:
  /// **'Odebrat fotku'**
  String get profilePhotoRemove;

  /// Vysvětlení, kdo profilovou fotku uvidí.
  ///
  /// In cs, this message translates to:
  /// **'Fotku uvidí jen lidé, se kterými si píšeš — šifrovaně, stejně jako zprávy. Poloha ani údaje o fotce se neposílají.'**
  String get profilePhotoHint;

  /// Chyba nastavení profilové fotky.
  ///
  /// In cs, this message translates to:
  /// **'Fotku se nepodařilo nastavit: {error}'**
  String profilePhotoFailed(String error);

  /// Nadpis výzvy k PINu před citlivou akcí v odemčené appce
  ///
  /// In cs, this message translates to:
  /// **'Potvrď, že jsi to ty'**
  String get reauthTitle;

  /// Snackbar: citlivá akce bez nastaveného PINu
  ///
  /// In cs, this message translates to:
  /// **'Tahle akce potřebuje PIN. Nejdřív si ho nastav.'**
  String get reauthPinRequired;

  /// Akce snackbaru: nastavit PIN
  ///
  /// In cs, this message translates to:
  /// **'Nastavit PIN'**
  String get reauthSetPin;

  /// Důvod ve výzvě k PINu/biometrii: zobrazení obnovovací fráze
  ///
  /// In cs, this message translates to:
  /// **'Zobrazení 24 slov pro obnovu účtu'**
  String get reauthReasonSeed;

  /// Důvod: export zálohy
  ///
  /// In cs, this message translates to:
  /// **'Export zálohy'**
  String get reauthReasonBackupExport;

  /// Důvod: obnova ze zálohy
  ///
  /// In cs, this message translates to:
  /// **'Obnova ze zálohy'**
  String get reauthReasonBackupImport;

  /// Důvod: nastavení nebo zrušení nátlakového PINu
  ///
  /// In cs, this message translates to:
  /// **'Změna nátlakového PINu'**
  String get reauthReasonDecoyPin;

  /// Důvod: prodloužení nebo vypnutí automatického zámku
  ///
  /// In cs, this message translates to:
  /// **'Prodloužení automatického zámku'**
  String get reauthReasonAutoLock;

  /// Důvod: vypnutí ochrany obrazovky
  ///
  /// In cs, this message translates to:
  /// **'Vypnutí ochrany obrazovky'**
  String get reauthReasonScreenSecurity;

  /// Důvod: smazání účtu
  ///
  /// In cs, this message translates to:
  /// **'Smazání účtu a všech dat'**
  String get reauthReasonDeleteAccount;

  /// Důvod: zapnutí biometrického odemčení
  ///
  /// In cs, this message translates to:
  /// **'Zapnutí biometrie'**
  String get reauthReasonBiometrics;

  /// Jméno neznámého odesílatele (žádost o zprávu) všude v UI; {name} si zvolil sám
  ///
  /// In cs, this message translates to:
  /// **'{name} (neznámý)'**
  String contactRequestName(String name);

  /// Text notifikace pro zprávu od neznámého odesílatele — bez jména, které si zvolil
  ///
  /// In cs, this message translates to:
  /// **'Žádost o zprávu od neznámého odesílatele'**
  String get pushMessageRequest;

  /// Nadpis panelu / štítek žádosti o zprávu
  ///
  /// In cs, this message translates to:
  /// **'Žádost o zprávu'**
  String get requestTitle;

  /// Panel žádosti o zprávu; {name} = jméno, které si odesílatel zvolil
  ///
  /// In cs, this message translates to:
  /// **'„{name}“ není ve tvých kontaktech. Jméno i fotku si zvolil sám, takže nemusí jít o toho, za koho se vydává. Dokud ho nepřijmeš, neuvidí, že jsi zprávu četl, a nemůže ti volat.'**
  String requestBody(String name);

  /// Varování v panelu žádosti: jméno se plete s existujícím kontaktem {name}
  ///
  /// In cs, this message translates to:
  /// **'Pozor: stejně se jmenuje tvůj kontakt {name}. Tohle je jiný klíč, tedy jiný telefon nebo jiný člověk. Než odpovíš, ověř si to jinou cestou (zavolej, potkejte se).'**
  String requestLookalikeWarning(String name);

  /// Tlačítko: přijmout žádost o zprávu
  ///
  /// In cs, this message translates to:
  /// **'Přijmout'**
  String get requestAccept;

  /// Nadpis dialogu přijetí žádosti
  ///
  /// In cs, this message translates to:
  /// **'Přijmout jako kontakt'**
  String get requestAcceptTitle;

  /// Text dialogu přijetí: kontakt pojmenuje uživatel sám
  ///
  /// In cs, this message translates to:
  /// **'Pojmenuj kontakt sám. Jméno, které si odesílatel zvolil, se nepřebírá automaticky.'**
  String get requestAcceptBody;

  /// Popisek pole se jménem kontaktu
  ///
  /// In cs, this message translates to:
  /// **'Jméno kontaktu'**
  String get requestAcceptNameLabel;

  /// Chyba: prázdné jméno
  ///
  /// In cs, this message translates to:
  /// **'Zadej jméno.'**
  String get requestNameEmpty;

  /// Chyba: jméno se plete s jiným kontaktem
  ///
  /// In cs, this message translates to:
  /// **'Tak (nebo skoro tak) se už jmenuje jiný kontakt. Zvol jméno, které je nezamění.'**
  String get requestNameTaken;

  /// Upozornění v konverzaci: kontaktu {name} se změnil identity klíč
  ///
  /// In cs, this message translates to:
  /// **'Bezpečnostní kód kontaktu {name} se změnil. Pod jeho adresou se ozval jiný klíč: nový telefon, přeinstalace, nebo podvrh. Ověření je zrušené. Než pošleš něco citlivého, porovnejte kód znovu.'**
  String noticeIdentityChanged(String name);

  /// Upozornění v konverzaci existujícího kontaktu {name}: neznámý si zvolil podobné jméno {claimed}
  ///
  /// In cs, this message translates to:
  /// **'Neznámý odesílatel si dal jméno „{claimed}“, které se plete s kontaktem {name}. Tento kontakt to není, zpráva přišla z jiného klíče. Najdeš ji v chatech jako žádost o zprávu.'**
  String noticeLookalikeRequest(String claimed, String name);

  /// Tlačítko u upozornění na změnu kódu
  ///
  /// In cs, this message translates to:
  /// **'Ověřit kód'**
  String get noticeVerifyAction;

  /// Náhled v seznamu chatů, když je poslední položkou bezpečnostní upozornění
  ///
  /// In cs, this message translates to:
  /// **'Bezpečnostní upozornění'**
  String get noticePreview;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['cs', 'de', 'en', 'it', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'cs':
      return AppLocalizationsCs();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
