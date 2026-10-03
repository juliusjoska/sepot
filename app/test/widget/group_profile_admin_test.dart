import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/features/profile/group_profile_screen.dart';
import 'package:sepot/features/profile/profile_widgets.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/identity_provider.dart';

/// Profil skupiny podle role: ne-správce nesmí vidět správcovské akce
/// (odebrat, udělat správcem), jen vysvětlení; správce je dostane v nabídce
/// člena.
class _FakeIdentityNotifier extends IdentityNotifier {
  _FakeIdentityNotifier(this._identity);
  final LocalIdentity _identity;

  @override
  Future<LocalIdentity?> build() async => _identity;
}

class _NoContacts extends ContactsNotifier {
  @override
  Future<List<Contact>> build() async => const [];
}

final _ja = LocalIdentity(
  displayName: 'Já',
  identityPrivateKey: Uint8List(32),
  identityPublicKey: Uint8List(33),
  createdAt: DateTime.utc(2026, 1, 1),
);

const _spravce = 'SPRAVCE0001';
const _clen = 'CLENKA0002';

Group _group({required bool jaSpravce, required bool vsichniV2}) => Group(
      id: 'g1',
      name: 'Chata v srpnu',
      memberIds: [_ja.id, _spravce, _clen],
      createdBy: _spravce,
      admins: [_spravce, if (jaSpravce) _ja.id],
      v2Members: vsichniV2 ? {_spravce, _clen} : {_spravce},
    );

Widget _app(Group group) => ProviderScope(
      overrides: [
        identityProvider.overrideWith(() => _FakeIdentityNotifier(_ja)),
        contactsProvider.overrideWith(_NoContacts.new),
        groupProvider.overrideWith((ref, id) async => group),
        conversationProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        locale: const Locale('cs'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupProfileScreen(groupId: group.id),
      ),
    );

Future<void> _pump(WidgetTester tester, Group group) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(group));
  await tester.pumpAndSettle();
}

ProfileAction _addAction(WidgetTester tester) => tester.widget<ProfileAction>(
    find.widgetWithText(ProfileAction, 'Přidat'));

void main() {
  testWidgets('ne-správce ve vynucené skupině: akce skryté, vysvětlení',
      (tester) async {
    await _pump(tester, _group(jaSpravce: false, vsichniV2: true));
    expect(tester.takeException(), isNull);

    expect(find.text('Správce'), findsOneWidget,
        reason: 'odznak u skutečného správce');
    expect(find.text('Jméno, členy a správce skupiny mění jen správci.'),
        findsOneWidget);
    expect(_addAction(tester).onTap, isNull,
        reason: 'přidávat lidi smí jen správce');
    expect(find.byIcon(Icons.edit_outlined), findsNothing,
        reason: 'přejmenování jen správcem');

    await tester.tap(find.textContaining('SEP-CLENKA'));
    await tester.pumpAndSettle();
    expect(find.text('Odebrat ze skupiny'), findsNothing);
    expect(find.text('Udělat správcem'), findsNothing);
  });

  testWidgets('ne-správce s v1 členem ve skupině smí přidávat, ne spravovat',
      (tester) async {
    await _pump(tester, _group(jaSpravce: false, vsichniV2: false));
    expect(_addAction(tester).onTap, isNotNull);
    expect(find.textContaining('Přidávat lidi zatím může každý'),
        findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('správce dostane nabídku člena s odebráním a rolí',
      (tester) async {
    await _pump(tester, _group(jaSpravce: true, vsichniV2: true));
    expect(find.text('Správce'), findsNWidgets(2));
    expect(_addAction(tester).onTap, isNotNull);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.textContaining('mění jen správci'), findsNothing);

    await tester.tap(find.textContaining('SEP-CLENKA'));
    await tester.pumpAndSettle();
    expect(find.text('Odebrat ze skupiny'), findsOneWidget);
    expect(find.text('Udělat správcem'), findsOneWidget);
  });
}
