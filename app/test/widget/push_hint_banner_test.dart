import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/features/chat_list/push_hint_banner.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/providers/push_provider.dart';

/// Proužek říká uživateli, proč mu zprávy chodí až po otevření appky.
/// Musí se ukázat jen tehdy, když budíčky opravdu nefungují — jinak by
/// z informace o stavu byla otravná reklama.
Widget _app({required PushHealth health, required bool dismissed}) =>
    ProviderScope(
      overrides: [
        pushHealthProvider.overrideWith((ref) async => health),
        pushHintDismissedProvider.overrideWith((ref) async => dismissed),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('cs'),
        home: Scaffold(body: PushHintBanner()),
      ),
    );

void main() {
  testWidgets('push vypnutý → proužek se ukáže', (tester) async {
    await tester.pumpWidget(_app(health: PushHealth.off, dismissed: false));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets('registrace selhala → proužek se ukáže', (tester) async {
    await tester.pumpWidget(_app(health: PushHealth.failed, dismissed: false));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets('budíčky fungují → proužek mlčí', (tester) async {
    await tester.pumpWidget(_app(health: PushHealth.ok, dismissed: false));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
  });

  testWidgets('odmítnutý proužek se znovu neukáže', (tester) async {
    await tester.pumpWidget(_app(health: PushHealth.off, dismissed: true));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
  });
}
