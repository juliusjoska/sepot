/// Změna časovače mizících zpráv uprostřed konverzace. Úmyslně tlumená —
/// je to informace, ne bezpečnostní varování.
library;

import 'package:flutter/material.dart';
import 'package:sepot/core/l10n/disappearing_text.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';

class TimerNoticeRow extends StatelessWidget {
  const TimerNoticeRow({
    super.key,
    required this.seconds,
    required this.changedBy,
    required this.byMe,
  });

  /// Nový časovač; null = vypnuto.
  final int? seconds;
  final String changedBy;
  final bool byMe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final duration = disappearingLabel(l10n, seconds);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined,
              size: 15, color: SepotColors.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              byMe
                  ? l10n.noticeTimerChangedByMe(duration)
                  : l10n.noticeTimerChanged(changedBy, duration),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: SepotColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
