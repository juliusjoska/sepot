import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sepot/core/utils/share_origin.dart';
import 'package:sepot/core/utils/externi_obrazovka.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';

/// Sdílení vlastního QR kódu a Šepot ID
class QrShareScreen extends ConsumerWidget {
  const QrShareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.qrShareTitle)),
      body: identityAsync.when(
        data: (identity) {
          if (identity == null) {
            return Center(child: Text(context.l10n.qrIdentityNotFound));
          }

          // Sledovat stav připojení: po dokončení vlastní registrace se
          // routing (aid+da) zapíše do DB a relay se připojí → tenhle watch
          // obrazovku překreslí a QR se z „připojuji" přepne na hotový kód.
          ref.watch(relayConnectionProvider);
          final service = ref.watch(messagingServiceProvider);
          final shareable = service.shareableIdentity;
          final hasRouting =
              shareable != null &&
              shareable.accountId != null &&
              shareable.deliveryAddress != null;

          // Bez routingu by QR/odkaz byl neúplný (protistrana by neměla kam
          // poslat první zprávu → „Kontakt nemá doručovací adresu"). Radši
          // než mrtvý kód ukázat stav připojování.
          if (!hasRouting) {
            return QrConnectingPlaceholder(
              identity: identity,
              powProgress: service.registrationPowProgress,
            );
          }

          final shareString = shareable.toShareString();

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
                      // Odkaz s routingem dává hustý QR (verze ~12); kolečka místo
                      // čtverců ho slabším kamerám znečitelní.
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF030712),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.qrShareHowTo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: kFontSans,
                    fontSize: 16,
                    color: SepotColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                // Pozvánka je jediná cesta k přidání; dřív tu dominovalo velké
                // oranžové Šepot ID a lidé ho opisovali jako „kód“.
                SizedBox(
                  width: double.infinity,
                  child: Builder(
                    builder: (buttonContext) => ElevatedButton.icon(
                      onPressed: () {
                        ExterniObrazovka.behem(
                          () => Share.share(
                            context.l10n.qrShareInviteMessage(
                              AppConstants.downloadUrl,
                              shareString,
                            ),
                            sharePositionOrigin: shareOrigin(buttonContext),
                          ),
                        );
                      },
                      icon: const Icon(Icons.share),
                      label: Text(context.l10n.qrShareSendInvite),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.commonCopiedToClipboard),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(context.l10n.qrShareCopyInvite),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  context.l10n.qrShareSepotIdLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SepotColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(identity.sepotId, style: SepotTheme.cryptoText),
                const SizedBox(height: 4),
                Text(
                  context.l10n.settingsFingerprint(
                    identity.fingerprint.display,
                  ),
                  style: SepotTheme.cryptoText.copyWith(fontSize: 11),
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
                      const Icon(
                        Icons.info_outline,
                        color: SepotColors.textMuted,
                        size: 20,
                      ),
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

/// Stav obrazovky, dokud vlastní registrace na relay nedoběhne — místo
/// neúplného QR (bez routingu) ukáže identitu a hlášku o připojování.
/// Stav „ještě nejsem zaregistrovaný“ místo QR kódu. Veřejné jen kvůli
/// widget testu (jinak ho nikdo mimo tenhle soubor nestaví).
@visibleForTesting
class QrConnectingPlaceholder extends StatelessWidget {
  const QrConnectingPlaceholder({
    super.key,
    required this.identity,
    required this.powProgress,
  });

  final LocalIdentity identity;

  /// Postup proof-of-work před registrací; `null` = obyčejné připojování.
  final ValueListenable<double?> powProgress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: powProgress,
      builder: (context, progress, _) => _content(context, progress),
    );
  }

  Widget _content(BuildContext context, double? progress) {
    final computing = progress != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: SepotColors.ember,
              // Počet pokusů je náhodný — hodnota je odhad, ne slib.
              value: computing && progress > 0 ? progress : null,
            ),
            const SizedBox(height: 32),
            Text(
              computing
                  ? context.l10n.qrShareSecuringTitle
                  : context.l10n.qrShareConnectingTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: SepotColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              computing
                  ? context.l10n.qrShareSecuringBody
                  : context.l10n.qrShareConnectingBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: SepotColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(identity.sepotId, style: SepotTheme.cryptoText),
          ],
        ),
      ),
    );
  }
}
