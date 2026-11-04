import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/features/chat_list/chat_list_tile.dart';
import 'package:sepot/features/conversation/widgets/timer_notice_row.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/message.dart';

/// Oznámení o změně časovače musí říct kdo a na kolik — jinak člen skupiny
/// neví, proč mu zprávy začaly mizet.
Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('cs'),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('cizí změna: jméno a doba', (tester) async {
    await tester.pumpWidget(_app(const TimerNoticeRow(
        seconds: 3600, changedBy: 'Alice', byMe: false)));
    expect(find.textContaining('Alice změnil(a) mizení zpráv'), findsOneWidget);
    expect(find.textContaining('1 hodina'), findsOneWidget);
  });

  testWidgets('vlastní změna na vypnuto', (tester) async {
    await tester.pumpWidget(_app(
        const TimerNoticeRow(seconds: null, changedBy: '', byMe: true)));
    expect(find.text('Změnil(a) jsi mizení zpráv: Vypnuto'), findsOneWidget);
  });

  test('náhled v seznamu chatů ukáže novou dobu', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('cs'));
    final notice = Message.notice(
        contactId: 'a',
        myId: 'b',
        notice: MessageNotice.timerChanged,
        content: '604800');
    final preview = ChatListTile.previewOf(l10n, notice);
    expect(preview.icon, Icons.timer_outlined);
    expect(preview.text, l10n.chatDisappearingEnabled(l10n.chatDisappearing1w));
  });
}
