/// Nahlášení zneužití — odesílá hlášení mimo relay, na web sepot.cz.
///
/// Proč ne přes relay: relay vidí jen opaque obálky a nemá čitelný kanál
/// k obsahu. Kdyby přijímal hlášení, získal by úložiště čitelných textů
/// vázaných na účty — přesně to, čemu se návrh vyhýbá.
///
/// Obsah zpráv se NIKDY neodesílá — ani automaticky, ani na vyžádání.
///
/// 🔴 Není to jen ohled na soukromí. Report systém, který provozovateli
/// doručí obsah nahlášené zprávy, znamená u dětské pornografie držení
/// materiálu = dokonaný § 192 trestního zákoníku, a to bez výjimky pro
/// „ověřování". UI proto uživatele výslovně od vkládání obsahu odrazuje
/// a u kategorie ohrožení dítěte ho posílá na STOPonline.cz / Policii ČR.
/// Hlášení nese jen metadata a slovní popis situace.
///
/// Splňuje: Google Play UGC policy (mechanismus nahlášení), Child Safety
/// Standards / CSAE (in-app nahlášení obav), Apple Guideline 1.2.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sepot/core/app_info.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/errors.dart';

/// Kategorie hlášení. `wire` hodnoty jsou součástí API — musí zůstat
/// v souladu s webovým endpointem, který hlášení přijímá. Popisky a
/// nápovědy kategorií skládá report_screen z lokalizace.
enum ReportCategory {
  childSafety('ohrozeni_ditete'),
  harassment('obtezovani'),
  spam('spam'),
  fraud('podvod'),
  other('jine');

  const ReportCategory(this.wire);

  final String wire;

  /// CSAE hlášení mají u nás přednost a jiný proces (viz sepot.cz/bezpecnost-deti).
  bool get isChildSafety => this == ReportCategory.childSafety;
}

class ReportService {
  const ReportService({this.endpoint = AppConstants.reportEndpoint});

  final String endpoint;

  static const Duration _timeout = Duration(seconds: 20);

  /// Odešle hlášení. Když se nepovede, vyhodí typovanou chybu
  /// ([ReportEmptyDescriptionError], [ReportConnectionError],
  /// [ReportRateLimitedError], [ReportServerError]) — UI ji překládá
  /// přes describeError.
  ///
  /// [reportedFingerprint] a [replyTo] jsou dobrovolné — bez nich je hlášení
  /// anonymní (server přesto uvidí IP adresu, na to upozorňuje UI).
  Future<void> submit({
    required ReportCategory category,
    required String description,
    String? reportedFingerprint,
    String? replyTo,
  }) async {
    final popis = description.trim();
    if (popis.isEmpty) {
      throw const ReportEmptyDescriptionError();
    }

    // S build číslem, ne jen „1.1.2" — jinak nejde poznat, ze kterého buildu
    // hlášení přišlo. Neznámou verzi radši vynechat než poslat vymyšlenou.
    final verze = AppInfo.versionWithBuild;

    final body = <String, dynamic>{
      'kategorie': category.wire,
      'popis': popis,
      'zdroj': 'app',
      'platforma': Platform.operatingSystem,
      'verze': ?verze,
      if (reportedFingerprint != null && reportedFingerprint.isNotEmpty)
        'nahlasenyOtisk': reportedFingerprint,
      if (replyTo != null && replyTo.trim().isNotEmpty)
        'kontakt': replyTo.trim(),
    };

    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(endpoint),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'X-Sepot-Client': 'app',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on Object {
      throw const ReportConnectionError();
    }

    if (res.statusCode == 200) return;
    if (res.statusCode == 429) {
      throw const ReportRateLimitedError();
    }
    throw ReportServerError(res.statusCode);
  }
}
