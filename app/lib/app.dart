import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/push/apns_ios.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/core/utils/externi_obrazovka.dart';
import 'package:sepot/core/calls/call_controller.dart';
import 'package:sepot/features/auth/change_pin_screen.dart';
import 'package:sepot/features/calls/call_screen.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/features/onboarding/onboarding_screen.dart';
import 'package:sepot/features/onboarding/restore_screen.dart';
import 'package:sepot/features/auth/pin_setup_screen.dart';
import 'package:sepot/features/auth/pin_lock_screen.dart';
import 'package:sepot/features/chat_list/chat_list_screen.dart';
import 'package:sepot/features/chat_list/archived_chats_screen.dart';
import 'package:sepot/features/conversation/conversation_screen.dart';
import 'package:sepot/features/contacts/contact_verify_screen.dart';
import 'package:sepot/features/contacts/contacts_screen.dart';
import 'package:sepot/features/groups/create_group_screen.dart';
import 'package:sepot/features/profile/contact_profile_screen.dart';
import 'package:sepot/features/profile/group_profile_screen.dart';
import 'package:sepot/features/settings/settings_screen.dart';
import 'package:sepot/features/safety/report_screen.dart';
import 'package:sepot/features/qr_pairing/qr_share_screen.dart';
import 'package:sepot/features/qr_pairing/qr_scan_screen.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/locale_provider.dart';
import 'package:sepot/providers/settings_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/incoming_message_banner.dart';

