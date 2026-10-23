/// Čerstvé ověření před citlivou akcí v už odemčené appce.
///
/// Odemčený telefon v cizí ruce nesmí stačit na převzetí účtu: 24 slov,
/// záloha, smazání účtu nebo oslabení zámku chtějí PIN (Argon2id unwrap,
/// stejná brzda jako zámková obrazovka), případně skutečnou biometrii.
/// Žádné okno „před chvílí jsem ověřil“ — každá akce se ptá znovu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/pin_keypad.dart';

/// Systémová biometrická výzva. Provider kvůli testům — skutečný
/// `local_auth` ve widget testu neběží.
final biometricPromptProvider = Provider<Future<bool> Function(String reason)>((
  ref,
) {
  return (reason) => LocalAuthentication().authenticate(
    localizedReason: reason,
    // biometricOnly: zámek telefonu (PIN/vzor zařízení) by obešel
    // Argon2id ochranu slabším faktorem, který zná i „půjčovatel“.
    options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
  );
});

/// Vrátí true, jen když uživatel právě teď prokázal, že zná PIN, nebo
/// prošel biometrií. [reason] se ukáže ve výzvě.
///
/// [allowBiometrics] = false u akcí, které biometrii samy zakládají:
/// zapnutí biometrie se nesmí potvrdit tím, co se teprve zapíná.
Future<bool> confirmSensitiveAction(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  bool allowBiometrics = true,
}) async {
  final storage = ref.read(storageProvider);
  if (storage.isDecoyMode) return false;

  if (!await storage.hasPin()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.reauthPinRequired),
          action: SnackBarAction(
            label: context.l10n.reauthSetPin,
            onPressed: () => context.push('/pin-setup'),
          ),
        ),
      );
    }
    return false;
  }

  if (allowBiometrics && await storage.isBiometricsEnabled()) {
    try {
      if (await ref.read(biometricPromptProvider)(reason)) return true;
    } catch (_) {
      // Biometrie nedostupná nebo zrušená — PIN je vždy cesta.
    }
  }

  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SepotColors.background,
    builder: (_) => _ReauthPinSheet(reason: reason),
  );
  return ok ?? false;
}

class _ReauthPinSheet extends ConsumerStatefulWidget {
  const _ReauthPinSheet({required this.reason});

  final String reason;

  @override
  ConsumerState<_ReauthPinSheet> createState() => _ReauthPinSheetState();
}

class _ReauthPinSheetState extends ConsumerState<_ReauthPinSheet> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  void _onKey(String key) {
    if (_busy) return;
    setState(() {
      _error = null;
      if (key == 'DEL') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += key;
      }
    });
    if (_pin.length == 6) _verify();
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    final l10n = context.l10n;
    final storage = ref.read(storageProvider);
    String error;
    try {
      if (await storage.verifyPin(_pin)) {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final locked = await storage.pinLockRemaining();
      error = locked == null
          ? l10n.pinWrong
          : l10n.pinLockedFor(locked.inSeconds);
    } on PinLockedException catch (e) {
      error = l10n.pinLockedFor(e.remaining.inSeconds);
    }
    if (!mounted) return;
    setState(() {
      _error = error;
      _pin = '';
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.reauthTitle,
            style: const TextStyle(
              fontFamily: kFontSans,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: SepotColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.reason,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: SepotColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          PinDots(filled: _pin.length),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SepotColors.error, fontSize: 14),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SepotColors.ember,
              ),
            ),
          ],
          const SizedBox(height: 32),
          PinKeypad(onKey: _onKey, enabled: !_busy),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }
}
