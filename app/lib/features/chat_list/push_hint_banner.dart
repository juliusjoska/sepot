import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/push_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Upozornění nad seznamem chatů, když budíčky nefungují.
///
/// Bez pushe Android appku na pozadí uspí a zprávy dorazí, až ji uživatel
/// sám otevře — vypadá to jako výpadek doručování, i když relay má všechno
/// připravené ve frontě. Proužek je proto informace o stavu, ne reklama:
/// zmizí, jakmile si push nastaví, a jde odmítnout natrvalo.
class PushHintBanner extends ConsumerWidget {
  const PushHintBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(pushHealthProvider).valueOrNull;
    final dismissed = ref.watch(pushHintDismissedProvider).valueOrNull ?? true;
    if (dismissed || health == null || health == PushHealth.ok) {
      return const SizedBox.shrink();
    }

    final text = health == PushHealth.failed
        ? context.l10n.pushHintFailed
        : context.l10n.pushHintOff;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Material(
        color: SepotColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/settings'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  size: 18,
                  color: health == PushHealth.failed
                      ? SepotColors.ember
                      : SepotColors.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontFamily: kFontSans,
                      fontSize: 13,
                      color: SepotColors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: SepotColors.textMuted,
                  tooltip: context.l10n.commonClose,
                  onPressed: () async {
                    await ref
                        .read(storageProvider)
                        .setSetting('push_hint_dismissed', true);
                    ref.invalidate(pushHintDismissedProvider);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
