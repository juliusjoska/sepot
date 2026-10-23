/// Změna PINu ve třech krocích (starý → nový → potvrzení).
///
/// PIN se neověřuje proti hashi, ale unwrapem DEK (Argon2id). Každý pokus
/// proto stojí ~2 s, což je zároveň jediná potřebná ochrana proti hádání.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sepot/core/crypto/dek_wrap.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/pin_keypad.dart';

enum _Krok { stary, novy, potvrzeni }

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  _Krok _krok = _Krok.stary;
  String _pin = '';
  String? _staryPin;
  String? _novyPin;
  bool _pracuje = false;
  String? _chyba;

  (String, String) _titulky(AppLocalizations l10n) => switch (_krok) {
        _Krok.stary =>
          (l10n.pinChangeCurrentTitle, l10n.pinChangeCurrentSubtitle),
        _Krok.novy => (l10n.pinChangeNewTitle, l10n.pinChangeNewSubtitle),
        _Krok.potvrzeni =>
          (l10n.pinChangeConfirmTitle, l10n.pinChangeConfirmSubtitle),
      };

  void _reset(String chyba) {
    setState(() {
      _chyba = chyba;
      _pin = '';
      _staryPin = null;
      _novyPin = null;
      _krok = _Krok.stary;
      _pracuje = false;
    });
  }

  void _klavesa(String k) {
    if (_pracuje) return;
    setState(() {
      _chyba = null;
      if (k == 'DEL') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        return;
      }
      if (_pin.length < 6) _pin += k;
    });
    if (_pin.length == 6) _hotovoSest();
  }

  Future<void> _hotovoSest() async {
    final storage = ref.read(storageProvider);

    switch (_krok) {
      case _Krok.stary:
        setState(() => _pracuje = true);
        final bool ok;
        try {
          ok = await storage.verifyPin(_pin);
        } on PinLockedException catch (e) {
          if (!mounted) return;
          _reset(context.l10n.pinLockedFor(e.remaining.inSeconds));
          return;
        }
        if (!mounted) return;
        if (!ok) {
          _reset(context.l10n.pinWrong);
          return;
        }
        setState(() {
          _staryPin = _pin;
          _pin = '';
          _krok = _Krok.novy;
          _pracuje = false;
        });

      case _Krok.novy:
        if (_pin == _staryPin) {
          setState(() {
            _chyba = context.l10n.pinChangeMustDiffer;
            _pin = '';
          });
          return;
        }
        setState(() {
          _novyPin = _pin;
          _pin = '';
          _krok = _Krok.potvrzeni;
        });

      case _Krok.potvrzeni:
        if (_pin != _novyPin) {
          setState(() {
            _chyba = context.l10n.pinMismatch;
            _pin = '';
            _novyPin = null;
            _krok = _Krok.novy;
          });
          return;
        }
        setState(() => _pracuje = true);
        try {
          await storage.changePin(oldPin: _staryPin!, newPin: _novyPin!);
        } on DecoyPinConflict catch (e) {
          if (!mounted) return;
          _reset(describeError(context.l10n, e));
          return;
        } on WrongPinException {
          if (!mounted) return;
          _reset(context.l10n.pinWrong);
          return;
        } catch (_) {
          if (!mounted) return;
          _reset(context.l10n.pinChangeFailed);
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.pinChanged)),
        );
        context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final (titulek, popis) = _titulky(context.l10n);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsChangePinTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                titulek,
                style: const TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: SepotColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                popis,
                style: const TextStyle(
                    fontSize: 14, color: SepotColors.textSecondary),
              ),
              const SizedBox(height: 40),
              PinDots(filled: _pin.length),
              if (_chyba != null) ...[
                const SizedBox(height: 16),
                Text(
                  _chyba!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: SepotColors.error, fontSize: 14),
                ),
              ],
              if (_pracuje) ...[
                const SizedBox(height: 16),
                // Argon2id (64 MiB, t=3) — pár sekund je záměr, ne prodleva.
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: SepotColors.ember),
                ),
              ],
              const SizedBox(height: 40),
              PinKeypad(onKey: _klavesa, enabled: !_pracuje),
            ],
          ),
        ),
      ),
    );
  }
}
