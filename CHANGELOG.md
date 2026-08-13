# Changelog

Všechny podstatné změny v aplikaci Šepot. Formát dle
[Keep a Changelog](https://keepachangelog.com/cs/1.1.0/),
verzování dle [ajtak standardu](#verzování).

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
