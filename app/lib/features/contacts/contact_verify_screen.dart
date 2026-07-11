/// Ověření kontaktu — safety number.
///
/// Obě strany vidí STEJNÝCH 60 číslic (libsignal Fingerprint, menší
/// polovina první). Ověření: naskenovat QR protistrany (libsignal
/// porovná klíče křížem) nebo přečíst číslice jiným kanálem a potvrdit
/// ručně. Shoda → kontakt „ověřen"; neshoda → varování před MITM.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sepot/core/crypto/safety_number.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/storage_provider.dart';

/// Prefix QR obsahu — odlišuje ověřovací QR od kontaktního `sepot://add/`.
const _verifyQrPrefix = 'sepot-verify:';

class ContactVerifyScreen extends ConsumerStatefulWidget {
  const ContactVerifyScreen({super.key, required this.contactId});

  final String contactId;

  @override
  ConsumerState<ContactVerifyScreen> createState() =>
      _ContactVerifyScreenState();
}

class _ContactVerifyScreenState extends ConsumerState<ContactVerifyScreen> {
  SafetyNumber? _number;
  String? _numberForKey; // cache per identity klíč kontaktu

  SafetyNumber? _safetyNumber(Contact contact, Uint8List localKey) {
    final keyId = contact.publicIdentity.fingerprint.display;
    if (_number == null || _numberForKey != keyId) {
      _number = SafetyNumber.compute(
        localIdentityKey: localKey,
        remoteIdentityKey: contact.publicIdentity.identityKey,
      );
      _numberForKey = keyId;
    }
    return _number;
  }

  Future<void> _setVerified(Contact contact, bool verified) async {
    contact.verified = verified;
    await ref.read(storageProvider).saveContact(contact);
    ref.invalidate(contactsProvider);
  }

  Future<void> _scanAndCompare(Contact contact, SafetyNumber mine) async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _VerifyScanScreen()),
    );
    if (scanned == null || !mounted) return;

    var match = false;
    if (scanned.startsWith(_verifyQrPrefix)) {
      try {
        final theirs = Uint8List.fromList(
            base64Decode(scanned.substring(_verifyQrPrefix.length)));
        match = SafetyNumber.compare(mine.scannable, theirs);
      } on FormatException {
        match = false;
      }
    }

    if (match) {
      await _setVerified(contact, true);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          match ? Icons.verified : Icons.gpp_bad_outlined,
          color: match ? SepotColors.sage : SepotColors.error,
          size: 40,
        ),
        title: Text(
            match ? ctx.l10n.verifyVerified : ctx.l10n.verifyMismatchTitle),
        content: Text(
          match
              ? ctx.l10n.verifyMatchBody(contact.displayName)
              : ctx.l10n.verifyMismatchBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonUnderstood),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmManual(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.verifyManualConfirmTitle),
        content: Text(ctx.l10n.verifyManualConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.verifyManualConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed == true) await _setVerified(contact, true);
  }

  @override
  Widget build(BuildContext context) {
    final contact = ref
        .watch(contactsProvider)
        .valueOrNull
        ?.where((c) => c.id == widget.contactId)
        .firstOrNull;
    final identity = ref.watch(identityProvider).valueOrNull;

    if (contact == null || identity == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.verifyTitle)),
        body: const Center(
          child: CircularProgressIndicator(color: SepotColors.ember),
        ),
      );
    }

    final number = _safetyNumber(contact, identity.identityPublicKey)!;
    final qrData = '$_verifyQrPrefix${base64Encode(number.scannable)}';

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.verifyTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (contact.verified)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: SepotColors.sage.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified,
                        color: SepotColors.sage, size: 18),
                    const SizedBox(width: 8),
                    Text(context.l10n.verifyContactVerifiedBanner,
                        style: const TextStyle(color: SepotColors.sage)),
                  ],
                ),
              ),
            Text(
              context.l10n.verifyIntro(contact.displayName),
              style: const TextStyle(
                  color: SepotColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: qrData,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 60 číslic ve 12 blocích po 5 (4 řádky × 3 sloupce)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SepotColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var row = 0; row < 4; row++)
                    Padding(
                      padding: EdgeInsets.only(bottom: row < 3 ? 10 : 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var col = 0; col < 3; col++)
                            Text(
                              number.groups[row * 3 + col],
                              style: SepotTheme.cryptoText.copyWith(
                                fontSize: 17,
                                letterSpacing: 1.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _scanAndCompare(contact, number),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(context.l10n.verifyScanButton),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _confirmManual(contact),
              icon: const Icon(Icons.checklist_rounded),
              label: Text(context.l10n.verifyManualButton),
            ),
            if (contact.verified) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _setVerified(contact, false),
                child: Text(
                  context.l10n.verifyUnverifyButton,
                  style: const TextStyle(color: SepotColors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Minimalistický skener jen pro ověřovací QR — vrací syrový obsah kódu.
class _VerifyScanScreen extends StatefulWidget {
  const _VerifyScanScreen();

  @override
  State<_VerifyScanScreen> createState() => _VerifyScanScreenState();
}

class _VerifyScanScreenState extends State<_VerifyScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    _done = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.verifyScanScreenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
