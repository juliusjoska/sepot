import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/features/qr_pairing/qr_share_screen.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/identity.dart';

void main() {
  testWidgets('během proof-of-work ukáže „Zabezpečuji registraci…“ a postup',
      (tester) async {
    final progress = ValueNotifier<double?>(null);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('cs'),
      home: Scaffold(
        body: QrConnectingPlaceholder(
          identity: LocalIdentity(
            displayName: 'Alice',
            identityPrivateKey: Uint8List(32),
            identityPublicKey: Uint8List(33),
            createdAt: DateTime.utc(2026, 1, 1),
          ),
          powProgress: progress,
        ),
      ),
    ));
    CircularProgressIndicator indicator() =>
        tester.widget(find.byType(CircularProgressIndicator));

    expect(find.text('Připojuji k relayi…'), findsOneWidget);
    expect(indicator().value, isNull);

    progress.value = 0.4;
    await tester.pump();
    expect(find.text('Zabezpečuji registraci…'), findsOneWidget);
    expect(find.textContaining('falešných účtů'), findsOneWidget);
    expect(indicator().value, 0.4);

    progress.value = null;
    await tester.pump();
    expect(find.text('Připojuji k relayi…'), findsOneWidget);
  });
}
