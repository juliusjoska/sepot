import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/providers/contacts_provider.dart';

/// QR skener pro přidání kontaktů
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.qrScanTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Overlay
          _buildOverlay(),
          // Spodní panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    SepotColors.background.withValues(alpha: 0.9),
                    SepotColors.background,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: SepotColors.ember,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.qrScanInstruction,
                      style: const TextStyle(
                        fontSize: 16,
                        color: SepotColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.qrScanHint,
                      style: const TextStyle(
                        fontSize: 13,
                        color: SepotColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanSize = constraints.maxWidth * 0.7;
        final left = (constraints.maxWidth - scanSize) / 2;
        final top = (constraints.maxHeight - scanSize) / 2 - 40;

        return Stack(
          children: [
            // Tmavý overlay kolem
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                SepotColors.background.withValues(alpha: 0.5),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.red, // Jakákoliv nepůhledná barva
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: top,
                    child: Container(
                      width: scanSize,
                      height: scanSize,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Rámec skenu
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: scanSize,
                height: scanSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: SepotColors.ember,
                    width: 3,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final shareString = barcode!.rawValue!;
    final identity = PublicIdentity.fromShareString(shareString);

    if (identity == null) return;

    setState(() => _isProcessing = true);
    _controller.stop();

    _showContactConfirmation(identity);
  }

  void _showContactConfirmation(PublicIdentity identity) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.qrNewContactTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: SepotColors.ember.withValues(alpha: 0.1),
              child: Text(
                identity.displayName.isEmpty
                    ? '?'
                    : identity.displayName.characters.first.toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: SepotColors.ember,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              identity.displayName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              identity.sepotId,
              style: SepotTheme.cryptoText,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsFingerprint(identity.fingerprint.display),
              style: SepotTheme.cryptoText.copyWith(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _controller.start();
              setState(() => _isProcessing = false);
            },
            child: Text(context.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(contactsProvider.notifier)
                    .addContact(identity, verified: true);

                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(context.l10n.qrContactAdded(identity.displayName)),
                    ),
                  );
                  context.pop();
                }
              } catch (e) {
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(describeError(context.l10n, e))),
                  );
                }
                _controller.start();
                setState(() => _isProcessing = false);
              }
            },
            child: Text(context.l10n.commonAdd),
          ),
        ],
      ),
    );
  }
}
