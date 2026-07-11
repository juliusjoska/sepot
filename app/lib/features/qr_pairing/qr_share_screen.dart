import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';

/// Sdílení vlastního QR kódu a Šepot ID
class QrShareScreen extends ConsumerWidget {
  const QrShareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.qrShareTitle),
      ),
      body: identityAsync.when(
        data: (identity) {
          if (identity == null) {
            return Center(child: Text(context.l10n.qrIdentityNotFound));
          }

          // Sdílet s routingem (accountId + delivery address z relaye),
          // jinak protistrana nemá kam poslat první zprávu
          final service = ref.watch(messagingServiceProvider);
          final shareString = (service.shareableIdentity ??
                  identity.publicIdentity)
              .toShareString();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                // QR kód
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: QrImageView(
                    data: shareString,
                    version: QrVersions.auto,
                    size: 240,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF030712),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: Color(0xFF030712),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Šepot ID
                Text(
                  identity.sepotId,
                  style: const TextStyle(
                    fontFamily: kFontMono,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: SepotColors.ember,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  identity.displayName,
                  style: const TextStyle(
                    fontFamily: kFontSans,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: SepotColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                // Fingerprint
                Text(
                  context.l10n.settingsFingerprint(identity.fingerprint.display),
                  style: SepotTheme.cryptoText,
                ),
                const SizedBox(height: 32),
                // Akce
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareString));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(context.l10n.commonCopiedToClipboard),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: Text(context.l10n.commonCopy),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Share.share(
                            context.l10n.qrShareInviteMessage(shareString),
                          );
                        },
                        icon: const Icon(Icons.share),
                        label: Text(context.l10n.commonShare),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Informace
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SepotColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SepotColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: SepotColors.textMuted, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.qrShareInfo,
                          style: const TextStyle(
                            fontSize: 13,
                            color: SepotColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: SepotColors.ember),
        ),
        error: (e, _) => Center(child: Text(describeError(context.l10n, e))),
      ),
    );
  }
}
