import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sepot/core/theme/app_theme.dart';

/// Průsvitná plocha s rozmazáním obsahu pod sebou (hlavička chatu, pole pro
/// psaní, spodní navigace). Blur je drahý, proto jen na pár plovoucích
/// lištách, nikdy na položkách seznamu.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
    this.border = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: SepotColors.glass,
            borderRadius: borderRadius,
            border: border
                ? Border.all(color: SepotColors.glassBorder)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Tečková tapeta pod konverzací — dává průsvitným lištám co rozmazat
/// a chatu hloubku, aniž by rušila text.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DotsPainter(),
      isComplex: true,
      willChange: false,
      child: child,
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  static const _spacing = 18.0;
  static const _radius = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = SepotColors.background);
    final dot = Paint()..color = SepotColors.mist.withValues(alpha: 0.11);
    for (var y = _spacing / 2; y < size.height; y += _spacing) {
      for (var x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) => false;
}
