import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/locale_provider.dart';

/// Volba jazyka aplikace: podle systému, nebo ruční přepnutí.
///
/// Názvy jazyků se záměrně nepřekládají — každý je ve své nativní podobě,
/// aby uživatel našel svůj jazyk i v cizím rozhraní.
const _jazyky = <String, String>{
  'cs': 'Čeština',
  'en': 'English',
  'de': 'Deutsch',
  'ru': 'Русский',
  'it': 'Italiano',
};

class LanguageSettingsTile extends ConsumerWidget {
  const LanguageSettingsTile({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final current = ref.read(localeProvider).valueOrNull?.languageCode;
    final l10n = context.l10n;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsLanguage),
        children: [
          RadioGroup<String>(
            groupValue: current ?? '',
            onChanged: (value) => Navigator.pop(ctx, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: '',
                  title: Text(l10n.languageSystem),
                ),
                for (final entry in _jazyky.entries)
                  RadioListTile<String>(
                    value: entry.key,
                    title: Text(entry.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;

    await ref
        .read(localeProvider.notifier)
        .set(picked.isEmpty ? null : Locale(picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider).valueOrNull?.languageCode;
    final subtitle = _jazyky[code] ?? context.l10n.languageSystem;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: SepotColors.surfaceVariant,
        ),
        child: const Icon(
          Icons.translate,
          size: 20,
          color: SepotColors.textSecondary,
        ),
      ),
      title: Text(context.l10n.settingsLanguage,
          style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: SepotColors.textMuted),
      ),
      onTap: () => _pick(context, ref),
    );
  }
}
