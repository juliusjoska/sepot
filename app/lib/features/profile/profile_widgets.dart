/// Stavební prvky profilu kontaktu a skupiny — ať oba vypadají a chovají
/// se stejně.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/conversation/image_viewer_screen.dart';
import 'package:sepot/models/message.dart';

/// Výsledek profilu otevřeného z chatu: co má chat udělat po návratu.
enum ProfileResult { openSearch }

/// Horní část profilu: zpět, velký avatar, jméno a řádky pod ním.
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.avatar,
    required this.title,
    required this.lines,
    this.onTitleTap,
  });

  final Widget avatar;
  final String title;
  final List<Widget> lines;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SepotColors.hero,
      padding: EdgeInsets.fromLTRB(
          4, MediaQuery.paddingOf(context).top + 4, 4, 22),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          avatar,
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTitleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (onTitleTap != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined,
                        size: 18, color: SepotColors.textSecondary),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(padding: const EdgeInsets.only(top: 4), child: line),
        ],
      ),
    );
  }
}

/// Čtveřice rychlých akcí pod hlavičkou profilu.
class ProfileAction extends StatelessWidget {
  const ProfileAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? SepotColors.ember : SepotColors.textPrimary;
    return Expanded(
      child: Material(
        color: SepotColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            height: 70,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zaoblená karta se sekcí profilu; řádky odděluje tenká linka.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.children, this.title, this.trailing});

  final String? title;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SepotColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  if (trailing != null)
                    Text(trailing!,
                        style: const TextStyle(
                            fontSize: 13, color: SepotColors.textSecondary)),
                ],
              ),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && title == null)
              const Divider(height: 1, indent: 16, color: SepotColors.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Řádek karty: popisek vlevo, hodnota vpravo, volitelně šipka.
class ProfileRow extends StatelessWidget {
  const ProfileRow({
    super.key,
    required this.label,
    this.value,
    this.leading,
    this.subtitle,
    this.onTap,
    this.danger = false,
    this.trailing,
  });

  final String label;
  final String? value;
  final Widget? leading;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: danger ? FontWeight.w600 : FontWeight.w400,
                          color: danger
                              ? SepotColors.error
                              : SepotColors.textPrimary)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 13, color: SepotColors.textSecondary)),
                    ),
                ],
              ),
            ),
            if (value != null)
              Text(value!,
                  style: const TextStyle(
                      fontSize: 14, color: SepotColors.textSecondary)),
            ?trailing,
            if (onTap != null && !danger && trailing == null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: SepotColors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mřížka sdílených fotek (inline náhledy z E2E zpráv, nic se nestahuje).
class SharedMediaCard extends StatelessWidget {
  const SharedMediaCard({super.key, required this.messages});

  /// Všechny zprávy konverzace — fotky si vybere sama.
  final List<Message> messages;

  static const _shown = 8;

  @override
  Widget build(BuildContext context) {
    final images = messages.where(isViewableImage).toList().reversed.toList();
    if (images.isEmpty) return const SizedBox.shrink();
    final extra = images.length - _shown;
    final visible = images.take(_shown).toList();

    return ProfileCard(
      title: context.l10n.profileSharedMedia,
      trailing: '${images.length}',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            children: [
              for (var i = 0; i < visible.length; i++)
                GestureDetector(
                  onTap: () =>
                      ImageViewerScreen.open(context, visible[i], messages),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (visible[i].attachment?.thumbnail != null)
                          Image.memory(visible[i].attachment!.thumbnail!,
                              fit: BoxFit.cover, gaplessPlayback: true)
                        else
                          const ColoredBox(color: SepotColors.surfaceVariant),
                        if (i == _shown - 1 && extra > 0)
                          ColoredBox(
                            color: Colors.black54,
                            child: Center(
                              child: Text('+$extra',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
