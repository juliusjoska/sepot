# Changelog

Všechny podstatné změny v aplikaci Šepot. Formát dle
[Keep a Changelog](https://keepachangelog.com/cs/1.1.0/),
verzování dle [ajtak standardu](#verzování).

## [Nevydáno]

## [1.2.2] – 2026-10-11

### Opraveno
- **Přečtený chat se dál ukazoval jako nepřečtený.** Zpráva, která přišla do
  otevřeného chatu, zůstala po návratu do seznamu tučně s odznakem; teď se
  přečte hned, když je chat na obrazovce (a appka v popředí). Stažení přílohy
  nebo dodatečné doručení už nevrátí přečtenou zprávu mezi nepřečtené.
- Gesto „odpověď tahem“ při zavírání chatu v ladicím buildu padalo na
  vytvoření animace nad zrušeným prvkem.
- Na iPhonu hlásila dlaždice Push v Nastavení chybu (volala UnifiedPush,
  který existuje jen na Androidu).

### Změněno
- **Nová ikona aplikace:** Š, které se ve spodní části rozpadá do teček.

## [1.2.1] – 2026-10-09

### Opraveno
- **Hovory se nedaly přijmout.** Příchozí signalizace hovoru se zahazovala dřív,
  než se dostala k obsluze hovoru; volaný jen „zazvonil“ z budíčku a pak nic.
- **Obrazovka hovoru po zavěšení:** avatar a jméno uskakovaly vlevo nahoru.
- **Obnova ze 24 slov na novém telefonu** končila nekonečným čekáním — server
  odmítal už existující identitu. Nové zařízení ji teď převezme podpisem.
- **Tichá ztráta zpráv:** úklid mizících zpráv mohl přepsat čerstvě přijatou
  zprávu; automatický zámek během zpracování zprávy ji mohl nenávratně zahodit;
  souběžné šifrování pro téhož příjemce dávalo obálky, které druhá strana
  zahodila. Všechny tři cesty opraveny.
- **Velká fronta po delším výpadku** (stovky zpráv) se už neodpojuje v půlce
  a server ji po osmi pokusech nemaže.
- **Nátlakový PIN** otevíral relaci se skutečnou identitou, frází i přístupem ke
  smazání účtu. Teď je izolovaná: náhodná identita, žádná síť, žádný zásah do
  klíčů; smazání v ní nechá skutečný účet být.
- Zvonění z budíčku bez skutečné nabídky končí po 12 s; server budíčky hovoru
  omezuje na cíl, takže cizí člověk se znalostí adresy telefon nerozezvoní
  pořád dokola.
- Dodatečné odeslání z fronty neztrácí anketu ani zmínky; budíček při
  „připojeno“ bez provozu obnoví spojení.

### Bezpečnost
- Hádání PINu: po pěti chybách prodleva 30 s, dál dvojnásobná až 15 minut.
- Nátlakový a skutečný PIN se ověřují jednou derivací — čas odemčení neprozradí,
  který byl zadán.
- Biometrie jen biometricky (zámek telefonu appku neodemkne); zabezpečení
  obrazovky je výchozí zapnuté a po odemčení skutečně platí; na iOS klíče
  nepřecházejí do iCloud Keychain ani záloh; filtr proti dotykům přes překryvná okna.
- Server: doplňování jednorázových klíčů a rotace podepsaných klíčů
  (`POST /v1/keys`), omezení výdeje jednorázových klíčů na adresu, chyby v logu
  bez adres push endpointů, připnutí DNS u budíčků, globální strop příloh,
  limity délek, `/v1/ready`, uvolnění spojení při vypnutí, revize a zdroj
  v `/v1/server-info`.

## [1.2.0] – 2026-10-01

### Nový vzhled
- **Domovská obrazovka s kartami Chaty, Kontakty a Nastavení.** Velký
  nadpis, hledání v chatech i v obsahu zpráv (najde „klic“ i „klíč“),
  filtry Vše / Nepřečtené / Skupiny, připnuté chaty nahoře.
- **Konverzace s hloubkou.** Průsvitná hlavička a pole pro psaní nad jemnou
  tapetou, zprávy od stejného člověka se skládají do bloků, ve skupině
  avatar a jméno autora v jeho barvě.
- **Odpověď tahem doprava**, řádek „N nových zpráv“ na místě, kde jsi
  skončil, a tlačítko na nejnovější zprávy s počtem nových.
- **Hledání v konverzaci** se zvýrazněním a přeskakováním mezi výsledky;
  klepnutí na citaci skočí na původní zprávu.
- **Profil kontaktu a skupiny** po klepnutí na jméno nebo avatar: ověření,
  sdílené fotky, společné skupiny, mizící zprávy, ztlumení, blokování;
  u skupiny členové, přidání lidí, přejmenování a odchod.
- **Fotky přes celou obrazovku s listováním** všemi fotkami konverzace.
- **Každý člověk má vlastní barvu avataru** — všude stejnou, i po
  přejmenování.
- **„Přečteno“ je poznat na první pohled** — plná pilulka místo
  modrošedých fajfek, které na korálové bublině skoro nebyly vidět.

### Přidáno
- **Hovory a videohovory** 1:1, šifrované end-to-end. Tlačítka v hlavičce
  chatu; telefon zazvoní i se zavřenou aplikací (na iPhonu přes CallKit).
  Když přímé spojení nejde, hovor šifrovaně přepošle náš server.
  V chatu zůstane záznam „Hovor · 3:12“ nebo „Zmeškaný hovor“.
- **Rozepsaná zpráva zůstane.** Když odejdeš z chatu, text v poli
  počká, a v seznamu chatů je vidět jako „Koncept: …“.
- **Přeposlání** zprávy, fotky, souboru i hlasovky do jiného chatu nebo
  skupiny (podržet zprávu → Přeposlat).
- **Poznámky pro sebe** v kartě Kontakty: chat sám se sebou na odkazy,
  fotky a poznámky. Zůstává jen v telefonu, šifrovaně, nic nejde na server.
- **@zmínky ve skupinách.** Po napsání „@“ se nabídnou členové; zmíněný
  dostane upozornění, i když má skupinu ztlumenou.
- **Rychlejší přehrávání hlasovek** — 1,5× a 2×, rychlost si Šepot pamatuje.
- **Správci skupin.** Zakladatel je správce a může udělat správcem
  i další členy. Odebrat člena, měnit správce a přejmenovat skupinu smí
  jen správce; každou takovou změnu podepíše svým klíčem a ostatní telefony
  podpis ověří, takže ji nikdo nemůže podvrhnout ani za správce vydávat.
  U členů je odznak „Správce“, ostatní vidí akce neaktivní s vysvětlením.
  Dokud má někdo ve skupině starší verzi Šepotu, přidávat lidi smí dál
  každý, aby se skupina nerozdělila; se staršími verzemi skupiny fungují
  jako dosud. Existující skupiny se převedou samy, bez jediné zprávy.
- **Profilová fotka.** V Nastavení klepni na svůj avatar. Fotka se ořízne,
  zmenší a zbaví metadat a tvým kontaktům dorazí šifrovaně s další
  zprávou; u nich se ukáže všude místo iniciál.
- **Ankety** v chatu i ve skupině (plus → Anketa): jedna nebo víc
  odpovědí, pruhy výsledků a kdo jak hlasoval, hlas jde změnit i zrušit.
  Starší verze Šepotu uvidí otázku a možnosti jako text.
- **„píše…“** v hlavičce chatu, v seznamu chatů a jako tři tečky pod
  poslední zprávou. Stejně jako potvrzení přečtení je volitelné (výchozí
  vypnuto) a oboustranné. Offline protistraně se nic neposílá do fronty ani
  ji to nebudí — server takové oznámení doručí jen živému spojení.
- **Čas doručení a přečtení.** Pod poslední odeslanou zprávou je vidět, kdy
  dorazila a kdy ji druhá strana přečetla. Po podržení zprávy ukáže „Info
  o zprávě“ čas odeslání, doručení a přečtení — ve skupině u každého člena
  zvlášť. Čas přečtení se ukazuje jen lidem, kteří potvrzení přečtení
  sdílejí oboustranně (výchozí vypnuto).
- **Přidání lidí do skupiny.** Do existující skupiny jde nově přidat
  kontakty z nabídky skupiny nebo ze seznamu členů.

### Změněno
- **Notifikace jsou na Androidu zapnuté od začátku.** Bez nich systém
  Šepot na pozadí uspí a zprávy čekají, dokud aplikaci neotevřeš. Kdo má
  UnifiedPush distributor (např. ntfy), dostane ho; ostatním se zapne
  budíček přes Google (FCM). Google přitom vidí jen to, že má telefon
  probudit — ne obsah ani odesílatele. Přepnout či vypnout jde v Nastavení.
- **Dvojitá fajfka ve skupině** svítí až ve chvíli, kdy zpráva dorazila
  všem členům, ne jen prvnímu.

### Opraveno
- **Ztlumená skupina dál posílala upozornění.** Ztlumení se u skupinové
  zprávy kontrolovalo v chatu s autorem, ne ve skupině.
- **Odesílané fotky nesly polohu (GPS) a údaje o telefonu.** Zpracování
  fotky před odesláním metadata EXIF nečekaně zachovávalo — v odeslané
  fotce i v jejím náhledu. Nově se před odesláním vždy odstraní.
- **Zablokovaný kontakt se mohl sám odblokovat**, když změnil adresu pro
  doručování.
- **„Přečteno“ se už nevrací na „doručeno“.** Když potvrzení o doručení
  dorazilo po potvrzení přečtení (typicky po výpadku spojení), zpráva se
  tvářila jako nepřečtená.
- **Zpráva označená jako neodeslaná** se po doručení sama opraví na
  doručenou.
- **Nastavení ukazovalo starou verzi aplikace.** Číslo verze bylo v kódu
  napsané ručně a při vydání 1.1.1 a 1.1.2 se ho zapomnělo přepsat, takže
  se všude hlásila 1.1.0 — včetně hlášení zneužití, u kterých pak nešlo
  dohledat, ze které verze přišla. Verze se nově čte z nainstalovaného
  balíčku a k hlášení se přikládá i číslo buildu.

## [1.1.2] – 2026-08-13

### Opraveno
- **Zprávy už nečekají na otevření aplikace.** Když mobilní síť tiše
  zahodila nečinné spojení, Šepot o tom nevěděl: tvářil se připojeně, ale
  odeslaná zpráva skončila chybou a příchozí nedorazily — a všechny se pak
  vysypaly naráz po restartu aplikace. Spojení se teď hlídá pravidelným
  pingem na obou stranách, takže výpadek se pozná a obnoví v řádu sekund.
- **Neodeslaná zpráva se pošle sama.** Dosud zůstala označená jako
  neodeslaná (u příloh dokonce natrvalo na „odesílá se") a poslat znovu ji
  musel člověk ručně. Nově se po obnovení spojení odešle sama; opakované
  doručení téže zprávy druhá strana pozná a nezobrazí ji dvakrát.
- **Zprávy, které nešly doručit, se přestaly hromadit.** Když se cestou
  ztratilo potvrzení o doručení, obálka na serveru zůstala a znovu a znovu
  se posílala, aniž by ji šlo přečíst. Server teď takové zprávy po několika
  marných pokusech zahodí, místo aby jimi zdržoval doručování ostatních.

### Přidáno
- **Upozornění, když nechodí notifikace.** Bez nich Android aplikaci na
  pozadí uspí a zprávy uvidíš, až ji otevřeš. Šepot to teď řekne rovnou v
  seznamu chatů a nabídne nastavení; hlášku jde odmítnout. Selhání
  registrace u distributora se už nezamlčí.

## [1.1.1] – 2026-07-18

### Opraveno
- **Odeslání první zprávy hned po instalaci už neselže.** Krátce po
  založení účtu, než se aplikace stihla připojit k relayi, mohla zpráva
  spadnout s hláškou „Odeslání selhalo". Nově se v tu chvíli ukáže
  srozumitelné „Šepot se ještě připojuje — zkus to za chvíli" a připojení
  proběhne na pozadí.
- **QR kód a odkaz se ukážou až s doručovací adresou.** Když sis chtěl
  ukázat vlastní QR dřív, než se aplikace poprvé připojila, vygeneroval se
  neúplný odkaz — protistrana pak nemohla poslat první zprávu („Kontakt
  nemá doručovací adresu"). Nově se místo neúplného kódu ukáže stav
  připojování a QR se objeví, jakmile je hotové.
- **Neúplný odkaz kontaktu se odmítne při přidání**, ne až při prvním
  odeslání — s jasnou výzvou požádat protistranu o nový odkaz.
- **Zamčení po nečinnosti už neumlčí aplikaci.** Po automatickém zamknutí
  a opětovném odemčení se zprávy zase přijímají i odesílají — dřív mohl
  messaging zůstat po odemčení vypnutý až do restartu aplikace.
- **Skupinová zpráva se při chybě neodeslání označí jako neodeslaná**
  místo aby zůstala navždy ve stavu „odesílá se".
- Ošetřeno vzácné zdvojení spojení s relayem při rychlém přepnutí Toru
  nebo zamčení během připojování.

### Změněno
- Interní úklid závislostí notifikací (odstraněna nepoužívaná větev, která
  komplikovala sestavení verze pro iOS).

## [1.1.0] – 2026-07-13

### Přidáno
- **Náhled fotky před odesláním.** Vyfocená nebo vybraná fotka už
  neodchází okamžitě — otevře se náhled, kde jde fotku otočit, kreslit
  po ní prstem (7 barev, krok zpět), přidat na ni text (tažením se
  přesouvá, klepnutím upraví) a připojit popisek. Odejde až po klepnutí
  na Odeslat; zavření náhledu nic nepošle.

### Opraveno
- **Nastavení se nevykreslilo** — obrazovka místo obsahu ukazovala
  chybovou hlášku „Tahle obrazovka se nevykreslila". Profilová karta
  předávala do překladu otisk klíče jako objekt místo textu.
- Avatar s iniciálami spadl na prázdném jménu nebo jménu s dvojitou
  mezerou; iniciály se nově skládají po grafémech, takže nerozpůlí emoji.
- **Písma se dodávají v aplikaci** (Inter, JetBrains Mono — OFL).
  Aplikace dřív stahovala fonty za běhu z Google CDN — síťový požadavek
  na cizí server navíc a binárka odlišná od zveřejněného zdroje.
- **Trvale vadná příchozí zpráva už neotravuje frontu.** Zpráva, jejíž
  obsah nejde po dešifrování zpracovat (poškozená pole od upraveného
  klienta), se potvrdí a zahodí — dřív se doručovala donekonečna při
  každém připojení. Nedešifrovatelné obálky fronta dál drží.
- Příloha s poškozeným náhledem od protistrany shodila vykreslení
  bubliny; vadný náhled se nově zahodí při příjmu a base64 krypto polí
  příloh se validuje.
- Zachycení výměny důvěryhodního kořene relaye (signál MITM) na
  pozadí — dřív tichá neošetřená výjimka, teď příznak čitelný pro UI.
- PNG bez průhlednosti (screenshoty, upravené fotky) se posílají jako
  JPEG — několikanásobně menší přenos; PNG zůstává jen pro obrázky se
  skutečnou průhledností.

## [1.0.0] – 2026-07-11

První ostrá verze. Šepot je od 11. 7. 2026 open source — kompletní
zdrojový kód aplikace i serveru je veřejný na
[gitea.ajtak.it/julius.joska/sepot](https://gitea.ajtak.it/julius.joska/sepot)
(zrcadlo [github.com/juliusjoska/sepot](https://github.com/juliusjoska/sepot)).

### Přidáno
- **Aplikace mluví pěti jazyky: česky, anglicky, německy, rusky
  a italsky.** Jazyk se řídí systémem (neznámé jazyky spadnou na
  angličtinu), nebo ho přepneš ručně v Nastavení → Obecné. Přeložené
  jsou i notifikace, chybové hlášky, iOS dialogy oprávnění a chybová
  obrazovka startu; volba jazyka funguje už na zamykací obrazovce.
- **Připojení přes Tor.** Přepínač v Nastavení → Připojení (Android,
  vyžaduje Orbot): provoz na server jde přes síť Tor a skryje tvou IP
  adresu. Přepnutí přestaví spojení za běhu, bez restartu aplikace.
- **Skupinové konverzace.** Skupinu (až 128 členů) založíš z Kontaktů,
  posílat do ní jde všechno co do běžného chatu — text, fotky, přílohy,
  hlasovky, reakce, odpovědi i mizící zprávy. Menu nabízí seznam členů,
  přejmenování a odchod. Zprávy jsou end-to-end šifrované každému členovi
  zvlášť, takže platí stejná ochrana jako v běžné konverzaci; server
  o skupině neví nic.

### Opraveno
- Automatický zámek, změna PINu i nátlakový PIN ověřeny na zařízení.

## [0.3.2] – 2026-07-10

### Přidáno
- **Smazání účtu maže i server.** „Smazat všechna data" nově kromě
  lokálního wipe odregistruje účet z relaye (`DELETE /v1/identity`):
  smaže se registrace identity, záznamy zařízení, distribuční klíče,
  push token i fronta nedoručených zpráv. Když je zařízení offline,
  aplikace na to upozorní a zbytek řeší podpora@sepot.cz.

### Opraveno
- iOS: privacy manifest (`PrivacyInfo.xcprivacy`) je součástí Xcode
  projektu — konec ručního vkládání při každém buildu (ITMS-91053).
- iOS: `Info.plist` měl dvakrát `CFBundleDisplayName` (jednou bez
  diakritiky) a povoloval landscape, ačkoli je aplikace zamčená na
  portrét. Sjednoceno.

## [0.3.1] – 2026-07-09

### Opraveno
- **Nahlašování už nevybízí k vkládání obsahu zpráv.** Formulář dřív nabízel
  „pokud chceš něco doložit, vlož to do popisu sám“. U hlášení o ohrožení
  dítěte by to znamenalo, že se k provozovateli dostane materiál, jehož
  držení je trestné — a k posouzení ho stejně nesmí použít. Nově formulář
  obsah odmítá a u této kategorie odkazuje na STOPonline.cz a Policii ČR.

## [0.3.0] – 2026-07-09

Nahlašování zneužití a standardy ochrany dětí — bez nich Šepot nesmí do
obchodů (Google Play UGC policy, Child Safety Standards, App Store 1.2).

### Přidáno
- **Nahlášení zneužití** — Nastavení → Bezpečnost → Nahlásit zneužití, nebo
  z menu konverzace. Do teď „nahlásit“ jen zablokovalo kontakt a nikam
  nedošlo; nově hlášení dorazí provozovateli. Kategorie zahrnují ohrožení
  dítěte (CSAE), které se řeší přednostně.
- **Standardy ochrany dětí** — veřejný dokument na
  [sepot.cz/bezpecnost-deti](https://sepot.cz/bezpecnost-deti), odkaz přímo
  z nastavení.
- **Deklarace exportní compliance** (`ITSAppUsesNonExemptEncryption`) —
  Šepot používá vlastní E2E šifrování, což se Applu hlásí pravdivě.

### Opraveno
- **iOS: bílá obrazovka po spuštění.** Nativní knihovna libsignal se na
  iPhonu nenačetla (framework je v `Frameworks/`, ale není zalinkovaný, a
  výchozí loader ho hledal v kořeni `.app`). Start teď knihovnu načítá přes
  `@rpath` a navíc už nikdy neskončí němou plochou — když se šifrovací
  jádro nespustí, objeví se čitelná chybová obrazovka s textem k odeslání.
- Verze uvedená v Nastavení → O aplikaci ukazovala pořád `0.1.0`.

### Poznámka k soukromí
Hlášení neodchází přes relay, ale na webový server sepot.cz — ten se při
odeslání dozví IP adresu odesílatele. Aplikace na to upozorňuje ještě před
odesláním. Obsah zpráv se neodesílá nikdy; do hlášení jde jen to, co
uživatel sám napíše.

## [0.2.0] – 2026-07-08

Velká funkční vlna — z E2E základu je plnohodnotný soukromý messenger.

### Přidáno
- **Jádro chatu** — odpovědi na zprávy, reakce emotikonem, úprava a mazání
  odeslaných zpráv.
- **Hlasové zprávy** — nahrávání mikrofonem přímo v chatu, přehrávání
  s průběhem. Šifrované per-file, plaintext audio nikdy nejde na disk.
- **Obnova účtu ze zálohovací fráze** — 24 slov vrátí tvoji identitu
  (stejný SEP kód, kontakty tě dál poznají).
- **Šifrované zálohy historie** — export/import konverzací; zálohu dešifruje
  jen tvoje identita.
- **Blokování a nahlášení kontaktu** — příchozí zprávy od blokovaného se
  zahodí.
- **Potvrzení přečtení** (volitelné, výchozí vypnuto).
- **Smazat u mě** — lokální smazání zprávy vedle „Smazat pro všechny".
- **Zabezpečení obrazovky** — blok screenshotů a skrytí obsahu v přepínači
  aplikací.
- **Nátlakový (decoy) PIN** — druhý PIN otevře prázdnou aplikaci; skutečná
  data zůstanou skrytá.
- **Nativní iOS push (APNs)** — bez závislosti na Googlu.

### Změněno
- **Sjednocené logo** napříč launcherem, splash obrazovkou i uvnitř aplikace.
- **Čistší pole pro psaní** — jeden tenký obrys, ikony uvnitř, nižší profil.
- **Bubliny se scalují** podle délky zprávy.

### Opraveno
- **Doručenky (✓✓)** se povýší i u offline příjemce, jakmile si zprávu
  vyzvedne.
- **Náhledy fotek** už neukazují předchozí obrázek (chyba recyklace v seznamu).

### Bezpečnost
- Zálohy i decoy PIN stojí na oddělených šifrovaných databázích a klíčích
  odvozených z identity.

## [0.1.0] – 2026-07-04

První beta.

### Přidáno
- **End-to-end šifrované zprávy** (libsignal, PQXDH + Double Ratchet,
  sealed sender) přes vlastní relay (WSS + Tor onion).
- **Fotky a dokumenty** — šifrované přílohy.
- **Ověření kontaktu** přes safety number a QR.
- **Mizící zprávy** s per-konverzace TTL.
- **PIN (Argon2id) a biometrické odemčení**, šifrovaná lokální DB (SQLCipher).
- **Push** — UnifiedPush (výchozí), FCM (opt-in).
- Bez telefonního čísla, bez e-mailu, bez reklam.

---

## Verzování

- **versionName `0.MINOR.PATCH`** v betě → **`1.0.0` = veřejné vydání**.
- **MINOR** = nová várka funkcí / milník (0.2.0 → 0.3.0 → 0.4.0…).
- **PATCH** = jen opravy chyb a drobnosti (0.2.1, 0.2.2…).
- **Build number** (`+N`) roste `+1` při každém uploadu, nezávisle na
  versionName, stejný pro iOS i Android. Uživatel ho nevidí.
