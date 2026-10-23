/// Napojení UnifiedPush distributora na relay budíčky.
///
/// Tok:
///   distributor (ntfy) → onNewEndpoint → relay.registerPush(UNIFIEDPUSH, url)
///   příchozí budíček    → onMessage    → messaging.onPushWake()
///                         (připoj se na WS → vylej offline frontu)
///
/// Obsah budíčku se ZÁMĚRNĚ ignoruje — je to konstantní „ťuk" `{"v":1}`,
/// žádný obsah ani odesílatel jím neprochází. Stačí i nešifrovaný
/// (`decrypted == false`) — potřebujeme jen fakt „něco přišlo, připoj se".
///
/// Callbacky u UnifiedPush registruje [PushBootstrap] z main() (kvůli
/// killed-state startu `--unifiedpush-bg` bez UI); tahle třída je
/// most bootstrap ↔ messaging + API pro nastavení.
///
/// Výchozí režim na Androidu vybírá [restoreMode] při prvním startu: s
/// UnifiedPush distributorem UnifiedPush, jinak FCM. Bez budíčku Android
/// appku na pozadí uspí a zprávy čekají, než ji člověk otevře — to je pro
/// messenger horší než token u Googlu (obsah ani odesílatel budíčkem nejde).
/// Uživatel může kdykoli přepnout v Nastavení.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:sepot/core/calls/call_ringer.dart';
import 'package:sepot/core/push/apns_ios.dart';
import 'package:sepot/core/push/push_bootstrap.dart';
import 'package:sepot/core/push/push_notifier.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/proto/sepot.pb.dart' as pb;
import 'package:unifiedpush/unifiedpush.dart';

/// Nativní strana iOS pushů. Oddělená od [PushService], aby šlo pořadí
/// kroků a skládání registrace ověřit testem bez iPhonu.
class IosPushPlatform {
  const IosPushPlatform();

  bool get isIOS => Platform.isIOS;
  Future<void> registerApns() => ApnsBridge.register();
  Future<String?> apnsToken() => ApnsBridge.currentToken();
  Future<String?> voipToken() => CallRinger.voipToken();
  Future<void> requestPermission() => PushNotifier.requestPermission();
  Future<void> writeMode(String mode) => PushBootstrap.writeMode(mode);
  Future<void> setRegistrationFailed(bool failed) =>
      PushBootstrap.setRegistrationFailed(failed);
}

class PushService {
  PushService(this._messaging, {IosPushPlatform ios = const IosPushPlatform()})
      : _ios = ios;

  final MessagingService _messaging;
  final IosPushPlatform _ios;
  StreamSubscription<String>? _fcmTokenSub;
  StreamSubscription<RemoteMessage>? _fcmMessageSub;

  pb.RegisterPush _registration(pb.RegisterPush_Platform platform,
          [Uint8List? endpoint]) =>
      pb.RegisterPush(
        platform: platform,
        endpoint: endpoint ?? Uint8List(0),
      );

  /// Může budíček rovnou probudit WS? (Jinak jde generická notifikace.)
  bool get canWake => _messaging.isStarted;

  /// Budíček: běžící messaging připojí WS; po auto-locku (zamčená DB) aspoň
  /// generická notifikace bez obsahu, ať se uživatel o zprávě dozví.
  void wake() {
    if (canWake) {
      _messaging.onPushWake();
    } else {
      unawaited(PushNotifier.showWakeNotification());
    }
  }

  void handleNewEndpoint(String url) {
    _messaging.registerPush(_registration(
      pb.RegisterPush_Platform.PLATFORM_UNIFIEDPUSH,
      Uint8List.fromList(utf8.encode(url)),
    ));
  }

  void handleUnregistered() {
    // Distributor nás odregistroval → relay ať token smaže (anonymní režim).
    _messaging
        .registerPush(_registration(pb.RegisterPush_Platform.PLATFORM_NONE));
  }

  /// Napojí messaging na push callbacky a doručí relayi endpoint, který
  /// případně dorazil během killed-state startu. Idempotentní — volat po
  /// startu messaging vrstvy.
  Future<void> init() async {
    PushBootstrap.attach(this);
    final pending = await PushBootstrap.takePendingEndpoint();
    if (pending != null) {
      handleNewEndpoint(pending);
    }
    // iOS: APNs token → relay jako PLATFORM_APNS; tichý budíček → wake.
    if (ApnsBridge.isSupported) {
      ApnsBridge.onToken = _registerApnsToken;
      ApnsBridge.onWake = wake;
      ApnsBridge.ensureHandler();
    }
  }

