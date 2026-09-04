import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sepot/core/app_info.dart';

/// Verzi appky nesmí nikdo psát ručně. Regrese: konstanta zůstala po releasu
/// na „1.1.0", takže všechna hlášení zneužití z produkční 1.1.2+22 byla
/// označená špatnou verzí a nešlo podle nich dohledat build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PackageInfo mock({required String version, required String buildNumber}) =>
      PackageInfo(
        appName: 'Šepot',
        packageName: 'cz.sepot.app',
        version: version,
        buildNumber: buildNumber,
        buildSignature: '',
      );

  void nastavBalicek(PackageInfo info) => PackageInfo.setMockInitialValues(
        appName: info.appName,
        packageName: info.packageName,
        version: info.version,
        buildNumber: info.buildNumber,
        buildSignature: info.buildSignature,
      );

  // Pořadí testů záleží: PackageInfo si první načtení nacachuje napořád,
  // takže stav „ještě se nenačetlo" jde ověřit jen před prvním init().
  test('před inicializací nepředstírá verzi', () {
    expect(AppInfo.version, AppInfo.unknownVersion);
    expect(AppInfo.versionWithBuild, isNull);
  });

  test('hlášení nese verzi včetně build čísla', () async {
    nastavBalicek(mock(version: '1.1.2', buildNumber: '22'));
    await AppInfo.init();

    expect(AppInfo.version, '1.1.2');
    expect(AppInfo.versionWithBuild, '1.1.2+22');
  });

  test('iOS bez CFBundleVersion nezdvojí verzi', () async {
    nastavBalicek(mock(version: '1.1.2', buildNumber: '1.1.2'));
    await AppInfo.init();

    expect(AppInfo.versionWithBuild, '1.1.2');
  });

  test('prázdné build číslo → jen verze', () async {
    nastavBalicek(mock(version: '2.0.0', buildNumber: ''));
    await AppInfo.init();

    expect(AppInfo.versionWithBuild, '2.0.0');
  });
}
