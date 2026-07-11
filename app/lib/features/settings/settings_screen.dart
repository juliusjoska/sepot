import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/providers/settings_provider.dart';
import 'package:sepot/features/settings/biometrics_tile.dart';
import 'package:sepot/features/settings/language_settings_tile.dart';
import 'package:sepot/features/settings/push_settings_tile.dart';
import 'package:sepot/features/settings/tor_settings_tile.dart';
import 'package:sepot/widgets/sepot_logo.dart';

/// Nastavení aplikace
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profil
            identityAsync.when(
              data: (identity) {
                if (identity == null) return const SizedBox.shrink();
                return _buildProfileCard(context, identity);
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            // Sekce Obecné
            _buildSectionHeader(l10n.settingsSectionGeneral),
            const LanguageSettingsTile(),
            const SizedBox(height: 8),
            // Sekce Zabezpečení
            _buildSectionHeader(l10n.settingsSectionSecurity),
            _buildTile(
              icon: Icons.pin_outlined,
              title: l10n.settingsChangePinTitle,
              subtitle: l10n.settingsChangePinSubtitle,
              onTap: () => context.push('/change-pin'),
            ),
            const BiometricsTile(),
            _buildTile(
              icon: Icons.timer_outlined,
              title: l10n.settingsAutoLockTitle,
              subtitle: _autoLockLabel(
                l10n,
                ref.watch(autoLockProvider).valueOrNull ??
                    AutoLockNotifier.vychozi,
              ),
              onTap: () => _nastavAutoLock(context, ref),
            ),
            _buildTile(
              icon: Icons.password_outlined,
              title: l10n.settingsDecoyPinTitle,
              subtitle: ref.watch(hasDecoyPinProvider).valueOrNull == true
                  ? l10n.settingsDecoyPinSetSubtitle
                  : l10n.settingsDecoyPinUnsetSubtitle,
              trailing: ref.watch(hasDecoyPinProvider).valueOrNull == true
                  ? TextButton(
                      onPressed: () => _disableDecoyPin(context, ref),
                      child: Text(l10n.commonCancel),
                    )
                  : null,
              onTap: () {
                if (ref.read(hasDecoyPinProvider).valueOrNull != true) {
                  _setDecoyPin(context, ref);
                }
              },
            ),
            const SizedBox(height: 8),
            // Sekce Notifikace
            _buildSectionHeader(l10n.settingsSectionNotifications),
            const PushSettingsTile(),
            const SizedBox(height: 8),
            // Sekce Připojení — Tor je přes Orbot (Android). Na iOS zatím
            // není cesta k lokální SOCKS proxy, tak dlaždici skryjeme.
            if (Platform.isAndroid) ...[
              _buildSectionHeader(l10n.settingsSectionConnection),
              const TorSettingsTile(),
              const SizedBox(height: 8),
            ],
            // Sekce Soukromí
            // Mizící zprávy se nastavují per konverzaci (menu ⋮), globální
            // dlaždice tu byla mrtvá — odebrána místo předstírání funkce.
            _buildSectionHeader(l10n.settingsSectionPrivacy),
            _buildTile(
              icon: Icons.done_all,
              title: l10n.settingsReadReceiptsTitle,
              subtitle: l10n.settingsReadReceiptsSubtitle,
              trailing: Switch(
                value: ref.watch(readReceiptsProvider).valueOrNull ?? false,
                onChanged: (v) =>
                    ref.read(readReceiptsProvider.notifier).set(v),
                activeTrackColor: SepotColors.ember,
              ),
              onTap: () {},
            ),
            _buildTile(
              icon: Icons.screenshot_monitor_outlined,
              title: l10n.settingsScreenSecurityTitle,
              subtitle: l10n.settingsScreenSecuritySubtitle,
              trailing: Switch(
                value: ref.watch(screenSecurityProvider).valueOrNull ?? false,
                onChanged: (v) =>
                    ref.read(screenSecurityProvider.notifier).set(v),
                activeTrackColor: SepotColors.ember,
              ),
              onTap: () {},
            ),
            const SizedBox(height: 8),
            // Sekce Záloha
            _buildSectionHeader(l10n.settingsSectionBackup),
            _buildTile(
              icon: Icons.key_outlined,
              title: l10n.settingsSeedPhraseTitle,
              subtitle: l10n.settingsSeedPhraseSubtitle,
              onTap: () => _showSeedPhrase(context, ref),
            ),
            _buildTile(
              icon: Icons.backup_outlined,
              title: l10n.settingsBackupExportTitle,
              subtitle: l10n.settingsBackupExportSubtitle,
              onTap: () => _exportBackup(context, ref),
            ),
            _buildTile(
              icon: Icons.restore_outlined,
              title: l10n.settingsBackupImportTitle,
              subtitle: l10n.settingsBackupImportSubtitle,
              onTap: () => _importBackup(context, ref),
            ),
            // „Web klient" byl slib funkce, která neexistuje (multi-device je
            // vlna 3). Apple Guideline 2.1 takové dlaždice bere jako nedodělek.
            const SizedBox(height: 8),
            // Sekce Bezpečnost — Play UGC/CSAE policy, Apple Guideline 1.2.
            // Nahlášení musí být dostupné i mimo konkrétní konverzaci.
            _buildSectionHeader(l10n.settingsSectionSafety),
            _buildTile(
              icon: Icons.flag_outlined,
              title: l10n.settingsReportAbuseTitle,
              subtitle: l10n.settingsReportAbuseSubtitle,
              onTap: () => context.push('/report'),
            ),
            _buildTile(
              icon: Icons.shield_outlined,
              title: l10n.settingsChildSafetyTitle,
              subtitle: l10n.settingsChildSafetySubtitle,
              onTap: () => launchUrl(
                Uri.parse(AppConstants.childSafetyUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const SizedBox(height: 8),
            // Sekce O aplikaci
            _buildSectionHeader(l10n.settingsSectionAbout),
            _buildTile(
              icon: Icons.info_outline,
              title: l10n.commonAppName,
              subtitle: l10n.settingsVersion(AppConstants.appVersion),
              onTap: () => _showAbout(context),
            ),
            // Zdrojový kód je veřejný (AGPL-3.0). Detaily o licenci a odkaz
            // na repozitář dává dlaždice níže.
            _buildTile(
              icon: Icons.gavel_outlined,
              title: l10n.settingsLicenseTitle,
              subtitle: l10n.settingsLicenseSubtitle,
              onTap: () => _zobrazLicenci(context),
            ),
            _buildTile(
              icon: Icons.privacy_tip_outlined,
              title: l10n.settingsPrivacyPolicyTitle,
              subtitle: l10n.settingsPrivacyPolicySubtitle,
              onTap: () => _otevri(AppConstants.privacyUrl),
            ),
            _buildTile(
              icon: Icons.description_outlined,
              title: l10n.settingsTermsTitle,
              subtitle: l10n.settingsTermsSubtitle,
              onTap: () => _otevri(AppConstants.termsUrl),
            ),
            _buildTile(
              icon: Icons.delete_outline,
              title: l10n.settingsDataDeletionTitle,
              subtitle: l10n.settingsDataDeletionSubtitle,
              onTap: () => _otevri(AppConstants.deletionUrl),
            ),
            const SizedBox(height: 24),
            // Smazat účet
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton(
                onPressed: () => _confirmDeleteAccount(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SepotColors.error,
                  side: const BorderSide(color: SepotColors.error),
                ),
                child: Text(l10n.settingsDeleteAllDataButton),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Future<void> _otevri(String url) => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

  /// Popisek intervalu auto-zámku pro daný počet sekund.
  String _autoLockLabel(AppLocalizations l10n, int sekundy) {
    switch (sekundy) {
      case 0:
        return l10n.settingsAutoLockNever;
      case 60:
        return l10n.settingsAutoLock1min;
      case 900:
        return l10n.settingsAutoLock15min;
      default:
        return l10n.settingsAutoLock5min;
    }
  }

  /// AGPL-3.0 § 6 chce spolu s binárkou i nabídku zdrojového kódu.
  /// Zdroj je veřejný (repozitář, F-Droid, APK); tenhle text na něj odkazuje.
  void _zobrazLicenci(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.settingsLicenseTitle),
        content: Text(
          ctx.l10n.settingsLicenseBody(AppConstants.supportEmail),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.commonClose),
          ),
        ],
      ),
    );
  }

  Future<void> _nastavAutoLock(BuildContext context, WidgetRef ref) async {
    final ted = ref.read(autoLockProvider).valueOrNull ?? AutoLockNotifier.vychozi;
    final vybrano = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.settingsAutoLockTitle),
        children: [
          for (final sekundy in AutoLockNotifier.moznostiSekundy)
            ListTile(
              onTap: () => Navigator.pop(ctx, sekundy),
              leading: Icon(
                sekundy == ted
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: sekundy == ted
                    ? SepotColors.ember
                    : SepotColors.textMuted,
              ),
              title: Text(_autoLockLabel(ctx.l10n, sekundy)),
            ),
        ],
      ),
    );
    if (vybrano != null && vybrano != ted) {
      await ref.read(autoLockProvider.notifier).set(vybrano);
    }
  }

  Widget _buildProfileCard(BuildContext context, dynamic identity) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: SepotColors.surface,
        border: Border.all(color: SepotColors.border),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: SepotColors.ember.withValues(alpha: 0.1),
            child: Text(
              identity.displayName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: SepotColors.ember,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            identity.displayName,
            style: const TextStyle(
              fontFamily: kFontSans,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: SepotColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: identity.sepotId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.settingsIdCopied)),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  identity.sepotId,
                  style: SepotTheme.idText,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.copy, size: 14, color: SepotColors.ember),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsFingerprint(identity.fingerprint),
            style: SepotTheme.cryptoText.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: kFontSans,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: SepotColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: SepotColors.surfaceVariant,
        ),
        child: Icon(icon, size: 20, color: SepotColors.textSecondary),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: SepotColors.textMuted),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: SepotColors.textMuted),
      onTap: onTap,
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final identity = ref.read(identityProvider).valueOrNull;
    if (identity == null) return;
    try {
      final bytes = await ref.read(backupServiceProvider).export(identity);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/sepot-zaloha.sepotbackup';
      await File(path).writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/octet-stream')],
        subject: l10n.backupShareSubject,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupExportFailed(describeError(l10n, e)))),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final identity = ref.read(identityProvider).valueOrNull;
    if (identity == null) return;
    try {
      final res = await FilePicker.pickFiles(withData: true);
      final data = res?.files.firstOrNull?.bytes;
      if (data == null) return;
      final n = await ref.read(backupServiceProvider).import(identity, data);
      ref.invalidate(conversationsProvider);
      ref.invalidate(contactsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupRestoredCount(n))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupImportFailed(describeError(l10n, e)))),
        );
      }
    }
  }

  Future<void> _setDecoyPin(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    const numberField = TextInputType.number;
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.settingsDecoyPinTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ctx.l10n.settingsDecoyPinExplain,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: numberField,
              maxLength: 6,
              decoration: InputDecoration(
                  labelText: ctx.l10n.settingsDecoyPinTitle, counterText: ''),
            ),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              keyboardType: numberField,
              maxLength: 6,
              decoration: InputDecoration(
                  labelText: ctx.l10n.commonConfirm, counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.commonCancel)),
          TextButton(
            onPressed: () {
              if (pinCtrl.text.length == 6 &&
                  pinCtrl.text == confirmCtrl.text) {
                Navigator.pop(ctx, pinCtrl.text);
              }
            },
            child: Text(ctx.l10n.commonSet),
          ),
        ],
      ),
    );
    if (pin == null) return;
    try {
      await ref.read(storageProvider).enableDecoyPin(pin);
      ref.invalidate(hasDecoyPinProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsDecoyPinEnabled)),
        );
      }
    } on DecoyPinConflict {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsDecoyPinConflict)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(describeError(l10n, e))),
        );
      }
    }
  }

  Future<void> _disableDecoyPin(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    await ref.read(storageProvider).disableDecoyPin();
    ref.invalidate(hasDecoyPinProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsDecoyPinDisabled)),
      );
    }
  }

  void _showSeedPhrase(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final storage = ref.read(storageProvider);
    final seed = await storage.loadSeedPhrase();

    if (seed == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsSeedPhraseNotFound)),
        );
      }
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.settingsSeedPhraseTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ctx.l10n.settingsSeedPhraseWarning,
              style: const TextStyle(
                fontSize: 13,
                color: SepotColors.warning,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(seed.length, (i) {
                return Chip(
                  label: Text(
                    ctx.l10n.settingsSeedWordChip(i + 1, seed[i]),
                    style: SepotTheme.cryptoText,
                  ),
                  backgroundColor: SepotColors.surfaceVariant,
                  side: const BorderSide(color: SepotColors.border),
                );
              }),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonClose),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SepotLogo(size: 64),
            const SizedBox(height: 16),
            Text(
              ctx.l10n.settingsAboutTagline,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              ctx.l10n.settingsVersion(AppConstants.appVersion),
              style: const TextStyle(color: SepotColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              ctx.l10n.settingsAboutBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: SepotColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonClose),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.settingsDeleteAccountTitle),
        content: Text(
          ctx.l10n.settingsDeleteAccountBody,
          style: const TextStyle(color: SepotColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final messaging = ref.read(messagingServiceProvider);
              // Serverová deregistrace PŘED lokálním wipe — podpis
              // požadavku potřebuje identity klíč, který wipe zahodí.
              final serverOk = await messaging.deleteRelayAccount();
              // Messaging drží referenci na DB — zastavit PŘED smazáním
              await messaging.stop();
              await ref.read(storageProvider).deleteAll();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                if (!serverOk) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.l10n.settingsDeleteAccountServerOffline,
                      ),
                      duration: const Duration(seconds: 8),
                    ),
                  );
                }
                context.go('/onboarding');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SepotColors.error,
            ),
            child: Text(ctx.l10n.settingsDeleteAllConfirm),
          ),
        ],
      ),
    );
  }
}
