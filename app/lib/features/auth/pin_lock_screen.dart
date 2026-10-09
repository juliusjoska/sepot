import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sepot/core/crypto/dek_wrap.dart';
import 'package:sepot/core/storage/secure_storage.dart' show PinLockedException;
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/push_provider.dart';
import 'package:sepot/providers/settings_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/sepot_logo.dart';

/// Odemykací obrazovka s PINem (+ volitelná biometrie)
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _pin = '';
  String? _error;
  bool _isVerifying = false;
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    // Biometrie zapnutá → rovnou nabídnout systémovou výzvu
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  Future<void> _tryBiometrics() async {
    final unlockReason = context.l10n.pinUnlockTitle;
    final storage = ref.read(storageProvider);
    if (!await storage.isBiometricsEnabled()) return;
    if (mounted) setState(() => _biometricsAvailable = true);

    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: unlockReason,
        // biometricOnly: zámek telefonu (PIN/vzor zařízení) nesmí Šepot
        // odemknout — obešel by Argon2id ochranu DEK slabším faktorem.
        options: const AuthenticationOptions(
            stickyAuth: true, biometricOnly: true),
      );
      if (!ok) return; // uživatel zrušil → zůstává PIN
      await storage.unlockWithBiometrics();
      _restartMessagingAfterUnlock();
      if (mounted) context.go('/chats');
    } catch (_) {
      // biometrie nedostupná/selhala — PIN je vždy fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SepotLogo(size: 60, showText: false),
              const SizedBox(height: 24),
              Text(
                context.l10n.pinUnlockTitle,
                style: const TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: SepotColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.pinEnterPin,
                style: const TextStyle(color: SepotColors.textSecondary),
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
                    ),
                  );
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: SepotColors.error, fontSize: 14),
                ),
              ],
              if (_isVerifying) ...[
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
              const SizedBox(height: 48),
              _buildNumpad(),
              if (_biometricsAvailable) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _isVerifying ? null : _tryBiometrics,
                  icon: const Icon(Icons.fingerprint,
                      color: SepotColors.ember),
                  label: Text(
                    context.l10n.pinUnlockWithBiometrics,
                    style: const TextStyle(color: SepotColors.textSecondary),
                  ),
                ),
              ],
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
                if (key.isEmpty) return const SizedBox(width: 80, height: 64);
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
            color: isDelete ? Colors.transparent : SepotColors.surfaceVariant,
            border: isDelete ? null : Border.all(color: SepotColors.border),
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
    if (_isVerifying) return;
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
          _verifyPin();
        }
      }
    });
  }

  /// Auto-lock službu zastavil a storage zamkl; po odemčení je nutné
  /// messaging znovu nastartovat. messagingStartProvider drží starou
  /// „hotovou" hodnotu (start se sám neprovede) → invalidace ho přepočítá
  /// nad odemčeným storage a spustí start() znovu (jinak žádný příjem ani
  /// odesílání až do restartu appky).
  void _restartMessagingAfterUnlock() {
    ref.invalidate(messagingStartProvider);
    ref.invalidate(pushInitProvider);
    // Zabezpečení obrazovky se čte z DB — před odemčením provider nic
    // neaplikoval, teď má skutečnou hodnotu.
    ref.invalidate(screenSecurityProvider);
  }

  Future<void> _verifyPin() async {
    setState(() => _isVerifying = true);

    try {
      // „Ověření" PINu = Argon2id unwrap DEK + otevření SQLCipher DB.
      // Špatný PIN = GCM tag nesedí = DB zůstává nečitelná.
      await ref.read(storageProvider).unlockWithPin(_pin);
      _restartMessagingAfterUnlock();
      if (mounted) context.go('/chats');
    } on WrongPinException {
      final locked = await ref.read(storageProvider).pinLockRemaining();
      if (!mounted) return;
      setState(() {
        _error = locked == null
            ? context.l10n.pinWrong2
            : context.l10n.pinLockedFor(locked.inSeconds);
        _pin = '';
        _isVerifying = false;
      });
      HapticFeedback.heavyImpact();
    } on PinLockedException catch (e) {
      setState(() {
        _error = context.l10n.pinLockedFor(e.remaining.inSeconds);
        _pin = '';
        _isVerifying = false;
      });
    } on StateError {
      // Wrapped DEK neexistuje — nekonzistentní stav, zpět na onboarding
      if (mounted) context.go('/onboarding');
    } catch (e) {
      setState(() {
        _error = context.l10n.pinUnlockError;
        _pin = '';
        _isVerifying = false;
      });
    }
  }
}
