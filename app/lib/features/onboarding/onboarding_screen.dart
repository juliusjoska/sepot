import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/sepot_logo.dart';

/// Onboarding — 3 stránky + generování identity
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  final _nameController = TextEditingController();
  List<String>? _seedPhrase;
  bool _isCreating = false;
  bool _seedSaved = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Indikátor stránek
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i <= _currentPage
                            ? SepotColors.ember
                            : SepotColors.border,
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Stránky
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildEncryptionPage(),
                  _buildIdentityPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Stránka 1: Uvítání
  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SepotLogo(size: 100),
          const SizedBox(height: 48),
          Text(
            context.l10n.onboardingWelcomeTitle,
            style: const TextStyle(
              fontFamily: kFontSans,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: SepotColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.onboardingWelcomeSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: kFontSans,
              fontSize: 16,
              height: 1.6,
              color: SepotColors.textSecondary,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () => _pageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
            child: Text(context.l10n.onboardingStart),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push('/restore'),
            child: Text(context.l10n.onboardingRestoreExisting),
          ),
        ],
      ),
    );
  }

  /// Stránka 2: Vysvětlení šifrování
  Widget _buildEncryptionPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SepotColors.mist.withValues(alpha: 0.1),
              border: Border.all(color: SepotColors.mist.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.shield_rounded,
              size: 40,
              color: SepotColors.mist,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            context.l10n.onboardingEncryptionTitle,
            style: const TextStyle(
              fontFamily: kFontSans,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: SepotColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          _buildFeatureRow(
            Icons.lock_rounded,
            context.l10n.onboardingFeatureSignalTitle,
            context.l10n.onboardingFeatureSignalSubtitle,
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            Icons.fingerprint,
            context.l10n.onboardingFeaturePqTitle,
            context.l10n.onboardingFeaturePqSubtitle,
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            Icons.phone_android_rounded,
            context.l10n.onboardingFeatureLocalKeysTitle,
            context.l10n.onboardingFeatureLocalKeysSubtitle,
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            Icons.timer_outlined,
            context.l10n.chatDisappearingMessages,
            context.l10n.onboardingFeatureDisappearingSubtitle,
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () => _pageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
            child: Text(context.l10n.commonContinue),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: SepotColors.surfaceVariant,
          ),
          child: Icon(icon, size: 22, color: SepotColors.ember),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SepotColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: SepotColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Stránka 3: Generování identity
  Widget _buildIdentityPage() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              context.l10n.onboardingIdentityTitle,
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: SepotColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.onboardingIdentitySubtitle,
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 14,
                color: SepotColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: context.l10n.onboardingDisplayNameLabel,
                hintText: context.l10n.onboardingDisplayNameHint,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              // Bez rebuildů by tlačítko „Vygenerovat klíče" zůstalo
              // navždy disabled (jeho stav čte controller v build())
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 32),
            if (_seedPhrase != null) ...[
              Text(
                context.l10n.settingsSeedPhraseTitle,
                style: const TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SepotColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.onboardingSeedPhraseWarning(_seedPhrase!.length),
                style: const TextStyle(
                  fontSize: 13,
                  color: SepotColors.warning,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: SepotColors.surfaceVariant,
                  border: Border.all(color: SepotColors.border),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_seedPhrase!.length, (i) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: SepotColors.surface,
                        border: Border.all(color: SepotColors.border),
                      ),
                      child: Text(
                        '${i + 1}. ${_seedPhrase![i]}',
                        style: SepotTheme.cryptoText.copyWith(fontSize: 13),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _seedSaved,
                onChanged: (v) => setState(() => _seedSaved = v ?? false),
                title: Text(
                  context.l10n.onboardingSeedSavedConfirm,
                  style: const TextStyle(fontSize: 14),
                ),
                activeColor: SepotColors.ember,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 24),
            if (_seedPhrase == null)
              ElevatedButton(
                onPressed: _nameController.text.trim().isNotEmpty
                    ? _generateIdentity
                    : null,
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.l10n.onboardingGenerateKeys),
              )
            else
              ElevatedButton(
                onPressed: _seedSaved ? _completeOnboarding : null,
                child: Text(context.l10n.commonContinue),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateIdentity() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _isCreating = true);

    try {
      // Vygeneruj identitu
      final identity = await ref
          .read(identityProvider.notifier)
          .createIdentity(_nameController.text.trim());

      // Seed fráze = skutečná záloha identity klíče (BIP39 enkódování),
      // NE nezávislá slova — jinak by obnova nikdy nefungovala
      final seed = identity.mnemonic;
      await ref.read(storageProvider).saveSeedPhrase(seed);

      setState(() {
        _seedPhrase = seed;
        _isCreating = false;
      });
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(describeError(context.l10n, e))),
        );
      }
    }
  }

  Future<void> _completeOnboarding() async {
    final storage = ref.read(storageProvider);
    await storage.setOnboardingComplete(true);

    if (mounted) {
      context.go('/pin-setup');
    }
  }
}
