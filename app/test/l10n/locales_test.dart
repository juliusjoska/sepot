import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/features/settings/language_settings_tile.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';

/// Všech 5 podporovaných jazyků se musí načíst a mít neprázdné texty.
/// Chybějící překlad = gen-l10n doplní text šablony (cs) — to hlídá
/// porovnání ARB souborů níže, ne runtime.
void main() {
  const locales = [
    Locale('cs'),
    Locale('en'),
    Locale('de'),
    Locale('ru'),
    Locale('it'),
  ];

  test('podporované locale sedí s MaterialApp seznamem', () {
    expect(
      AppLocalizations.supportedLocales.toSet(),
      locales.toSet(),
    );
  });

  for (final locale in locales) {
    test('AppLocalizations se načte pro $locale', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.appTitle, 'Šepot');
      expect(l10n.settingsLanguage, isNotEmpty);
      expect(l10n.languageSystem, isNotEmpty);
    });
  }

  // Wiring delegátů ve widget tree: skutečný widget se musí vykreslit
  // v jazyce vynuceného locale (ne jen delegate.load v izolaci).
  const tileTitles = {
    'cs': 'Jazyk aplikace',
    'en': 'App language',
    'de': 'App-Sprache',
    'ru': 'Язык приложения',
    'it': "Lingua dell'app",
  };

  for (final entry in tileTitles.entries) {
    testWidgets('LanguageSettingsTile se vykreslí v ${entry.key}',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: Locale(entry.key),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: LanguageSettingsTile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  test('žádný jazyk nemá chybějící klíče proti šabloně (cs)', () {
    final dir = Directory('lib/l10n');
    final template = json.decode(
      File('${dir.path}/app_cs.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final templateKeys =
        template.keys.where((k) => !k.startsWith('@')).toSet();

    for (final code in ['en', 'de', 'ru', 'it']) {
      final other = json.decode(
        File('${dir.path}/app_$code.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final keys = other.keys.where((k) => !k.startsWith('@')).toSet();
      expect(
        templateKeys.difference(keys),
        isEmpty,
        reason: 'app_$code.arb nemá všechny klíče šablony',
      );
      expect(
        keys.difference(templateKeys),
        isEmpty,
        reason: 'app_$code.arb má klíče navíc oproti šabloně',
      );
    }
  });
}
