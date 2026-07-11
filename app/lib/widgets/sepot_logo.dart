import 'package:flutter/material.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';

/// Logo Šepot — brand mark „Š s tečkami" (nokturno-ikona-B2).
///
/// Používá STEJNÝ obrázek jako launcher ikona
/// (`assets/icon/icon-1024.png`), aby logo na ploše, na splash i uvnitř
/// appky bylo jednotné.
class SepotLogo extends StatelessWidget {
  final double size;
  final bool showText;

  const SepotLogo({
    super.key,
    this.size = 80,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Image.asset(
            'assets/icon/icon-1024.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 16),
          Text(
            context.l10n.commonAppName,
            style: TextStyle(
              fontFamily: kFontSans,
              fontSize: size * 0.35,
              fontWeight: FontWeight.w700,
              color: SepotColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.commonAppTagline,
            style: TextStyle(
              fontFamily: kFontSans,
              fontSize: size * 0.15,
              fontWeight: FontWeight.w400,
              color: SepotColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
