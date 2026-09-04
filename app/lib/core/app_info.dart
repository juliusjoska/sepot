/// Verze aplikace čtená z nainstalovaného balíčku.
///
/// Proč ne konstanta: verze se dřív psala ručně do `AppConstants` a musela se
/// hlídat proti `version:` v pubspec.yaml. Nehlídala se — produkční 1.1.2+22
/// posílala v hlášeních zneužití „1.1.0" a podle hlášení tak nešlo dohledat,
/// ze kterého buildu přišlo. `package_info_plus` čte `versionName` (Android)
/// / `CFBundleShortVersionString` (iOS), které Flutter generuje přímo
/// z pubspecu — rozejít se to už nemůže a ruční editace odpadá.
library;

import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  AppInfo._();

  /// Zástupný text, dokud verzi nezná (nebo když ji nešlo přečíst). Znak, ne
  /// slovo — appka běží v pěti jazycích a české „neznámá" by v nich čouhalo.
  static const String unknownVersion = '—';

  static PackageInfo? _info;

  /// Načte verzi z balíčku. Volat jednou při startu, před prvním `runApp`.
  static Future<void> init() async {
    _info = await PackageInfo.fromPlatform();
  }

  /// Verze pro uživatele: `1.1.2`.
  static String get version => _info?.version ?? unknownVersion;

  /// Verze pro diagnostiku: `1.1.2+22`. Build číslo je jediné, čím se hlášení
  /// zneužití přiřadí konkrétnímu buildu — do UI nepatří, do hlášení ano.
  /// `null`, dokud verzi nezná: hlášení pak pole vynechá, ať server dostane
  /// prázdno místo vymyšlené hodnoty.
  static String? get versionWithBuild {
    final info = _info;
    if (info == null) return null;
    // iOS bez vyplněného CFBundleVersion vrací v buildNumber rovnou verzi
    // (dokumentované chování balíčku) — nelepit „1.1.2+1.1.2".
    if (info.buildNumber.isEmpty || info.buildNumber == info.version) {
      return info.version;
    }
    return '${info.version}+${info.buildNumber}';
  }
}
