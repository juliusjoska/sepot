import 'package:flutter/material.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/message.dart';

/// Stav mé zprávy: ⏱ odesílá se · ✓ u relaye · ✓✓ doručeno · pilulka
/// přečteno · ✕ selhalo.
///
/// „Přečteno“ se liší TVAREM (plná pilulka), ne jen barvou — dřívější
/// modrošedé ✓✓ mělo na korálové bublině kontrast ~1,2 : 1 a nešlo ho
/// odlišit od „doručeno“.
class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.status,
    this.onEmber = false,
  });

  final MessageStatus status;

  /// Vykresluje se na korálové bublině (jinak na tmavém pozadí).
  final bool onEmber;

  @override
  Widget build(BuildContext context) {
    final soft = onEmber
        ? SepotColors.emberInk.withValues(alpha: 0.6)
        : SepotColors.textSecondary;
    return switch (status) {
      MessageStatus.sending => Icon(Icons.schedule_rounded, size: 14, color: soft),
      MessageStatus.sent => Icon(Icons.done_rounded, size: 15, color: soft),
      MessageStatus.delivered =>
        Icon(Icons.done_all_rounded, size: 15, color: soft),
      MessageStatus.read => Container(
          width: 21,
          height: 14,
          decoration: BoxDecoration(
            color: onEmber ? SepotColors.emberInk : SepotColors.ember,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            Icons.done_all_rounded,
            size: 11,
            color: onEmber ? SepotColors.ember : SepotColors.emberInk,
          ),
        ),
      MessageStatus.failed =>
        const Icon(Icons.error_outline_rounded, size: 15, color: SepotColors.error),
    };
  }
}
