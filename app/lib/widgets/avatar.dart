import 'package:flutter/material.dart';
import 'package:sepot/core/theme/app_theme.dart';

/// Generovaný avatar z iniciál
class SepotAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool isOnline;

  const SepotAvatar({
    super.key,
    required this.name,
    this.size = 48,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(name);
    final color = _colorFromName(name);

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Nokturno: tichý tmavý podklad, barva jen v iniciálách
            color: SepotColors.surfaceVariant,
            border: Border.all(color: SepotColors.border),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                color: color,
                fontSize: size * 0.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: SepotColors.success,
                shape: BoxShape.circle,
                border: Border.all(
                  color: SepotColors.background,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _getInitials(String name) {
    // Prázdné díly odfiltrovat — dvojitá mezera ve jméně nesmí shodit render.
    // Grafémy (characters), ne code units — jméno začínající emoji by se
    // jinak rozpůlilo na rozbitý surrogate.
    final parts =
        name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0].characters.first}${parts[1].characters.first}'
          .toUpperCase();
    }
    if (parts.isEmpty) return '?';
    return parts[0].characters.take(2).toString().toUpperCase();
  }

  Color _colorFromName(String name) {
    // Jen tlumené tóny palety — žádné syté cizí barvy
    final colors = [
      SepotColors.ember,
      SepotColors.mist,
      SepotColors.sage,
      SepotColors.warning,
      SepotColors.textSecondary,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}
