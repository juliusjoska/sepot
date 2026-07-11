import 'package:flutter/material.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';

/// Badge indikující E2E šifrování
class E2EBadge extends StatelessWidget {
  final bool compact;

  const E2EBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, size: 12, color: SepotColors.ember),
          const SizedBox(width: 4),
          Text(
            context.l10n.commonE2eBadgeCompact,
            style: const TextStyle(
              fontSize: 10,
              color: SepotColors.ember,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SepotColors.ember.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SepotColors.ember.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, size: 14, color: SepotColors.ember),
          const SizedBox(width: 4),
          Text(
            context.l10n.commonE2eBadgeFull,
            style: const TextStyle(
              fontSize: 11,
              color: SepotColors.ember,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