  String? _apnsToken;

  /// Registrace iOS pushů pro relay: APNs token pro zprávy + VoIP token pro
  /// hovory (relay drží obojí u zařízení). VoIP token jde i sám, s prázdným
  /// endpointem — PushKit ho vydá nezávisle na APNs a hovory nesmí čekat,
  /// až Apple vydá i token pro zprávy. Null = zatím není co poslat.
  @visibleForTesting
  static pb.RegisterPush? apnsRegistration({
    String? apnsToken,
    String? voipToken,
  }) {
    if (apnsToken == null && voipToken == null) return null;
    final reg = pb.RegisterPush(
      platform: pb.RegisterPush_Platform.PLATFORM_APNS,
      endpoint: apnsToken == null
          ? Uint8List(0)
          : Uint8List.fromList(utf8.encode(apnsToken)),
    );
    if (voipToken != null) reg.voipToken = utf8.encode(voipToken);
    return reg;
  }

  Future<void> _sendApnsRegistration() async {
    final reg = apnsRegistration(
      apnsToken: _apnsToken,
      voipToken: await _ios.voipToken(),
    );
    if (reg != null) _messaging.registerPush(reg);
  }

  Future<void> _registerApnsToken(String token) async {
    _apnsToken = token;
    await _sendApnsRegistration();
  }

  /// PushKit vydal (nový) VoIP token — poslat ho relayi, i když APNs token
  /// pro zprávy ještě nedorazil.
  Future<void> refreshVoipToken() => _sendApnsRegistration();

  /// iOS nativní push (APNs) — zapne registraci u Apple; token přijde
  /// asynchronně a sám se pošle relayi. Bez Googlu.
  ///
  /// Registrace u Apple jde PŘED žádostí o oprávnění: tichý budíček
  /// oprávnění nepotřebuje, takže odmítnutý (nebo selhaný) dialog nesmí
  /// zastavit doručování zpráv.
  Future<void> enableApns() async {
    await init();
    await _ios.registerApns();
    await _ios.writeMode('apns');
    final existing = await _ios.apnsToken();
    if (existing != null) {
      await _registerApnsToken(existing);
    } else {
      // VoIP token mohl přijít dřív než APNs — hovory ať zvoní hned.
      await _sendApnsRegistration();
    }
    try {
      await _ios.requestPermission();
    } catch (e, s) {
      // Bez oprávnění chodí budíčky dál, jen bez viditelné notifikace.
      debugPrint('Oprávnění k notifikacím selhalo: $e\n$s');
    }
  }

  /// Zapne push: použije uloženého/výchozího distributora a zaregistruje se.
  /// Vrací `false`, když žádný distributor není (uživatel musí nainstalovat
  /// např. ntfy nebo vybrat přes [distributors]/[useDistributor]).
  Future<bool> enable() async {
    await init();
    // Android 13+: bez POST_NOTIFICATIONS by killed-state budíček zapadl
    await PushNotifier.requestPermission();
    final ok = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    if (!ok) return false;
    await UnifiedPush.register();
    return true;
  }

  /// Seznam nainstalovaných distributorů (pro výběr v nastavení).
  /// UnifiedPush existuje jen na Androidu; jinde by volání pluginu vyhodilo
  /// UnimplementedError (iOS: dlaždice Push v Nastavení).
  Future<List<String>> distributors() async =>
      Platform.isAndroid ? UnifiedPush.getDistributors() : const [];

  /// Aktuálně uložený distributor (null = push vypnutý / nevybraný).
  Future<String?> currentDistributor() async =>
      Platform.isAndroid ? UnifiedPush.getDistributor() : null;

  /// Vybere konkrétního distributora a zaregistruje se u něj.
  Future<void> useDistributor(String distributor) async {
    await init();
    await PushNotifier.requestPermission();
    await UnifiedPush.saveDistributor(distributor);
    await UnifiedPush.register();
  }

  /// Vypne push: odregistruje u distributora a řekne relayi smazat token.
  Future<void> disable() async {
    await UnifiedPush.unregister();
    handleUnregistered();
  }

  Future<bool> get isEnabled async =>
      Platform.isAndroid && (await UnifiedPush.getDistributor()) != null;

  // ── Režimy (off / up / fcm) ─────────────────────────────────────────

