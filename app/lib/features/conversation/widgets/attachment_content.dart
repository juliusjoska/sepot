/// Obsah bublin s přílohou — obrázek (thumbnail + stav) a dokument
/// (karta s názvem/velikostí). Plné rozlišení se dešifruje až ve vieweru;
/// v chatu stačí inline náhled, který dorazil UVNITŘ E2E zprávy.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/features/conversation/image_viewer_screen.dart';
import 'package:sepot/models/attachment.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:share_plus/share_plus.dart';

String formatBytes(AppLocalizations l10n, int bytes) {
  if (bytes < 1024) return l10n.attachmentSizeBytes(bytes);
  if (bytes < 1024 * 1024) {
    return l10n.attachmentSizeKb((bytes / 1024).toStringAsFixed(0));
  }
  return l10n.attachmentSizeMb((bytes / (1024 * 1024)).toStringAsFixed(1));
}

/// Cache dešifrovaných plných obrázků (blob_id → bajty), ať se nedešifruje
/// při každém překreslení seznamu. Prostý strop, nejstarší se zahazují.
final _fullImageCache = <String, Uint8List>{};
const _fullImageCacheMax = 30;

void _cachePut(String blobId, Uint8List bytes) {
  _fullImageCache.remove(blobId);
  _fullImageCache[blobId] = bytes;
  while (_fullImageCache.length > _fullImageCacheMax) {
    _fullImageCache.remove(_fullImageCache.keys.first);
  }
}

/// Obrázková příloha: náhled + overlay podle stavu přenosu.
class ImageAttachmentContent extends ConsumerWidget {
  const ImageAttachmentContent({
    super.key,
    required this.contactId,
    required this.message,
  });

  final String contactId;
  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = message.attachment!;
    final thumb = meta.thumbnail;

    final aspect = (meta.width != null &&
            meta.height != null &&
            meta.width! > 0 &&
            meta.height! > 0)
        ? meta.width! / meta.height!
        : 4 / 3;

    return GestureDetector(
      onTap: switch (meta.state) {
        AttachmentTransferState.ready => () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImageViewerScreen(message: message),
              ),
            );
          },
        AttachmentTransferState.failed => () => ref
            .read(conversationsProvider.notifier)
            .retryAttachmentDownload(contactId, message),
        _ => null,
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: aspect.clamp(0.5, 2.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Náhled jako podklad/placeholder (rozmazaný, ne kostičkovaný).
              // Klíč podle blob_id — jinak ListView recykluje widget a
              // s gaplessPlayback ukáže náhled PŘEDCHOZÍ fotky.
              if (thumb != null)
                Image.memory(thumb,
                    key: ValueKey('thumb-${meta.blobId}'),
                    fit: BoxFit.cover,
                    gaplessPlayback: true)
              else
                const ColoredBox(
                  color: SepotColors.surfaceVariant,
                  child: Icon(Icons.image_outlined,
                      size: 48, color: SepotColors.textMuted),
                ),
              // Jakmile je blob stažený, překryj OSTROU plnou fotkou.
              // Klíč podle blob_id, ať se stav nedědí z jiné fotky.
              if (meta.state == AttachmentTransferState.ready)
                _FullImage(
                    key: ValueKey('full-${meta.blobId}'),
                    contactId: contactId,
                    message: message),
              if (meta.state != AttachmentTransferState.ready)
                ColoredBox(
                  color: Colors.black45,
                  child: Center(child: _stateIndicator(context, meta.state)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stateIndicator(BuildContext context, AttachmentTransferState state) {
    return switch (state) {
      AttachmentTransferState.downloading ||
      AttachmentTransferState.pending =>
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        ),
      AttachmentTransferState.failed => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, color: Colors.white, size: 32),
            const SizedBox(height: 4),
            Text(
              context.l10n.attachmentDownloadFailedTapToRetry,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      AttachmentTransferState.ready => const SizedBox.shrink(),
    };
  }
}

/// Ostrá plná fotka do bubliny (stav ready). Dešifruje blob do paměti
/// s cache; než je hotová, prosvítá náhled pod ní (žádné kostičky).
class _FullImage extends ConsumerStatefulWidget {
  const _FullImage(
      {super.key, required this.contactId, required this.message});

  final String contactId;
  final Message message;

  @override
  ConsumerState<_FullImage> createState() => _FullImageState();
}

class _FullImageState extends ConsumerState<_FullImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FullImage old) {
    super.didUpdateWidget(old);
    // Kdyby se widget přece jen recykloval na jinou fotku (jiný blob_id),
    // zahoď staré bajty a načti čerstvě — žádné zděděné náhledy.
    if (old.message.attachment!.blobId != widget.message.attachment!.blobId) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final blobId = widget.message.attachment!.blobId;
    final cached = _fullImageCache[blobId];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    final bytes = await ref
        .read(messagingServiceProvider)
        .loadDecryptedAttachment(widget.message);
    if (bytes != null) _cachePut(blobId, bytes);
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();
    return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
  }
}

