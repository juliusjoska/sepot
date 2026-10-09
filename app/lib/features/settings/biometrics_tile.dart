/// Přepínač biometrického odemčení.
///
/// Zapnutí = kopie DEK do OS keystore (TEE) — vědomé změkčení čistého
/// PIN-only modelu (DEK jinak existuje jen za Argon2id) výměnou za
/// pohodlí. Vyžaduje nastavený PIN a odemčené úložiště; enrolment se
/// potvrzuje systémovou biometrickou výzvou.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/storage_provider.dart';

class BiometricsTile extends ConsumerStatefulWidget {
  const BiometricsTile({super.key});

  @override
  ConsumerState<BiometricsTile> createState() => _BiometricsTileState();
}

class _BiometricsTileState extends ConsumerState<BiometricsTile> {
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(storageProvider).isBiometricsEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final storage = ref.read(storageProvider);
    try {
      if (value) {
        if (!await storage.hasPin()) {
          _snack(l10n.biometricsPinRequiredFirst);
          return;
        }
        if (!storage.isUnlocked) {
          _snack(l10n.biometricsStorageLocked);
          return;
        }
        final auth = LocalAuthentication();
        if (!await auth.isDeviceSupported()) {
          _snack(l10n.biometricsNotAvailable);
          return;
        }
        final ok = await auth.authenticate(
          localizedReason: l10n.biometricsEnrollPromptReason,
          options: const AuthenticationOptions(
              stickyAuth: true, biometricOnly: true),
        );
        if (!ok) return;
        await storage.enableBiometrics();
        if (mounted) setState(() => _enabled = true);
      } else {
        await storage.disableBiometrics();
        if (mounted) setState(() => _enabled = false);
      }
    } catch (e) {
      _snack(l10n.biometricsSetupFailed(describeError(l10n, e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: SepotColors.surfaceVariant,
        ),
        child: const Icon(Icons.fingerprint,
            size: 20, color: SepotColors.textSecondary),
      ),
      title: Text(context.l10n.biometricsTileTitle,
          style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        context.l10n.biometricsTileSubtitle,
        style: const TextStyle(fontSize: 13, color: SepotColors.textMuted),
      ),
      trailing: Switch(
        value: _enabled,
        onChanged: _busy ? null : _toggle,
        activeTrackColor: SepotColors.ember,
      ),
      onTap: () => _toggle(!_enabled),
    );
  }
}
