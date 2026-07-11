import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';

export 'package:sepot/l10n/generated/app_localizations.dart';

/// Zkratka pro přístup k lokalizovaným textům: `context.l10n.klic`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Lokalizace mimo widget tree (notifikace, headless push start).
///
/// Preferuje ruční volbu jazyka (`override`, typicky
/// `LocaleNotifier.readStored()`), jinak jazyk systému; nepodporovaný
/// jazyk spadne na angličtinu — stejné pořadí jako `supportedLocales`.
AppLocalizations l10nFor(Locale? override) {
  final locale = override ?? PlatformDispatcher.instance.locale;
  final lang = Locale(locale.languageCode);
  final supported = AppLocalizations.delegate.isSupported(lang);
  return lookupAppLocalizations(supported ? lang : const Locale('en'));
}
