/// Vstupní vrstva UnifiedPush — registruje se z main() PŘED runApp,
/// protože Android budí zabitou appku s argumentem `--unifiedpush-bg`
/// a bez UI: callbacky pak musí existovat dřív, než (ne)vznikne widget
/// tree.
///
/// Dvě situace při příchodu budíčku:
///   - appka běží (messaging nastartován) → wake: připoj WS, vylej frontu
///   - killed/zamčeno → DB je za PINem, nic nejde dešifrovat →
///     jen generická lokální notifikace (PushNotifier); zprávy se
///     stáhnou, až uživatel appku odemkne
///
/// Nový endpoint doručený na pozadí se NEDÁ poslat relayi (vyžaduje
/// autentizovaný WS + krypto z DB) → uloží se do OS keystore a odešle
/// při příštím plném startu (PushService.init ho vyzvedne).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sepot/core/push/apns_ios.dart';
import 'package:sepot/core/push/push_notifier.dart';
import 'package:sepot/core/push/push_service.dart';
import 'package:unifiedpush/unifiedpush.dart';

/// FCM budíček se zabitou appkou — plugin spouští handler ve vlastním
/// background isolate. Stejný model jako UnifiedPush killed-state:
/// DB je zamčená, nic nejde dešifrovat → jen generická notifikace.
@pragma('vm:entry-point')
Future<void> sepotFcmBackgroundWake(RemoteMessage message) async {
  await Firebase.initializeApp();
  await PushNotifier.showWakeNotification();
}

class PushBootstrap {
  PushBootstrap._();

  /// True = proces nastartoval Android kvůli pushi (`--unifiedpush-bg`),
  /// bez UI. main() pak NEvolá runApp.
  static bool backgroundStart = false;

  static PushService? _service;

  static const _pendingEndpointKey = 'pending_push_endpoint';
  static const _modeKey = 'push_mode'; // 'off' | 'up' | 'fcm'
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Režim pushů žije v OS keystore (NE v SQLCipher DB) — musí být
  /// čitelný před unlockem, aby main() věděl, zda registrovat FCM.
  static Future<String> readMode() async =>
      await _store.read(key: _modeKey) ?? 'off';

  static Future<void> writeMode(String mode) =>
      _store.write(key: _modeKey, value: mode);

  static Future<void> init(List<String> args) async {
    backgroundStart = args.contains('--unifiedpush-bg');

    // iOS: nativní APNs most. onWake musí fungovat i v killed-state
    // (iOS probudí engine tichým pushem), proto handler registrujeme tady,
    // před runApp. Messaging se napojí přes attach()/PushService.init.
    if (Platform.isIOS) {
      ApnsBridge.onWake = _wake;
      ApnsBridge.ensureHandler();
    } else {
      await UnifiedPush.initialize(
        onNewEndpoint: _onNewEndpoint,
        onRegistrationFailed: (_, _) {},
        onUnregistered: _onUnregistered,
        onMessage: _onMessage,
      );
    }

    // Firebase se dotkne Googlu (installations FID) → inicializovat
    // VÝHRADNĚ když si uživatel FCM režim sám zapnul.
    if (!Platform.isLinux && await readMode() == 'fcm') {
      try {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(sepotFcmBackgroundWake);
      } catch (_) {
        // bez google-services konfigurace / na desktopu — FCM nedostupné
      }
    }
  }

  /// Napojí plnou appku (messaging vrstvu) na už zaregistrované callbacky.
  static void attach(PushService service) {
    _service = service;
  }

  /// Sdílené probuzení (UnifiedPush i APNs): appka běží → připoj WS a
  /// vylej frontu; killed/zamčeno → generická notifikace bez obsahu.
  static void _wake() {
    final s = _service;
    if (s != null && s.canWake) {
      s.wake();
    } else {
      unawaited(PushNotifier.showWakeNotification());
    }
  }

  static void _onMessage(PushMessage message, String instance) {
    // Obsah budíčku se ZÁMĚRNĚ ignoruje (konstantní ťuk {"v":1}).
    final s = _service;
    if (s != null && s.canWake) {
      s.wake();
    } else {
      unawaited(PushNotifier.showWakeNotification());
    }
  }

  static void _onNewEndpoint(PushEndpoint endpoint, String instance) {
    final s = _service;
    if (s != null) {
      s.handleNewEndpoint(endpoint.url);
    } else {
      unawaited(_store.write(key: _pendingEndpointKey, value: endpoint.url));
    }
  }

  static void _onUnregistered(String instance) {
    _service?.handleUnregistered();
  }

  /// Vyzvedne (a smaže) endpoint uložený během background startu.
  static Future<String?> takePendingEndpoint() async {
    final value = await _store.read(key: _pendingEndpointKey);
    if (value != null) {
      await _store.delete(key: _pendingEndpointKey);
    }
    return value;
  }
}
