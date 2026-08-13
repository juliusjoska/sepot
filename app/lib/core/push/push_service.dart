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
/// FCM „fast mode" (opt-in) je druhá cesta (viz [setModeFcm]); default je
/// degooglovaný UnifiedPush.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sepot/core/push/apns_ios.dart';
import 'package:sepot/core/push/push_bootstrap.dart';
import 'package:sepot/core/push/push_notifier.dart';
import 'package:sepot/core/services/messaging_service.dart';
import 'package:sepot/proto/sepot.pb.dart' as pb;
import 'package:unifiedpush/unifiedpush.dart';

class PushService {
  PushService(this._messaging);

  final MessagingService _messaging;
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

  void wake() => _messaging.onPushWake();

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

  void _registerApnsToken(String token) {
    _messaging.registerPush(_registration(
      pb.RegisterPush_Platform.PLATFORM_APNS,
      Uint8List.fromList(utf8.encode(token)),
    ));
  }

  /// iOS nativní push (APNs) — zapne registraci u Apple; token přijde
  /// asynchronně a sám se pošle relayi. Bez Googlu.
  Future<void> enableApns() async {
    await init();
    await PushNotifier.requestPermission();
    await ApnsBridge.register();
    final existing = await ApnsBridge.currentToken();
    if (existing != null) _registerApnsToken(existing);
    await PushBootstrap.writeMode('apns');
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
  Future<List<String>> distributors() => UnifiedPush.getDistributors();

  /// Aktuálně uložený distributor (null = push vypnutý / nevybraný).
  Future<String?> currentDistributor() => UnifiedPush.getDistributor();

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
      (await UnifiedPush.getDistributor()) != null;

  // ── Režimy (off / up / fcm) ─────────────────────────────────────────

  /// Aktuální režim; 'up' zpětně dovodí z vybraného distributora
  /// (instalace před zavedením režimů).
  Future<String> currentMode() async {
    final mode = await PushBootstrap.readMode();
    if (mode != 'off') return mode;
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

  /// FCM fast mode — OPT-IN: registrační token zařízení jde Googlu
  /// (obsah budíčků nikdy, ťuk je konstantní `{"v":1}`).
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
    if (Platform.isIOS) {
      try {
        await enableApns();
      } catch (_) {
        await init();
      }
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
}
