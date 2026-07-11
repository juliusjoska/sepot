import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/crypto/mnemonic.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Obnova účtu ze zálohovací fráze (24 slov). Vrátí IDENTITU (klíč →
/// stejný SEP kód a safety number), NE historii zpráv.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _nameController = TextEditingController();
  final _wordsController = TextEditingController();
  bool _restoring = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _wordsController.dispose();
    super.dispose();
  }

  /// Rozsekej vstup na slova (mezery, nové řádky, čárky, čísla „1." pryč).
  List<String> _parseWords(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\d+[.)]?'), ' ')
        .split(RegExp(r'[\s,]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  int get _wordCount => _parseWords(_wordsController.text).length;

  Future<void> _restore() async {
    final name = _nameController.text.trim();
    final words = _parseWords(_wordsController.text);
    if (name.isEmpty) {
      setState(() => _error = context.l10n.restoreErrorNameRequired);
      return;
    }
    if (words.length != AppConstants.seedPhraseWords) {
      setState(() => _error = context.l10n.restoreErrorWordCount(
          _wordCount, AppConstants.seedPhraseWords));
      return;
    }
    if (!SepotMnemonic.isValid(words)) {
      setState(() => _error = context.l10n.restoreErrorInvalidPhrase);
      return;
    }

    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      await ref
          .read(identityProvider.notifier)
          .recoverIdentity(words, name);
      await ref.read(storageProvider).setOnboardingComplete(true);
      if (mounted) context.go('/pin-setup');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error =
            context.l10n.restoreErrorFailed(describeError(context.l10n, e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = _wordCount == AppConstants.seedPhraseWords &&
        _nameController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.restoreTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.restoreHeading,
                style: const TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: SepotColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.restoreIntro(AppConstants.seedPhraseWords),
                style: const TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 14,
                  height: 1.5,
                  color: SepotColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              // Upozornění na historii
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: SepotColors.warning.withValues(alpha: 0.1),
                  border: Border.all(
                      color: SepotColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 20, color: SepotColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.restoreHistoryWarning,
                        style: TextStyle(
                            fontSize: 13,
                            color: SepotColors.textPrimary.withValues(alpha: .9)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.onboardingDisplayNameLabel,
                  hintText: context.l10n.onboardingDisplayNameHint,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _wordsController,
                minLines: 4,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[^\w\s.,)]')),
                ],
                decoration: InputDecoration(
                  labelText: context.l10n.settingsSeedPhraseTitle,
                  hintText: context.l10n.restorePhraseHint,
                  alignLabelWithHint: true,
                  helperText: context.l10n.restoreWordCountHelper(
                      _wordCount, AppConstants.seedPhraseWords),
                  helperStyle: TextStyle(
                    color: _wordCount == AppConstants.seedPhraseWords
                        ? SepotColors.sage
                        : SepotColors.textMuted,
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: SepotColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (ok && !_restoring) ? _restore : null,
                  child: _restoring
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(context.l10n.restoreTitle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
