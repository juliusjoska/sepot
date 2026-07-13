import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/features/settings/settings_screen.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/identity_provider.dart';

/// Obrazovka Nastavení se musí vykreslit bez výjimky v build —
/// pád tady znamená pro uživatele „Tahle obrazovka se nevykreslila".
class _FakeIdentityNotifier extends IdentityNotifier {
  _FakeIdentityNotifier(this._identity);
  final LocalIdentity? _identity;

  @override
  Future<LocalIdentity?> build() async => _identity;
}

LocalIdentity _identityWithName(String name) => LocalIdentity(
      displayName: name,
      identityPrivateKey: Uint8List(32),
      identityPublicKey: Uint8List(33),
      createdAt: DateTime.utc(2026, 1, 1),
    );

Widget _app(LocalIdentity? identity) => ProviderScope(
      overrides: [
        identityProvider.overrideWith(() => _FakeIdentityNotifier(identity)),
      ],
      child: MaterialApp(
        locale: const Locale('cs'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    );

void main() {
  testWidgets('vykreslí se s běžnou identitou', (tester) async {
    await tester.pumpWidget(_app(_identityWithName('Alice')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('vykreslí se s prázdným jménem identity', (tester) async {
    await tester.pumpWidget(_app(_identityWithName('')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('vykreslí se bez identity', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