/// Hlavní router aplikace
final _router = GoRouter(
  initialLocation: '/loading',
  routes: [
    GoRoute(
      path: '/loading',
      builder: (context, state) => const _LoadingScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/restore',
      builder: (context, state) => const RestoreScreen(),
    ),
    GoRoute(
      path: '/pin-setup',
      builder: (context, state) => const PinSetupScreen(),
    ),
    GoRoute(
      path: '/pin-lock',
      builder: (context, state) => const PinLockScreen(),
    ),
    GoRoute(
      path: '/chats',
      builder: (context, state) => const ChatListScreen(),
    ),
    GoRoute(
      path: '/archived',
      builder: (context, state) => const ArchivedChatsScreen(),
    ),
    GoRoute(
      path: '/conversation/:contactId',
      builder: (context, state) => ConversationScreen(
        contactId: state.pathParameters['contactId']!,
        startSearch: state.uri.queryParameters['search'] == '1',
      ),
    ),
    GoRoute(
      path: '/contact/:contactId',
      builder: (context, state) => ContactProfileScreen(
        contactId: state.pathParameters['contactId']!,
        fromChat: state.uri.queryParameters['from'] == 'chat',
      ),
    ),
    GoRoute(
      path: '/group/:groupId',
      builder: (context, state) => GroupProfileScreen(
        groupId: state.pathParameters['groupId']!,
        fromChat: state.uri.queryParameters['from'] == 'chat',
      ),
    ),
    GoRoute(
      path: '/contacts',
      builder: (context, state) => const ContactsScreen(),
    ),
    GoRoute(
      path: '/create-group',
      builder: (context, state) => const CreateGroupScreen(),
    ),
    GoRoute(
      path: '/group/:groupId/add',
      builder: (context, state) =>
          CreateGroupScreen(addToGroupId: state.pathParameters['groupId']),
    ),
    GoRoute(
      path: '/verify/:contactId',
      builder: (context, state) => ContactVerifyScreen(
        contactId: state.pathParameters['contactId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/report',
      builder: (context, state) => ReportScreen(
        reportedFingerprint: state.uri.queryParameters['contact'],
        reportedName: state.uri.queryParameters['name'],
      ),
    ),
    GoRoute(
      path: '/qr-share',
      builder: (context, state) => const QrShareScreen(),
    ),
    GoRoute(
      path: '/qr-scan',
      builder: (context, state) => const QrScanScreen(),
    ),
    GoRoute(
      path: '/change-pin',
      builder: (context, state) => const ChangePinScreen(),
    ),
    GoRoute(
      path: '/call',
      builder: (context, state) => const CallScreen(),
    ),
  ],
);

/// Obrazovky, ze kterých nemá smysl zamykat (nebo už zamčené jsou).
const _bezZamku = {'/pin-lock', '/onboarding', '/restore', '/pin-setup', '/loading'};

/// Hlavní widget aplikace
class SepotApp extends ConsumerWidget {
  const SepotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null = systémový jazyk; než se volba načte z keystore, jede systém.
    final locale = ref.watch(localeProvider).valueOrNull;

    // Příchozí i odchozí hovor otevře obrazovku hovoru odkudkoli.
    ref.listen(callProvider.select((s) => s.phase), (previous, phase) {
      final starting =
          phase == CallPhase.incoming || phase == CallPhase.outgoing;
      final path = _router.routerDelegate.currentConfiguration.uri.path;
      if (starting && previous != phase && path != '/call') {
        _router.push('/call');
      }
    });

    return _AutoLockGate(
      child: _ForegroundMessages(
        child: MaterialApp.router(
          onGenerateTitle: (context) => context.l10n.appTitle,
          theme: SepotTheme.dark,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          // Explicitní pořadí: první položka je fallback pro systémové jazyky,
          // které nepodporujeme (např. francouzština → angličtina, ne čeština).
          supportedLocales: const [
            Locale('en'),
            Locale('cs'),
            Locale('de'),
            Locale('ru'),
            Locale('it'),
          ],
        ),
      ),
    );
  }
}

/// Banner a vibrace pro zprávu, která přijde do běžící appky v popředí.
///
/// Stojí nad MaterialApp, takže texty i overlay bere z navigátoru routeru.
/// Zpráva do právě otevřeného chatu se neoznamuje: člověk ji vidí.
class _ForegroundMessages extends ConsumerStatefulWidget {
  const _ForegroundMessages({required this.child});

  final Widget child;

  @override
  ConsumerState<_ForegroundMessages> createState() =>
      _ForegroundMessagesState();
}

class _ForegroundMessagesState extends ConsumerState<_ForegroundMessages> {
  StreamSubscription<ForegroundMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(foregroundMessagesProvider).stream.listen(_ukaz);
  }

  @override
  void dispose() {
    _sub?.cancel();
    IncomingMessageBanner.hide();
    super.dispose();
  }

  void _ukaz(ForegroundMessage zprava) {
    final cesta = '/conversation/${zprava.convId}';
    final kde = _router.routerDelegate.currentConfiguration.uri.path;
    // Na hovoru a zamykacích obrazovkách by banner jen překážel.
    if (kde == cesta || kde == '/call' || _bezZamku.contains(kde)) return;

    final navigator = _router.routerDelegate.navigatorKey.currentState;
    final overlay = navigator?.overlay;
    if (navigator == null || overlay == null) return;
    final l10n = navigator.context.l10n;
    final jmeno = zprava.senderName;

    IncomingMessageBanner.show(
      overlay,
      text: jmeno != null
          ? l10n.pushNewMessageFrom(jmeno)
          : zprava.isRequest
          ? l10n.pushMessageRequest
          : l10n.pushNewMessages,
      avatarName: jmeno ?? '?',
      avatarSeed: zprava.senderId,
      onTap: () => _router.push(cesta),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Hlídá, jak dlouho byla appka na pozadí, a po vypršení limitu zamkne.
///
/// Zamknout znamená zavřít SQLCipher DB. Kdyby přitom běžel messaging,
/// příchozí zpráva by sáhla na zavřenou DB → proto se služba nejdřív
/// zastaví a `messagingStartProvider` invaliduje, aby se po odemčení
/// nastartovala znovu (FutureProvider by se sám nespustil).
class _AutoLockGate extends ConsumerStatefulWidget {
  const _AutoLockGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_AutoLockGate> createState() => _AutoLockGateState();
}

class _AutoLockGateState extends ConsumerState<_AutoLockGate>
    with WidgetsBindingObserver {
  DateTime? _naPozadiOd;

  /// Odešla appka na pozadí kvůli výběru fotky, souboru nebo sdílení?
  /// Zachytí se v okamžiku odchodu: výběr může skončit dřív, než přijde
  /// `resumed`, a pak by už [ExterniObrazovka.otevrena] lhala.
  bool _odchodKvuliExterni = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Spuštění klepnutím na notifikaci není návrat z pozadí (resumed).
    unawaited(ApnsBridge.clearMessageAlerts());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_naPozadiOd != null) break;
        _naPozadiOd = DateTime.now();
        _odchodKvuliExterni = ExterniObrazovka.otevrena;
        // Okamžitý zámek se uzavírá hned při odchodu, ne až po návratu:
        // jinak by se po odemčení telefonu na zlomek vteřiny ukázal chat.
        unawaited(_zvazZamek(Duration.zero));
      case AppLifecycleState.resumed:
        unawaited(ApnsBridge.clearMessageAlerts());
        final od = _naPozadiOd;
        _naPozadiOd = null;
        if (od == null) break;
        // Seznam chatů jinak obnovuje jen MessagingService.onUpdate; po
        // pobytu na pozadí (uspaný proces, budíček push) na to nespoléhat —
        // nové zprávy se pak ukázaly až po vstupu do konverzace a zpět.
        // Přenačtení z lokální DB je levné.
        if (ref.read(storageProvider).isUnlocked) {
          ref.invalidate(conversationsProvider);
          // Otevřená konverzace se přenačítá zvlášť (celá family), jinak
          // zprávy z doby na pozadí ukáže až po odchodu a návratu do chatu.
          ref.invalidate(conversationProvider);
        }
        unawaited(_zvazZamek(DateTime.now().difference(od)));
      case AppLifecycleState.inactive:
        break; // krátký přechod (notifikační lišta, hovor) — neřešit
    }
  }

  Future<void> _zvazZamek(Duration pryc) async {
    final storage = ref.read(storageProvider);
    if (!storage.isUnlocked) return;
    if (!await storage.hasPin()) return;
    // Zámek zastaví messaging a s ním i běžící hovor. Hovor na pozadí
    // (zhasnutý displej u ucha) je normální stav, ne opuštěná appka.
    if (ref.read(callProvider).busy) return;

    final limit = await ref.read(autoLockProvider.future);
    if (!AutoLockNotifier.maZamknout(
      nastaveni: limit,
      pryc: pryc,
      kvuliExterniObrazovce: _odchodKvuliExterni,
    )) {
      return;
    }

    final kde = _router.state.uri.path;
    if (_bezZamku.contains(kde)) return;

    // Zastavit službu a zamknout DB. messagingStartProvider ZÁMĚRNĚ
    // neinvalidujeme tady — invalidace by ho eager-rebuildla ještě nad
    // odemčeným storage (těsně před lock) a messaging by nastartoval nad DB,
    // kterou hned zavíráme. Restart řeší odemykací obrazovky přes
    // ref.invalidate(messagingStartProvider) až po úspěšném unlocku.
    await ref.read(messagingServiceProvider).stop();
    storage.lock();
    _router.go('/pin-lock');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Načítací obrazovka — rozhodne, kam navigovat
class _LoadingScreen extends ConsumerStatefulWidget {
  const _LoadingScreen();

  @override
  ConsumerState<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<_LoadingScreen> {
  @override
  void initState() {
    super.initState();
    // Aplikuj zabezpečení obrazovky co nejdřív (window flag přetrvá napříč
    // obrazovkami) — ať je chráněný i lock/onboarding.
    ref.read(screenSecurityProvider);
    _checkState();
  }

  Future<void> _checkState() async {
    // Minimální doba splashe, ať načítací obrazovka neproblikne (skutečná
    // inicializace se awaituje níž přes provider.future).
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final isOnboarded = await ref.read(isOnboardingCompleteProvider.future);
    final hasPin = await ref.read(hasPinProvider.future);

    if (!mounted) return;

    if (!isOnboarded) {
      context.go('/onboarding');
    } else if (hasPin) {
      // Odemkne PIN obrazovka (Argon2id unwrap DEK)
      context.go('/pin-lock');
    } else {
      // Bez PINu — DEK přímo z OS keystore. PIN je povinný a v appce nejde
      // vypnout, takže sem vede jen nedokončené nastavení: registrace i obnova
      // se označí za hotové dřív, než se PIN uloží, a iOS zamčenou appku
      // mezitím může ukončit. Cesta rovnou do chatů by tiše nechala účet
      // bez PINu. Patří sem i starší instalace s PBKDF2
      // pin_hash (starý formát DEK nechránil).
      final storage = ref.read(storageProvider);
      await storage.unlockWithoutPin();
      if (!mounted) return;
      ref.invalidate(screenSecurityProvider);
      context.go('/pin-setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: SepotColors.ember),
      ),
    );
  }
}
