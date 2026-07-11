/// Numerická klávesnice pro PIN + řádek teček.
///
/// Vytaženo z `pin_setup_screen`, aby ji mohla použít i změna PINu.
/// Systémovou klávesnici záměrně nepoužíváme — nechceme, aby PIN prošel
/// IME (predikce, schránka, klávesnice třetích stran).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sepot/core/theme/app_theme.dart';

class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, this.length = 6});

  final int filled;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final on = i < filled;
        return Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? SepotColors.ember : SepotColors.border,
            border: Border.all(
              color: on ? SepotColors.ember : SepotColors.border,
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}

class PinKeypad extends StatelessWidget {
  const PinKeypad({super.key, required this.onKey, this.enabled = true});

  /// Dostane číslici '0'–'9' nebo 'DEL'.
  final void Function(String key) onKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'DEL'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row
                  .map((k) => k.isEmpty
                      ? const SizedBox(width: 88, height: 64)
                      : _klavesa(k))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _klavesa(String key) {
    final delete = key == 'DEL';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onKey(key);
              }
            : null,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: delete ? Colors.transparent : SepotColors.surfaceVariant,
            border: delete ? null : Border.all(color: SepotColors.border),
          ),
          child: Center(
            child: delete
                ? const Icon(Icons.backspace_outlined,
                    color: SepotColors.textSecondary, size: 24)
                : Text(
                    key,
                    style: const TextStyle(
                      fontFamily: kFontSans,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: SepotColors.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
