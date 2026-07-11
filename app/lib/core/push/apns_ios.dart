/// Nativní APNs most pro iOS (bez Firebase).
///
/// Komunikuje s AppDelegate.swift přes MethodChannel `cz.sepot.sepot/apns`:
///   Dart → native:  register (registerForRemoteNotifications), getToken
///   native → Dart:  onToken (APNs device token hex), onWake (tichý budíček)
///
/// APNs token se pošle relayi jako PLATFORM_APNS; relay pak posílá tichý
/// background budíček přímo přes Apple, žádný Google v cestě.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class ApnsBridge {
  ApnsBridge._();

  static const _channel = MethodChannel('cz.sepot.sepot/apns');
  static bool _handlerSet = false;

  /// Callback při vydání/změně APNs tokenu (hex string).
  static void Function(String token)? onToken;

  /// Callback při tichém budíčku (probudit WS a vylít frontu).
  static void Function()? onWake;

  static bool get isSupported => Platform.isIOS;

  /// Zaregistruje příjem native → Dart callbacků. Idempotentní; volat
  /// při startu (i killed-state, aby onWake fungoval po probuzení pushem).
  static void ensureHandler() {
    if (_handlerSet || !isSupported) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onToken':
          final token = call.arguments as String?;
          if (token != null) onToken?.call(token);
        case 'onWake':
          onWake?.call();
      }
      return null;
    });
  }

  /// Spustí nativní APNs registraci (systém se případně zeptá na povolení
  /// notifikací). Token dorazí asynchronně přes [onToken].
  static Future<void> register() async {
    if (!isSupported) return;
    ensureHandler();
    await _channel.invokeMethod<void>('register');
  }

  /// Už vydaný token (null, pokud APNs ještě neodpověděl).
  static Future<String?> currentToken() async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('getToken');
  }
}
