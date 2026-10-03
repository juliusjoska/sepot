import 'dart:async';
import 'dart:ui';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

/// Systémové zvonění (CallKit na iOS, celoobrazovkové na Androidu) pro
/// hovory, které přijdou, když appka není v popředí.
///
/// Budíček z relaye nenese, kdo volá — relay to neví. Zvonění z budíčku
/// proto ukáže „Šepot“ a označí se `extra.push`; až appka dešifruje
/// nabídku, [CallController] ho spáruje s hovorem podle toho.
class CallRinger {
  CallRinger._();

  static const _appName = 'Šepot';

  /// Zvonění vzniklé z budíčku, ke kterému ještě nedorazila nabídka.
  static const pushMarker = 'push';

  /// Jak dlouho zvoní — stejné jako expirace budíčku na relayi.
  static const ringMillis = 45000;

  static StreamSubscription<CallEvent?>? _sub;

  /// Id zvonění, která uživatel odmítl dřív, než dorazila nabídka.
  /// (Přijetí si pamatuje samo zvonění — `isAccepted` v [pendingPushRing].)
  static final declinedEarly = <String>{};

  static void listen({
    required void Function(String id) onAccept,
    required void Function(String id) onDecline,
    required void Function(String id) onEnded,
    required void Function() onVoipToken,
  }) {
    _sub ??= FlutterCallkitIncoming.onEvent.listen((event) {
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          onAccept(callKitParams.id);
        case CallEventActionCallDecline(:final callKitParams):
          onDecline(callKitParams.id);
        case CallEventActionCallEnded(:final callKitParams):
          onEnded(callKitParams.id);
        case CallEventActionDidUpdateDevicePushTokenVoip():
          onVoipToken();
        default:
          break;
      }
    });
  }

  static Future<String?> voipToken() async {
    final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    return token != null && token.isNotEmpty ? token : null;
  }

  /// Zvonění pro dešifrovanou nabídku (appka běží na pozadí).
  static Future<void> ringFor({
    required String callId,
    required String name,
    required bool video,
  }) =>
      FlutterCallkitIncoming.showCallkitIncoming(
          _params(id: callId, name: name, video: video));

  /// Zvonění z budíčku relaye — jméno ani typ hovoru ještě neznáme.
  static Future<void> ringFromPush() => FlutterCallkitIncoming
      .showCallkitIncoming(_params(
          id: const Uuid().v4(),
          name: _appName,
          video: false,
          extra: {pushMarker: true}));

  /// Zvonění z budíčku, které čeká na nabídku (nejnovější), a jestli ho
  /// uživatel už přijal — typicky na zamčené obrazovce, než appka naběhla.
  static Future<({String id, bool accepted})?> pendingPushRing() async {
    final calls = await FlutterCallkitIncoming.activeCalls();
    for (final call in calls.reversed) {
      if (call.extra?[pushMarker] == true) {
        return (id: call.id, accepted: call.isAccepted);
      }
    }
    return null;
  }

  static Future<void> connected(String id) =>
      FlutterCallkitIncoming.setCallConnected(id);

  static Future<void> end(String id) => FlutterCallkitIncoming.endCall(id);

  /// Texty zvonění. Zvonění z budíčku běží v izolátu na pozadí bez
  /// lokalizace appky, proto vlastní malý slovník podle jazyka systému.
  static const _texts = {
    'cs': ('Přijmout', 'Odmítnout', 'Příchozí hovory'),
    'de': ('Annehmen', 'Ablehnen', 'Eingehende Anrufe'),
    'it': ('Accetta', 'Rifiuta', 'Chiamate in arrivo'),
    'ru': ('Принять', 'Отклонить', 'Входящие звонки'),
    'en': ('Accept', 'Decline', 'Incoming calls'),
  };

  static (String, String, String) get _localTexts =>
      _texts[PlatformDispatcher.instance.locale.languageCode] ??
      _texts['en']!;

  static CallKitParams _params({
    required String id,
    required String name,
    required bool video,
    Map<String, dynamic>? extra,
  }) =>
      CallKitParams(
        id: id,
        nameCaller: name,
        appName: _appName,
        handle: _appName,
        type: video ? 1 : 0,
        duration: ringMillis,
        extra: extra ?? const {},
        missedCallNotification: const NotificationParams(
          showNotification: false,
        ),
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0B0C12',
          actionColor: '#7FAE8C',
          textColor: '#F0EEE8',
          incomingCallNotificationChannelName: _localTexts.$3,
          textAccept: _localTexts.$1,
          textDecline: _localTexts.$2,
          isShowFullLockedScreen: true,
        ),
        ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );
}
