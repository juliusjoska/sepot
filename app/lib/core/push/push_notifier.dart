/// Lokální notifikace pro push budíčky.
///
/// Zásada: notifikace NIKDY nenese obsah, odesílatele ani počet zpráv —
/// při killed-state budíčku je DB zamčená (PIN → Argon2id), takže ani
/// technicky NELZE nic dešifrovat. Generické „máš nové zprávy" je tudíž
/// jediná poctivá (a metadata-čistá) možnost — stejný model jako
/// zamčený Threema/Signal.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/providers/locale_provider.dart';

class PushNotifier {
  PushNotifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Jedno pevné id — opakované budíčky aktualizují touž notifikaci,
  /// žádné hromadění (počet by sám o sobě byl metadata leak).
  static const int _notificationId = 1;

  static Future<void> _ensureInit() async {
    if (_ready) return;
    final l10n = l10nFor(await LocaleNotifier.readStored());
    await _plugin.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Bez iOS nastavení plugin hodí ArgumentError a s ním padala celá
        // APNs registrace — iPhony relayi neposlaly token vůbec. O oprávnění
        // se žádá až v [requestPermission], ne při první notifikaci.
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(
          defaultActionName: l10n.pushActionOpen,
        ),
      ),
    );
    _ready = true;
  }

  /// Sdílené detaily notifikace — channel ID 'zpravy' je NEMĚNNÉ
  /// (Android by při změně vytvořil nový kanál), name/description se
  /// lokalizují (systém je čte při vytvoření kanálu).
  static NotificationDetails _details(AppLocalizations l10n) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'zpravy',
        l10n.pushChannelMessagesName,
        channelDescription: l10n.pushChannelMessagesDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
      ),
      iOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
    );
  }

  /// Oprávnění k viditelným notifikacím (Android 13+, iOS) — volat při
  /// zapnutí pushe. Tichý budíček na iOS ho nepotřebuje.
  static Future<void> requestPermission() async {
    await _ensureInit();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Notifikace o přijaté zprávě, když appka běží, ale není v popředí.
  /// Jen jméno odesílatele — obsah zprávy do notifikace NIKDY (šifrovaný
  /// obsah nepatří do notification logu OS ani na zamčenou obrazovku).
  static Future<void> showMessageNotification(String senderName) async {
    await _ensureInit();
    final l10n = l10nFor(await LocaleNotifier.readStored());
    await _plugin.show(
      _notificationId,
      l10n.commonAppName,
      l10n.pushNewMessageFrom(senderName),
      _details(l10n),
    );
  }

  /// Zpráva od neznámého odesílatele (žádost o zprávu): bez jména, které
  /// si zvolil sám.
  static Future<void> showMessageRequestNotification() async {
    await _ensureInit();
    final l10n = l10nFor(await LocaleNotifier.readStored());
    await _plugin.show(
      _notificationId,
      l10n.commonAppName,
      l10n.pushMessageRequest,
      _details(l10n),
    );
  }

  /// Generická notifikace bez obsahu. Klepnutí otevře appku (unlock →
  /// WS připojení → fronta se vyleje normální cestou).
  static Future<void> showWakeNotification() async {
    await _ensureInit();
    final l10n = l10nFor(await LocaleNotifier.readStored());
    await _plugin.show(
      _notificationId,
      l10n.commonAppName,
      l10n.pushNewMessages,
      _details(l10n),
    );
  }
}
