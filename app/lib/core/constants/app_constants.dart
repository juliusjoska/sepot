/// Konstanty aplikace Šepot
class AppConstants {
  AppConstants._();

  static const String appName = 'Šepot';
  /// Musí sedět s `version:` v pubspec.yaml (bez build čísla).
  static const String appVersion = '0.3.2';
  static const String appAuthor = 'ajtak.it';

  // Relay server (REST + WS na jednom portu). Přepsatelné při buildu:
  // flutter build --dart-define=SEPOT_RELAY=http://<dev-relay-host>:8470
  static const String relayUrl = String.fromEnvironment(
    'SEPOT_RELAY',
    defaultValue: 'https://relay.sepot.cz',
  );

  // Tor onion vstup relaye (HiddenServicePort 80 → relay:8470; onion vrstva
  // šifruje, TLS uvnitř netřeba). Používá se, když je v nastavení zapnutý
  // Tor — provoz jde přes SOCKS5 (Orbot) a jméno .onion resolvuje Tor
  // (viz TorTransport / MessagingService.setTorEnabled).
  static const String relayOnion =
      'http://cipjsctoeyf4fcrntvdvt22o2ansgr73qvthmewo246vuntd7cqmykyd.onion';

  // Kryptografické konstanty
  static const int pinLength = 6;
  // 24 slov = 32 B identity klíče enkódovaného přes BIP39 (žádný KDF)
  static const int seedPhraseWords = 24;

  // Úložiště - názvy Hive boxů
  static const String identityBox = 'identity';
  static const String contactsBox = 'contacts';
  static const String conversationsBox = 'conversations';
  static const String messagesBox = 'messages';
  static const String settingsBox = 'settings';

  // Nastavení zpráv
  static const int maxMessageLength = 4096;
  static const int defaultDisappearingSeconds = 86400; // 24 hodin

  // Přílohy — musí sedět s relayem (SEPOT_MAX_ATTACHMENT_BYTES, default
  // 25 MiB na ŠIFROVANÝ blob; plaintext strop držíme kousek pod tím)
  static const int maxAttachmentBytes = 25 * 1024 * 1024 - 64 * 1024;

  // Auto-lock timeout (v sekundách)
  static const int autoLockTimeout = 300; // 5 minut

  // Nahlašování zneužití. Endpoint NENÍ na relayi: relay drží jen opaque
  // obálky a nesmí získat čitelný kanál k obsahu. Nahlášení jde na web,
  // odkud chodí e-mail — a odesílatel je o tom v UI zpraven.
  static const String reportEndpoint = String.fromEnvironment(
    'SEPOT_REPORT_ENDPOINT',
    defaultValue: 'https://sepot.cz/api/nahlaseni',
  );

  /// Veřejné standardy ochrany dětí (Google Play CSAE, Apple 1.2).
  static const String childSafetyUrl = 'https://sepot.cz/bezpecnost-deti';

  /// Apple Guideline 5.1.1(i) žádá odkaz na zásady soukromí i UVNITŘ aplikace,
  /// nejen v metadatech obchodu.
  static const String privacyUrl = 'https://sepot.cz/ochrana-soukromi';
  static const String termsUrl = 'https://sepot.cz/podminky';
  static const String deletionUrl = 'https://sepot.cz/smazani-dat';

  static const String supportEmail = 'podpora@sepot.cz';
}
