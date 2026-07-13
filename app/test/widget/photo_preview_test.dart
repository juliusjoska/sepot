import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sepot/features/conversation/photo_preview_screen.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';

/// Náhled fotky před odesláním: nic neodchází bez potvrzení, úpravy
/// (rotace) se propíšou do odeslaných bajtů, popisek do výsledku.
///
/// Dekódování obrázku a render úprav jsou reálné async operace engine,
/// proto testy běží v `tester.runAsync`.
Uint8List _testPng({int width = 8, int height = 4}) =>
    Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));

void main() {
  Future<Future<PhotoPreviewResult?>> openPreview(
    WidgetTester tester,
    Uint8List bytes,
  ) async {
    late Future<PhotoPreviewResult?> pushed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('cs'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              pushed = Navigator.of(context).push<PhotoPreviewResult>(
                MaterialPageRoute(
                  builder: (_) => PhotoPreviewScreen(
                    bytes: bytes,
                    fileName: 'test.png',
                    mime: 'image/png',
                  ),
                ),
              );
            },
            child: const Text('otevřít'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('otevřít'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Reálný async decode obrázku — počkat, až zmizí spinner.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'obrázek se nedekódoval',
    );
    return pushed;
  }

  Future<PhotoPreviewResult?> settleResult(
    WidgetTester tester,
    Future<PhotoPreviewResult?> pushed,
  ) async {
    // Render + pop jsou reálné async operace — pumpovat, dokud route žije.
    // pump s duration posouvá i pop animaci, jinak by route nikdy nezmizel.
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(PhotoPreviewScreen).evaluate().isEmpty) break;
    }
    return pushed;
  }

  testWidgets('zrušení nic nepošle', (tester) async {
    await tester.runAsync(() async {
      final pushed = await openPreview(tester, _testPng());
      await tester.tap(find.byIcon(Icons.close));
      final result = await settleResult(tester, pushed);
      expect(find.byType(PhotoPreviewScreen), findsNothing);
      expect(result, isNull);
    });
  });

  testWidgets('odeslání bez úprav vrací původní bajty + popisek', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = _testPng();
      final pushed = await openPreview(tester, bytes);

      await tester.enterText(find.byType(TextField), 'ahoj z testu');
      await tester.tap(find.byTooltip('Poslat'));
      final result = await settleResult(tester, pushed);

      expect(result, isNotNull);
      expect(result!.bytes, same(bytes)); // beze změn = žádný re-encode tady
      expect(result.caption, 'ahoj z testu');
      expect(result.fileName, 'test.png');
    });
  });

  testWidgets('rotace se propíše do odeslaných bajtů', (tester) async {
    await tester.runAsync(() async {
      final pushed = await openPreview(tester, _testPng(width: 8, height: 4));

      await tester.tap(find.byTooltip('Otočit'));
      await tester.pump();
      await tester.tap(find.byTooltip('Poslat'));
      final result = await settleResult(tester, pushed);

      expect(result, isNotNull);
      final decoded = img.decodeImage(result!.bytes)!;
      expect(decoded.width, 4); // 8×4 otočeno o 90° → 4×8
      expect(decoded.height, 8);
      expect(result.caption, isNull);
    });
  });
}
