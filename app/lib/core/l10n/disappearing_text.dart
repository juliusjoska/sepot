import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/message.dart';

/// Popisky voleb mizících zpráv (sekundy → text); -1 = vypnuto. Hodnoty
/// musí sedět s AppConstants.disappearingChoices.
List<(int, String)> disappearingOptions(AppLocalizations l10n) => [
      (-1, l10n.commonOff),
      (30, l10n.chatDisappearing30s),
      (300, l10n.chatDisappearing5m),
      (3600, l10n.chatDisappearing1h),
      (86400, l10n.chatDisappearing1d),
      (604800, l10n.chatDisappearing1w),
    ];

/// Text aktuálního nastavení mizících zpráv („1 týden“ / „Vypnuto“).
String disappearingLabel(AppLocalizations l10n, int? seconds) {
  final options = disappearingOptions(l10n);
  return options.where((o) => o.$1 == (seconds ?? -1)).firstOrNull?.$2 ??
      l10n.commonOff;
}

/// Sekundy z oznámení o změně časovače; null = vypnuto.
int? timerNoticeSeconds(Message notice) {
  final seconds = int.tryParse(notice.content ?? '') ?? 0;
  return seconds > 0 ? seconds : null;
}
