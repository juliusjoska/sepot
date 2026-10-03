/// Fotky konverzace přes celou obrazovku — listování, přiblížení, sdílení.
///
/// Plné rozlišení se dešifruje až tady, do PAMĚTI (na disk nikdy).
/// FLAG_SECURE platí globálně, takže screenshot/škrcení obrazovky
/// nehrozí ani ve vieweru. Sdílení jde přes systémový share sheet
/// (XFile.fromData — plaintext jen v cache sdílení).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/attachment.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/widgets/avatar.dart';
import 'package:sepot/widgets/glass.dart';
import 'package:share_plus/share_plus.dart';

/// Fotky zprávy, které jde otevřít: stažené obrázky, ne smazané.
bool isViewableImage(Message m) =>
    !m.isDeleted &&
    m.type == MessageType.image &&
    m.attachment?.state == AttachmentTransferState.ready;

class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  /// Fotky od nejstarší po nejnovější (pořadí jako v chatu).
  final List<Message> images;
  final int initialIndex;

  /// Otevře fotku [message] a nabídne listování ostatními z [all].
  static Future<void> open(
      BuildContext context, Message message, List<Message> all) {
    final images = all.where(isViewableImage).toList();
    var index = images.indexWhere((m) => m.id == message.id);
    if (index < 0) {
      images
        ..clear()
        ..add(message);
      index = 0;
    }
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) =>
            ImageViewerScreen(images: images, initialIndex: index),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _decrypted = <String, Future<Uint8List?>>{};
  bool _chrome = true;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<Uint8List?> _load(Message m) => _decrypted.putIfAbsent(
      m.id,
      () => ref.read(messagingServiceProvider).loadDecryptedAttachment(m));

  Message get _current => widget.images[_index];

  Future<void> _share() async {
    final meta = _current.attachment!;
    final ext = meta.mime == 'image/png'
        ? 'png'
        : meta.mime == 'image/gif'
            ? 'gif'
            : 'jpg';
    final name = context.l10n.attachmentSharedImageFilename(ext);
    final bytes = await _load(_current);
    if (bytes == null) return;
    await Share.shareXFiles([
      XFile.fromData(bytes, name: name, mimeType: meta.mime),
    ]);
  }

  String _senderName(Message m) {
    final me = ref.read(identityProvider).valueOrNull;
    if (m.senderId == me?.id) return context.l10n.groupsYou;
    final contact = (ref.read(contactsProvider).valueOrNull ?? const [])
        .where((c) => c.publicIdentity.id == m.senderId)
        .firstOrNull;
    return contact?.displayName.isNotEmpty == true
        ? contact!.displayName
        : context.l10n.commonUnknownContact;
  }

  @override
  Widget build(BuildContext context) {
    final m = _current;
    final locale = Localizations.localeOf(context).toString();
    final when =
        '${DateFormat.MMMd(locale).format(m.timestamp)} ${DateFormat.Hm(locale).format(m.timestamp)}';
    final total = widget.images.length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _chrome = !_chrome),
                child: PageView.builder(
                  controller: _pages,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _Page(future: _load(widget.images[i])),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _chrome ? 0 : -140,
              left: 0,
              right: 0,
              child: GlassSurface(
                border: false,
                padding: EdgeInsets.fromLTRB(
                    4, MediaQuery.paddingOf(context).top + 6, 8, 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    SepotAvatar(name: _senderName(m), seed: m.senderId, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_senderName(m),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                          Text(
                            total > 1
                                ? '$when · ${context.l10n.chatSearchCounter(_index + 1, total)}'
                                : when,
                            style: const TextStyle(
                                fontSize: 12,
                                color: SepotColors.textEmphasis),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.commonShare,
                      icon: const Icon(Icons.ios_share_rounded),
                      onPressed: _share,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _chrome ? 0 : -220,
              left: 0,
              right: 0,
              child: (m.content?.isNotEmpty == true || total > 1)
                  ? GlassSurface(
                      border: false,
                      padding: EdgeInsets.fromLTRB(
                          16, 12, 16, MediaQuery.paddingOf(context).bottom + 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m.content?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(m.content!,
                                  style: const TextStyle(
                                      fontSize: 15, height: 1.4)),
                            ),
                          if (total > 1)
                            SizedBox(
                              height: 48,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: total,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (context, i) => _Thumb(
                                  message: widget.images[i],
                                  selected: i == _index,
                                  onTap: () => _pages.animateToPage(i,
                                      duration:
                                          const Duration(milliseconds: 250),
                                      curve: Curves.easeOutCubic),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.future});

  final Future<Uint8List?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: future,
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
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        );
      },
    );
  }
}

/// Náhled v pásu dole — stačí malý náhled, který přišel uvnitř E2E zprávy.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.message,
    required this.selected,
    required this.onTap,
  });

  final Message message;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = message.attachment?.thumbnail;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? SepotColors.ember : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: selected ? 1 : 0.6,
            child: thumb != null
                ? Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
                : const ColoredBox(color: SepotColors.surfaceVariant),
          ),
        ),
      ),
    );
  }
}
