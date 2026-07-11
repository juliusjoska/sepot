import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Nastavení PINu (6 číslic)
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _pin = '';
  String? _firstPin;
  bool _isConfirming = false;
  bool _isSaving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SepotColors.ember.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.pin_rounded,
                  size: 32,
                  color: SepotColors.ember,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isConfirming
                    ? context.l10n.pinConfirmTitle
                    : context.l10n.pinSetupTitle,
                style: const TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: SepotColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isConfirming
                    ? context.l10n.pinConfirmSubtitle
                    : context.l10n.pinSetupSubtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: SepotColors.textSecondary,
                ),
              ),
              const SizedBox(height: 48),
              // PIN tečky
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  return Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? SepotColors.ember
                          : SepotColors.border,
                      border: Border.all(
                        color: i < _pin.length
                            ? SepotColors.ember
                            : SepotColors.border,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: SepotColors.error,
                    fontSize: 14,
                  ),
                ),
              ],
              if (_isSaving) ...[
                const SizedBox(height: 16),
                // Argon2id wrap DEK běží (~sekundy, memory-hard záměrně)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SepotColors.ember,
                  ),
                ),
              ],
              const SizedBox(height: 48),
              // Numerická klávesnice
              _buildNumpad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'DEL'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((key) {
                if (key.isEmpty) {
                  return const SizedBox(width: 80, height: 64);
                }
                return _buildKey(key);
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildKey(String key) {
    final isDelete = key == 'DEL';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: () => _onKeyPress(key),
        borderRadius: BorderRadius.circular(32),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDelete
                ? Colors.transparent
                : SepotColors.surfaceVariant,
            border: isDelete
                ? null
                : Border.all(color: SepotColors.border),
          ),
          child: Center(
            child: isDelete
                ? const Icon(
                    Icons.backspace_outlined,
                    color: SepotColors.textSecondary,
                    size: 24,
                  )
                : Text(
                    key,
                    style: const TextStyle(
                      fontFamily: kFontSans,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: SepotColors.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _onKeyPress(String key) {
    if (_isSaving) return;
    HapticFeedback.lightImpact();

    setState(() {
      _error = null;

      if (key == 'DEL') {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      } else if (_pin.length < 6) {
        _pin += key;

        if (_pin.length == 6) {
          _onPinComplete();
        }
      }
    });
  }

  Future<void> _onPinComplete() async {
    if (_firstPin == null) {
      // První zadání PINu
      setState(() {
        _firstPin = _pin;
        _pin = '';
        _isConfirming = true;
      });
    } else {
      // Potvrzení PINu
      if (_pin == _firstPin) {
        // PINy se shodují — zabal DEK za Argon2id(PIN); od téhle chvíle
        // je PIN klíčem k databázi, ne vizuálním zámkem
        setState(() => _isSaving = true);
        try {
          await ref.read(storageProvider).enablePin(_pin);
        } catch (e) {
          setState(() {
            _error = context.l10n.pinSetupFailed;
            _pin = '';
            _firstPin = null;
            _isConfirming = false;
            _isSaving = false;
          });
          return;
        }

        if (mounted) {
          context.go('/chats');
        }
      } else {
        // PINy se neshodují
        setState(() {
          _error = context.l10n.pinMismatchRetry;
          _pin = '';
          _firstPin = null;
          _isConfirming = false;
        });
      }
    }
  }
}
