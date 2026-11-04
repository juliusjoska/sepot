import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/widgets/avatar.dart';
import 'package:sepot/widgets/glass.dart';

/// Banner nahoře pro zprávu, která přišla do jiného chatu, než je otevřený.
///
/// Systémová notifikace v popředí nepatří (člověk se dívá do appky) a snack
/// bar dole by překryl pole pro psaní. Jen jeden banner naráz: další zpráva
/// nahradí předchozí, aby se při živé skupině nevršily přes celou obrazovku.
class IncomingMessageBanner {
  IncomingMessageBanner._();

  static const _zobrazeno = Duration(seconds: 4);

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    OverlayState overlay, {
    required String text,
    required String avatarName,
    required String? avatarSeed,
    required VoidCallback onTap,
  }) {
    hide();
    // vibrate(), ne lehký impact: lehké ťuknutí při psaní nikdo nepozná.
    HapticFeedback.vibrate();
    final entry = OverlayEntry(
      builder: (context) => _Banner(
        text: text,
        avatarName: avatarName,
        avatarSeed: avatarSeed,
        onTap: () {
          hide();
          onTap();
        },
        onDismiss: hide,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(_zobrazeno, hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.avatarName,
    required this.avatarSeed,
    required this.onTap,
    required this.onDismiss,
  });

  final String text;
  final String avatarName;
  final String? avatarSeed;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final banner = Dismissible(
      key: const ValueKey('incoming-message-banner'),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismiss(),
      child: Semantics(
        liveRegion: true,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  SepotAvatar(name: avatarName, seed: avatarSeed, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SepotColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: reduceMotion
              ? banner
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: -1, end: 0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, posun, child) => FractionalTranslation(
                    translation: Offset(0, posun),
                    child: child,
                  ),
                  child: banner,
                ),
        ),
      ),
    );
  }
}