  /// Aktuální režim; 'up' zpětně dovodí z vybraného distributora
  /// (instalace před zavedením režimů).
  Future<String> currentMode() async {
    final mode = await PushBootstrap.readMode();
    if (mode != 'off') return mode;
    if (!Platform.isAndroid) return mode;
    return (await UnifiedPush.getDistributor()) != null ? 'up' : 'off';
  }

  /// Odmítl distributor poslední registraci? Nastavení to ukáže — jinak by
  /// push vypadal zapnutý, ale budíčky by nechodily.
  Future<bool> registrationFailed() => PushBootstrap.registrationFailed();

  Future<void> setModeOff() async {
    await _teardownFcm(deleteToken: true);
    try {
      await UnifiedPush.unregister();
    } catch (_) {}
    handleUnregistered();
    await PushBootstrap.writeMode('off');
  }

  /// UnifiedPush režim (default, degooglovaný). Vrací false, když chybí
  /// distributor — UI pak nabídne výběr/instalaci.
  Future<bool> setModeUnifiedPush() async {
    await _teardownFcm(deleteToken: true);
    final ok = await enable();
    if (ok) await PushBootstrap.writeMode('up');
    return ok;
  }

  /// FCM: registrační token zařízení jde Googlu (obsah budíčků nikdy,
  /// ťuk je konstantní `{"v":1}`).
  Future<void> setModeFcm() async {
    await init();
    try {
      await UnifiedPush.unregister();
    } catch (_) {}
    await PushNotifier.requestPermission();
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(sepotFcmBackgroundWake);

    final fm = FirebaseMessaging.instance;
    final token = await fm.getToken();
    if (token == null) {
      throw StateError('failed to obtain FCM token');
    }
    _registerFcmToken(token);
    _fcmTokenSub ??= fm.onTokenRefresh.listen(_registerFcmToken);
    // popředí: ťuk → připojit WS (paralela k UnifiedPush onMessage)
    _fcmMessageSub ??= FirebaseMessaging.onMessage.listen((_) => wake());
    await PushBootstrap.writeMode('fcm');
  }

  void _registerFcmToken(String token) {
    _messaging.registerPush(_registration(
      pb.RegisterPush_Platform.PLATFORM_FCM,
      Uint8List.fromList(utf8.encode(token)),
    ));
  }

  Future<void> _teardownFcm({required bool deleteToken}) async {
    await _fcmTokenSub?.cancel();
    _fcmTokenSub = null;
    await _fcmMessageSub?.cancel();
    _fcmMessageSub = null;
    if (deleteToken) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {
        // Firebase neinicializovaný / bez sítě — token vyprší sám
      }
    }
  }

  /// Obnova režimu po startu appky (volá pushInitProvider).
  Future<void> restoreMode() async {
    // iOS: jediná smysluplná cesta je APNs (UnifiedPush je Android-only).
    // Zapínáme ho automaticky — pro iOS messenger jsou notifikace základ.
    if (_ios.isIOS) {
      try {
        await enableApns();
        await _ios.setRegistrationFailed(false);
      } catch (e, s) {
        // Dřív se chyba spolkla a iPhone tiše zůstal bez budíčků. Teď ji
        // uvidí stav pushů v chat listu (PushHealth.failed).
        debugPrint('APNs registrace selhala: $e\n$s');
        await _ios.setRegistrationFailed(true);
        await init();
      }
      return;
    }
    if (await PushBootstrap.readStoredMode() == null) {
      await _chooseDefaultMode();
      return;
    }
    switch (await currentMode()) {
      case 'up':
        await enable();
      case 'fcm':
        try {
          await setModeFcm();
        } catch (_) {
          // bez sítě — token registrace proběhne při příštím startu
        }
      default:
        await init(); // aspoň attach (killed-state notifikace)
    }
  }

  /// První start na Androidu (nebo instalace z doby, kdy byl push
  /// opt-in a nikdo ho nezapnul). Kdo má nainstalovaný UnifiedPush
  /// distributor, vybral si degooglovanou cestu sám — dostane ji.
  /// Ostatním zapneme FCM. Telefon bez Google služeb token nedostane;
  /// pak zapíšeme „off", ať se to nezkouší při každém startu — seznam
  /// chatů na chybějící budíčky upozorní sám.
  Future<void> _chooseDefaultMode() async {
    try {
      if ((await currentMode()) == 'up' ||
          (await distributors()).isNotEmpty) {
        if (await setModeUnifiedPush()) return;
      }
      await setModeFcm();
    } catch (_) {
      await init();
      await PushBootstrap.writeMode('off');
    }
  }
}
