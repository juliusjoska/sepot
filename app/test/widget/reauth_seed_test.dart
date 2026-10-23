import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/features/auth/reauth.dart';
import 'package:sepot/features/settings/settings_screen.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/pin_keypad.dart';

/// 24 slov z odemčené appky jen po čerstvém PINu nebo biometrii; v nátlakové
/// relaci vůbec. Úložiště je podvržené — Argon2id a keystore testuje
/// `test/storage/verify_pin_test.dart`.
class _FakeStorage extends SecureStorageService {
  _FakeStorage({this.pin = true, this.bio = false, this.decoy = false});

  final bool pin;
  final bool bio;
  final bool decoy;
  int seedReads = 0;

  static const correctPin = '123456';
  static final words = List.generate(24, (i) => 'slovo$i');

  @override
  bool get isDecoyMode => decoy;

  @override
  Future<bool> hasPin() async => pin;

  @override
  Future<bool> hasDecoyPin() async => false;

  @override
  Future<bool> isBiometricsEnabled() async => bio;

  @override
  Future<Duration?> pinLockRemaining() async => null;

  @override
  Future<bool> verifyPin(String pin) async => pin == correctPin;

  @override
  Future<List<String>?> loadSeedPhrase() async {
    seedReads++;
    return decoy ? null : words;
  }
}

class _FakeIdentityNotifier extends IdentityNotifier {
  @override
  Future<LocalIdentity?> build() async => LocalIdentity(
        displayName: 'Alice',
        identityPrivateKey: Uint8List(32),
        identityPublicKey: Uint8List(33),
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<_FakeStorage> pump(
    WidgetTester tester, {
    bool pin = true,
    bool bio = false,
    bool bioResult = false,
    bool decoy = false,
  }) async {
    final storage = _FakeStorage(pin: pin, bio: bio, decoy: decoy);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        identityProvider.overrideWith(_FakeIdentityNotifier.new),
        biometricPromptProvider.overrideWithValue((_) async => bioResult),
      ],
      child: MaterialApp(
        locale: const Locale('cs'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    return storage;
  }

  Future<void> openSeed(WidgetTester tester) async {
    final tile = find.text('Zálohovací fráze');
    await tester.scrollUntilVisible(tile, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.descendant(
          of: find.byType(PinKeypad), matching: find.text(d)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  final firstWord = find.textContaining('slovo0');

  testWidgets('fráze se bez PINu neukáže ani nenačte', (tester) async {
    final storage = await pump(tester);
    await openSeed(tester);
    expect(find.text('Potvrď, že jsi to ty'), findsOneWidget);
    expect(firstWord, findsNothing);
    expect(storage.seedReads, 0, reason: 'z keystore až po ověření');

    await tester.tap(find.text('Zrušit'));
    await tester.pumpAndSettle();
    expect(firstWord, findsNothing);
    expect(storage.seedReads, 0);
  });

  testWidgets('špatný PIN frázi neukáže', (tester) async {
    final storage = await pump(tester);
    await openSeed(tester);
    await typePin(tester, '000000');
    expect(find.text('Špatný PIN.'), findsOneWidget);
    expect(firstWord, findsNothing);
    expect(storage.seedReads, 0);
  });

  testWidgets('správný PIN frázi ukáže', (tester) async {
    final storage = await pump(tester);
    await openSeed(tester);
    await typePin(tester, _FakeStorage.correctPin);
    expect(firstWord, findsOneWidget);
    expect(storage.seedReads, 1);
  });

  testWidgets('každé zobrazení chce PIN znovu', (tester) async {
    await pump(tester);
    await openSeed(tester);
    await typePin(tester, _FakeStorage.correctPin);
    await tester.tap(find.text('Zavřít'));
    await tester.pumpAndSettle();

    await openSeed(tester);
    expect(find.text('Potvrď, že jsi to ty'), findsOneWidget);
    expect(firstWord, findsNothing);
  });

  testWidgets('úspěšná biometrie stačí', (tester) async {
    await pump(tester, bio: true, bioResult: true);
    await openSeed(tester);
    expect(firstWord, findsOneWidget);
  });

  testWidgets('zrušená biometrie spadne na PIN', (tester) async {
    await pump(tester, bio: true, bioResult: false);
    await openSeed(tester);
    expect(find.text('Potvrď, že jsi to ty'), findsOneWidget);
    expect(firstWord, findsNothing);
  });

  testWidgets('bez nastaveného PINu fráze nejde', (tester) async {
    final storage = await pump(tester, pin: false);
    await openSeed(tester);
    expect(find.textContaining('Nejdřív si ho nastav'), findsOneWidget);
    expect(firstWord, findsNothing);
    expect(storage.seedReads, 0);
  });

  testWidgets('nátlaková relace frázi vůbec nenabízí', (tester) async {
    await pump(tester, decoy: true);
    expect(find.text('Zálohovací fráze', skipOffstage: false), findsNothing);
  });

  testWidgets('smazání účtu bez PINu neproběhne', (tester) async {
    await pump(tester);
    final button = find.text('Smazat všechna data');
    await tester.scrollUntilVisible(button, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(find.text('Potvrď, že jsi to ty'), findsOneWidget);
    await typePin(tester, '999999');
    expect(find.text('Špatný PIN.'), findsOneWidget);
  });
}