/// Hlasová zpráva: play/pause, průběh a délka. Blob se dešifruje do paměti
/// až při prvním přehrání (plaintext audio nikdy nejde na disk).
class AudioAttachmentContent extends ConsumerStatefulWidget {
  const AudioAttachmentContent({
    super.key,
    required this.contactId,
    required this.message,
    required this.isMine,
  });

  final String contactId;
  final Message message;
  final bool isMine;

  @override
  ConsumerState<AudioAttachmentContent> createState() => _AudioState();
}

class _AudioState extends ConsumerState<AudioAttachmentContent> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _loading = false;
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration? _total;

  @override
  void initState() {
    super.initState();
    final dur = widget.message.attachment!.durationMs;
    _total = dur != null ? Duration(milliseconds: dur) : null;
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _total = d);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    final meta = widget.message.attachment!;
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_pos > Duration.zero && _pos < (_total ?? Duration.zero)) {
      await _player.resume();
      return;
    }
    setState(() => _loading = true);
    final bytes = await ref
        .read(messagingServiceProvider)
        .loadDecryptedAttachment(widget.message);
    if (!mounted) return;
    setState(() => _loading = false);
    if (bytes == null) return;
    await _player.play(BytesSource(bytes, mimeType: meta.mime));
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.message.attachment!;
    final ink = widget.isMine ? SepotColors.emberInk : SepotColors.textPrimary;
    final accent = widget.isMine ? SepotColors.emberInk : SepotColors.ember;

    if (meta.state != AttachmentTransferState.ready) {
      return SizedBox(
        width: 200,
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              meta.state == AttachmentTransferState.failed
                  ? context.l10n.attachmentDownloadFailed
                  : context.l10n.attachmentDownloading,
              style: TextStyle(color: ink, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final total = _total ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      width: 210,
      child: Row(
        children: [
          GestureDetector(
            onTap: _loading ? null : _toggle,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: accent),
                    )
                  : Icon(_playing ? Icons.pause : Icons.play_arrow,
                      color: accent, size: 24),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: ink.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.mic, size: 13, color: ink.withValues(alpha: .6)),
                    Text(
                      _playing || _pos > Duration.zero
                          ? _fmt(_pos)
                          : _fmt(total),
                      style: TextStyle(
                          fontSize: 11, color: ink.withValues(alpha: .8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dokument: karta s ikonou, názvem a velikostí. Klepnutí (stav ready)
/// dešifruje do paměti a otevře systémový share sheet — plaintext se na
/// disk dostane jen do cache sdílení (spravuje OS), nikdy do galerie.
class DocumentAttachmentContent extends ConsumerStatefulWidget {
  const DocumentAttachmentContent({
    super.key,
    required this.contactId,
    required this.message,
  });

  final String contactId;
  final Message message;

  @override
  ConsumerState<DocumentAttachmentContent> createState() =>
      _DocumentAttachmentContentState();
}

class _DocumentAttachmentContentState
    extends ConsumerState<DocumentAttachmentContent> {
  bool _opening = false;

  Future<void> _open() async {
    final meta = widget.message.attachment!;
    final l10n = context.l10n;
    setState(() => _opening = true);
    try {
      final bytes = await ref
          .read(messagingServiceProvider)
          .loadDecryptedAttachment(widget.message);
      if (bytes == null) return;
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: meta.name ?? l10n.attachmentSharedFileFallbackName,
          mimeType: meta.mime,
        ),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(l10n.attachmentOpenFailed(describeError(l10n, e)))),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.message.attachment!;

    return InkWell(
      onTap: switch (meta.state) {
        AttachmentTransferState.ready => _opening ? null : _open,
        AttachmentTransferState.failed => () => ref
            .read(conversationsProvider.notifier)
            .retryAttachmentDownload(widget.contactId, widget.message),
        _ => null,
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _leadingIcon(meta.state),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    meta.name ?? context.l10n.commonFile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SepotColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta.state == AttachmentTransferState.failed
                        ? context.l10n.attachmentDownloadFailedTapToRetry
                        : formatBytes(context.l10n, meta.size),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SepotColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leadingIcon(AttachmentTransferState state) {
    const size = 38.0;
    if (_opening ||
        state == AttachmentTransferState.downloading ||
        state == AttachmentTransferState.pending) {
      return const SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: SepotColors.ember,
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SepotColors.ember.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        state == AttachmentTransferState.failed
            ? Icons.refresh_rounded
            : Icons.description_outlined,
        color: SepotColors.ember,
        size: 20,
      ),
    );
  }
}
