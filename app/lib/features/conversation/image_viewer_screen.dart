/// Fullscreen prohlížeč obrázkové přílohy.
///
/// Plné rozlišení se dešifruje až tady, do PAMĚTI (na disk nikdy).
/// FLAG_SECURE platí globálně, takže screenshot/škrcení obrazovky
/// nehrozí ani ve vieweru. Sdílení jde přes systémový share sheet
/// (XFile.fromData — plaintext jen v cache sdílení).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:share_plus/share_plus.dart';

class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({super.key, required this.message});

  final Message message;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  late final Future<Uint8List?> _decrypted;

  @override
  void initState() {
    super.initState();
    _decrypted = ref
        .read(messagingServiceProvider)
        .loadDecryptedAttachment(widget.message);
  }

  Future<void> _share() async {
    final meta = widget.message.attachment!;
    final ext = meta.mime == 'image/png'
        ? 'png'
        : meta.mime == 'image/gif'
            ? 'gif'
            : 'jpg';
    final name = context.l10n.attachmentSharedImageFilename(ext);
    final bytes = await _decrypted;
    if (bytes == null) return;
    await Share.shareXFiles([
      XFile.fromData(bytes, name: name, mimeType: meta.mime),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _share,
          ),
        ],
      ),
      body: FutureBuilder<Uint8List?>(
        future: _decrypted,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: SepotColors.ember),
            );
          }
          final bytes = snapshot.data;
          if (snapshot.hasError || bytes == null) {
            return Center(
              child: Text(
                context.l10n.attachmentDecryptFailed,
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }
          return InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}
