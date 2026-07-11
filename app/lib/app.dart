import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/auth/change_pin_screen.dart';
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
import 'package:sepot/features/settings/settings_screen.dart';
import 'package:sepot/features/safety/report_screen.dart';
import 'package:sepot/features/qr_pairing/qr_share_screen.dart';
import 'package:sepot/features/qr_pairing/qr_scan_screen.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/locale_provider.dart';
import 'package:sepot/providers/settings_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

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

    return _AutoLockGate(
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
    );
  }
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        _naPozadiOd ??= DateTime.now();
      case AppLifecycleState.resumed:
        final od = _naPozadiOd;
        _naPozadiOd = null;
        if (od != null) unawaited(_zvazZamek(DateTime.now().difference(od)));
      case AppLifecycleState.inactive:
        break; // krátký přechod (notifikační lišta, hovor) — neřešit
    }
  }

  Future<void> _zvazZamek(Duration pryc) async {
    final storage = ref.read(storageProvider);
    if (!storage.isUnlocked) return;
    if (!await storage.hasPin()) return;

    final limit = await ref.read(autoLockProvider.future);
    if (limit <= 0 || pryc.inSeconds < limit) return;

    final kde = _router.state.uri.path;
    if (_bezZamku.contains(kde)) return;

    await ref.read(messagingServiceProvider).stop();
    ref.invalidate(messagingStartProvider);
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
      // Bez PINu — DEK přímo z OS keystore. Před-S9 instalace s PBKDF2
      // pin_hash jde nastavit PIN znovu (starý formát DEK nechránil).
      final storage = ref.read(storageProvider);
      final legacyPin = await storage.hasLegacyPin();
      await storage.unlockWithoutPin();
      if (mounted) context.go(legacyPin ? '/pin-setup' : '/chats');
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
