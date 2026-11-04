/// Žádost o hodnocení v obchodě.
///
/// Hodnocení rozhoduje, kolik lidí ze stránky v obchodě appku opravdu stáhne,
/// a dlouho po vydání ho Šepot neměl žádné. Ptáme se ale jen toho, kdo appku
/// skutečně používá: kdo ještě nemá s kým psát, dává nízké hvězdičky
/// prázdnému messengeru, ne Šepotu.
///
/// iOS: jen systémový dialog StoreKitu. Vlastní výzvy k hodnocení Apple
/// nepouští (5.6.1) a systém sám hlídá strop 3× ročně, takže dialog se
/// nemusí ukázat ani po zavolání.
/// Android: vlastní dotaz s odkazem do Google Play. Play In-App Review by do
/// appky zatáhl proprietární knihovnu Googlu (Play Core), což u soukromého
/// messengeru s buildem pro F-Droid nechceme.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ReviewPrompt {
  ReviewPrompt({
    required Future<int?> Function(String key) read,
    required Future<void> Function(String key, int value) write,
    bool Function()? enabled,
    DateTime Function()? clock,
  })  : _read = read,
        _write = write,
        _enabled = enabled ?? _always,
        _clock = clock ?? DateTime.now;

  final Future<int?> Function(String key) _read;
  final Future<void> Function(String key, int value) _write;
  final bool Function() _enabled;
  final DateTime Function() _clock;

  static const sentCountKey = 'review_sent_count';
  static const firstUseKey = 'review_first_use_ms';
  static const lastAskedKey = 'review_last_asked_ms';
  static const askedCountKey = 'review_asked_count';

  /// Kolik vlastních zpráv musí člověk poslat, než se zeptáme — pár
  /// zkušebních zpráv po instalaci ještě není používání.
  static const minSentMessages = 20;

  /// Odstup od prvního spuštění, ať se neptáme v den instalace.
  static const minDaysInUse = 3;

  /// Odstup mezi dotazy, když člověk řekne „Teď ne“.
  static const daysBetweenAsks = 120;

  /// Víc než třikrát už je to otravování (stejný strop má i iOS za rok).
  static const maxAsks = 3;

  static const _channel = MethodChannel('cz.sepot.sepot/review');

  Future<void> noteMessageSent() async {
    if (!_enabled()) return;
    final sent = await _read(sentCountKey) ?? 0;
    // Strop jen proto, aby se číslo zbytečně nezvětšovalo; víc nepotřebujeme.
    if (sent < minSentMessages) await _write(sentCountKey, sent + 1);
  }

  Future<bool> shouldAsk() async {
    if (!_enabled()) return false;
    final now = _clock();
    final firstUse = await _read(firstUseKey);
    if (firstUse == null) {
      await _write(firstUseKey, now.millisecondsSinceEpoch);
      return false;
    }
    if (now.difference(_fromMs(firstUse)).inDays < minDaysInUse) return false;
    if ((await _read(sentCountKey) ?? 0) < minSentMessages) return false;
    if ((await _read(askedCountKey) ?? 0) >= maxAsks) return false;
    final lastAsked = await _read(lastAskedKey);
    return lastAsked == null ||
        now.difference(_fromMs(lastAsked)).inDays >= daysBetweenAsks;
  }

  Future<void> markAsked() async {
    await _write(lastAskedKey, _clock().millisecondsSinceEpoch);
    await _write(askedCountKey, (await _read(askedCountKey) ?? 0) + 1);
  }

  /// Zeptá se, pokud je na to čas. Volat na klidném místě (seznam chatů),
  /// ne uprostřed psaní.
  Future<void> maybeAsk(BuildContext context) async {
    if (!await shouldAsk()) return;
    if (!context.mounted) return;
    await markAsked();
    if (Platform.isIOS) {
      await _channel.invokeMethod<void>('requestReview');
    } else if (Platform.isAndroid && context.mounted) {
      await _askOnAndroid(context);
    }
  }

  Future<void> _askOnAndroid(BuildContext context) async {
    final l10n = context.l10n;
    final rate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.reviewAskTitle),
        content: Text(l10n.reviewAskBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.reviewAskLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.reviewAskRate),
          ),
        ],
      ),
    );
    if (rate != true) return;
    // market:// otevře rovnou appku Obchod Play; bez ní (telefon bez Googlu)
    // zbývá webová stránka.
    final opened = await launchUrl(Uri.parse(AppConstants.playStoreMarketUrl),
        mode: LaunchMode.externalApplication);
    if (!opened) {
      await launchUrl(Uri.parse(AppConstants.playStoreWebUrl),
          mode: LaunchMode.externalApplication);
    }
  }

  static bool _always() => true;

  static DateTime _fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
}

final reviewPromptProvider = Provider<ReviewPrompt>((ref) {
  final storage = ref.read(storageProvider);
  return ReviewPrompt(
    read: storage.getSetting<int>,
    write: storage.setSetting,
    // Nátlakový režim předstírá jiný, nepoužívaný účet — dotaz na hodnocení
    // by tam prozradil, že se appka ve skutečnosti používá. Zjišťuje se při
    // každém volání, protože režim se mění odemčením jiným PINem.
    enabled: () => !storage.isDecoyMode,
  );
});
