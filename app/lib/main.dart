import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sepot/app.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/push/push_bootstrap.dart';

/// Proces nastartoval Android kvůli pushi, bez UI — `runApp` se nesmí zavolat
/// ani ze záchranného handleru.
bool _bezUi = false;

/// Reálné UI už běží. Pozdější async chyba ho nesmí přepsat chybovou obrazovkou.
bool _uiNabehla = false;

/// Start aplikace.
///
/// KRITICKÉ: mezi startem a prvním `runApp()` nesmí zůstat nechráněné `await`.
/// Když nativní init (libsignal) na zařízení selže, appka nesmí skončit němou
/// bílou obrazovkou — místo toho ukáže chybu, aby šla diagnostikovat.
void main(List<String> args) {
  runZonedGuarded(() async {
    // ÚPLNĚ PRVNÍ: kdyby cokoli níž (i ensureInitialized) hodilo, záchranný
    // handler musí vědět, že v headless push startu runApp volat nesmí.
    // Čteme z args nezávisle na PushBootstrap, aby to platilo i kdyby jeho
    // init selhal.
    _bezUi = args.contains('--unifiedpush-bg');

    WidgetsFlutterBinding.ensureInitialized();

    // Bez tohohle vykreslí release build chybu v build() jako němou šedou
    // plochu bez textu. V debug si necháme červenou obrazovku Flutteru.
    if (kReleaseMode) {
      ErrorWidget.builder =
          (details) => _ChybovaPlocha(detail: details.exceptionAsString());

      // network_security_config hlídá jen platformní HTTP stack, ne dart:io
      // sockety. `--dart-define=SEPOT_RELAY=http://…` by tedy v release
      // buildu tiše poslal provoz v plaintextu. Radši tvrdý pád.
      final relay = Uri.parse(AppConstants.relayUrl);
      if (relay.scheme != 'https' && relay.scheme != 'wss') {
        throw StateError(
          'Release build must talk https/wss, not "${relay.scheme}".',
        );
      }
    }

    // Chyby render pipeline zalogovat, ale NEshazovat kvůli nim běžící UI.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    // Formáty dat všech podporovaných jazyků — nekritické, appka poběží i bez nich
    for (final lang in const ['cs', 'en', 'de', 'ru', 'it']) {
      try {
        await initializeDateFormatting(lang);
      } catch (e, s) {
        debugPrint('initializeDateFormatting($lang) selhalo (nekritické): $e\n$s');
      }
    }

    // UnifiedPush callbacky VŽDY před runApp — Android budí zabitou appku
    // s `--unifiedpush-bg` bez UI (killed-state push budíček).
    try {
      await PushBootstrap.init(args);
    } catch (e, s) {
      // Push je nekritický: bez něj appka funguje, jen nechodí budíčky.
      debugPrint('PushBootstrap.init selhalo (nekritické): $e\n$s');
    }
    if (_bezUi || PushBootstrap.backgroundStart) {
      // Bez UI: onMessage jen ukáže generickou notifikaci (DB je zamčená,
      // dešifrovat nejde). Engine drží plugin, runApp se NEvolá.
      return;
    }

    // Nativní krypto backend (libsignal) — musí běžet dřív než cokoli,
    // co sahá na identitu. Nejčastější příčina bílé obrazovky na iOS.
    // Timeout kryje i zásek (init nevrátí) — nesmí viset donekonečna.
    try {
      await SepotCrypto.init().timeout(const Duration(seconds: 15));
    } catch (e, s) {
      debugPrint('SepotCrypto.init selhalo: $e\n$s');
      // Chybová cesta: keystore může být sám rozbitý, uloženou volbu jazyka
      // nečteme — jen systémový jazyk.
      runApp(_ChybaApp(
        titulek: l10nFor(null).errorCryptoInitTitle,
        detail: '$e',
      ));
      return;
    }

    // Zamkni orientaci na portrét
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Tmavý status bar
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B0C12),
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // Úložiště startuje ZAMČENÉ — odemyká se až v loading/pin-lock flow
    _spustUi(const ProviderScope(child: SepotApp()));
  }, (error, stack) {
    debugPrint('Neodchycená chyba při startu: $error\n$stack');
    // Headless push nemá UI, kam chybu vykreslit.
    if (_bezUi) return;
    // Appka už jede — pozdější async chyba ji nesmí shodit do chybovky.
    if (_uiNabehla) return;
    runApp(_ChybaApp(titulek: l10nFor(null).errorStartupTitle, detail: '$error'));
  });
}

void _spustUi(Widget app) {
  _uiNabehla = true;
  runApp(app);
}

/// Náhrada za výchozí `ErrorWidget` — ten v release módu kreslí prázdnou
/// šedou plochu bez jediného slova. Nesmí spoléhat na `MaterialApp` nad sebou.
class _ChybovaPlocha extends StatelessWidget {
  final String detail;

  const _ChybovaPlocha({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0B0C12),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10nFor(null).errorScreenNotRenderedTitle,
                    style: const TextStyle(
                      color: Color(0xFFF0EEE8),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    detail,
                    style: const TextStyle(
                      color: Color(0xFFF0795A),
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimální chybová obrazovka — bez závislosti na krypto/providerech,
/// aby se vykreslila i když selže start. Text jde označit a zkopírovat.
class _ChybaApp extends StatelessWidget {
  final String titulek;
  final String detail;

  const _ChybaApp({required this.titulek, required this.detail});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0C12),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Text(
                  titulek,
                  style: const TextStyle(
                    color: Color(0xFFF0EEE8),
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10nFor(null).errorStartupBody,
                  style: const TextStyle(color: Color(0xFF9AA0B5), fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12141D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF262A3A)),
                  ),
                  child: SelectableText(
                    detail,
                    style: const TextStyle(
                      color: Color(0xFFF0795A),
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l10nFor(null).errorContactFooter,
                  style: const TextStyle(color: Color(0xFF626880), fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
