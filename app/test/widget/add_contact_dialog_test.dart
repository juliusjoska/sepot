import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/features/contacts/contacts_screen.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/providers/contacts_provider.dart';

/// Lidé opisují Šepot ID ze sdílecí obrazovky jako „kód“ a čekají, že podle
/// něj přidají kontakt. Dialog jim to musí vysvětlit tam, kam se dívají.
class _PrazdneKontakty extends ContactsNotifier {
  @override
  Future<List<Contact>> build() async => const [];
}

Widget _app() => ProviderScope(
  overrides: [contactsProvider.overrideWith(_PrazdneKontakty.new)],
  child: MaterialApp(
    locale: const Locale('cs'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ContactsScreen(),
  ),
);

Future<void> _otevritDialogAVlozit(WidgetTester tester, String text) async {
  await tester.pumpWidget(_app());
  await tester.pump();
  await tester.tap(find.byIcon(Icons.person_add_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.tap(find.text('Přidat'));
  await tester.pump();
}

void main() {
  testWidgets('opsané Šepot ID vysvětlí přímo v dialogu', (tester) async {
    await _otevritDialogAVlozit(tester, 'SEP-7KQ2 M9XA4F');

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Tohle je Šepot ID'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('nesmysl dostane obecnou hlášku, ne tu o Šepot ID', (
    tester,
  ) async {
    await _otevritDialogAVlozit(tester, 'ahoj');

    expect(find.textContaining('Tohle je Šepot ID'), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('dialog nabízí naskenovat QR kód', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.person_add_outlined));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Skenovat QR kód'),
      ),
      findsOneWidget,
    );
  });
}
