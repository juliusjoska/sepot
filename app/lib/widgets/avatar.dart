import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/messaging_provider.dart';

/// Avatar člověka: jeho profilová fotka, jinak iniciály na barevném tónu.
///
/// Tón se odvozuje ze [seed] (otisk klíče), ne ze jména — přejmenovaný
/// kontakt si barvu nechá a dva lidé se stejným jménem se od sebe liší.
/// Podle téhož otisku se hledá i fotka.
class SepotAvatar extends ConsumerWidget {
  final String name;
  final double size;

  /// Stabilní identifikátor pro tón (fingerprint). Bez něj se použije jméno.
  final String? seed;

  /// Zelený odznak ověřeného kontaktu v pravém dolním rohu.
  final bool verified;

  /// Kroužek kolem avataru (připnutý chat s nepřečtenou zprávou apod.).
  final Color? ring;

  const SepotAvatar({
    super.key,
    required this.name,
    this.size = 48,
    this.seed,
    this.verified = false,
    this.ring,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = SepotTint.of(seed ?? name);
    final badge = (size * 0.34).clamp(12.0, 30.0);
    final photo =
        seed == null ? null : ref.watch(avatarProvider(seed!)).valueOrNull;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();

    Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tint.background),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: photo != null
          ? Image.memory(
              photo,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Dekódovat jen v potřebné velikosti — seznam má desítky avatarů.
              cacheWidth: px,
              gaplessPlayback: true,
            )
          : Text(
              initialsOf(name),
              style: TextStyle(
                color: tint.ink,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    if (ring != null) {
      circle = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring!, width: 2),
        ),
        child: circle,
      );
    }
    if (!verified) return circle;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              color: SepotColors.sage,
              shape: BoxShape.circle,
              border: Border.all(color: SepotColors.background, width: 2),
            ),
            child: Icon(Icons.check_rounded,
                size: badge * 0.62, color: SepotColors.background),
          ),
        ),
      ],
    );
  }

  static final _leadingPunct = RegExp(r'^\p{P}', unicode: true);

  /// Iniciály pro avatar — veřejné, ať je sdílí i kolečka hlasujících apod.
  static String initialsOf(String name) {
    // Prázdné díly odfiltrovat — dvojitá mezera ve jméně nesmí shodit render.
    // Grafémy (characters), ne code units — jméno začínající emoji by se
    // jinak rozpůlilo na rozbitý surrogate.
    // Slova začínající interpunkcí přeskočit: přívlastek „(neznámý)“ u žádosti
    // o zprávu by jinak dal iniciály „M(“.
    final parts = name
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty && !_leadingPunct.hasMatch(p))
        .toList();
    if (parts.length >= 2) {
      return '${parts[0].characters.first}${parts[1].characters.first}'
          .toUpperCase();
    }
    if (parts.isEmpty) return '?';
    return parts[0].characters.take(2).toString().toUpperCase();
  }
}

/// Avatar skupiny: zaoblený čtverec s ikonou, ať se na první pohled liší
/// od člověka.
/// Avatar poznámek pro sebe — vlastní tvar i barva, ať se neplete s lidmi.
class NotesAvatar extends StatelessWidget {
  const NotesAvatar({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SepotColors.ember.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(Icons.bookmark_rounded,
          size: size * 0.5, color: SepotColors.ember),
    );
  }
}

class SepotGroupAvatar extends StatelessWidget {
  const SepotGroupAvatar({super.key, required this.seed, this.size = 48});

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = SepotTint.of(seed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.background,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(Icons.groups_rounded, size: size * 0.5, color: tint.ink),
    );
  }
}
