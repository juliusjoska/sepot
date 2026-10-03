import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/poll.dart';
import 'package:sepot/widgets/avatar.dart';

/// Anketa v bublině: otázka, možnosti s pruhem výsledků a kolečky
/// hlasujících. Klepnutí na možnost hlasuje (znovu = zrušit).
class PollContent extends StatelessWidget {
  const PollContent({
    super.key,
    required this.poll,
    required this.onEmber,
    required this.myId,
    required this.nameOf,
    required this.onVote,
  });

  final Poll poll;

  /// Kreslí se na korálové bublině (moje anketa).
  final bool onEmber;
  final String myId;
  final String Function(String fingerprint) nameOf;
  final void Function(List<int> choice)? onVote;

  static const _maxFaces = 3;

  void _toggle(int index) {
    final mine = poll.votes[myId] ?? const <int>[];
    final List<int> next;
    if (poll.multi) {
      next = mine.contains(index)
          ? (mine.toList()..remove(index))
          : [...mine, index];
    } else {
      next = mine.contains(index) ? const [] : [index];
    }
    HapticFeedback.selectionClick();
    onVote?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final ink = onEmber ? SepotColors.emberInk : SepotColors.textPrimary;
    final soft = onEmber
        ? SepotColors.emberInk.withValues(alpha: 0.65)
        : SepotColors.textSecondary;
    final track = onEmber
        ? SepotColors.emberInk.withValues(alpha: 0.12)
        : SepotColors.background.withValues(alpha: 0.55);
    final fill = onEmber
        ? SepotColors.emberInk.withValues(alpha: 0.22)
        : SepotColors.ember.withValues(alpha: 0.24);
    final mine = poll.votes[myId] ?? const <int>[];
    final total = poll.voterCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.bar_chart_rounded, size: 15, color: soft),
            const SizedBox(width: 5),
            Text(
              '${poll.multi ? context.l10n.pollMulti : context.l10n.pollSingle}'
              ' · ${context.l10n.pollVoters(total)}',
              style: TextStyle(fontSize: 12, color: soft),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(poll.question,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 10),
        for (var i = 0; i < poll.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _OptionRow(
            label: poll.options[i],
            count: poll.countFor(i),
            share: total == 0 ? 0 : poll.countFor(i) / total,
            chosen: mine.contains(i),
            voters: poll.votersFor(i),
            nameOf: nameOf,
            ink: ink,
            track: track,
            fill: fill,
            onEmber: onEmber,
            onTap: onVote == null ? null : () => _toggle(i),
          ),
        ],
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.count,
    required this.share,
    required this.chosen,
    required this.voters,
    required this.nameOf,
    required this.ink,
    required this.track,
    required this.fill,
    required this.onEmber,
    required this.onTap,
  });

  final String label;
  final int count;
  final double share;
  final bool chosen;
  final List<String> voters;
  final String Function(String) nameOf;
  final Color ink;
  final Color track;
  final Color fill;
  final bool onEmber;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = onEmber ? SepotColors.emberInk : SepotColors.ember;
    return Semantics(
      button: onTap != null,
      selected: chosen,
      label: '$label, $count',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: chosen ? accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    widthFactor: share.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: ColoredBox(color: fill),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      chosen
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: chosen ? accent : ink.withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label,
                          style: TextStyle(fontSize: 14, color: ink)),
                    ),
                    if (voters.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _Faces(voters: voters, nameOf: nameOf),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Překrývající se kolečka prvních hlasujících.
class _Faces extends StatelessWidget {
  const _Faces({required this.voters, required this.nameOf});

  final List<String> voters;
  final String Function(String) nameOf;

  @override
  Widget build(BuildContext context) {
    final shown = voters.take(PollContent._maxFaces).toList();
    return SizedBox(
      width: 20.0 + (shown.length - 1) * 13,
      height: 20,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 13.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: SepotColors.surface, width: 1.5),
                ),
                child: SepotAvatar(
                    name: nameOf(shown[i]), seed: shown[i], size: 17),
              ),
            ),
        ],
      ),
    );
  }
}
