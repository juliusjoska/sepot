import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/services/image_processor.dart';
import 'package:sepot/core/theme/app_theme.dart';

/// Výsledek náhledu: co poslat. `null` z Navigatoru = uživatel zrušil.
class PhotoPreviewResult {
  const PhotoPreviewResult({
    required this.bytes,
    required this.fileName,
    required this.mime,
    this.caption,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mime;
  final String? caption;
}

/// Náhled fotky před odesláním — nic neodchází bez potvrzení.
///
/// Úpravy: kreslení prstem, text na fotce (tažení prstem, tap = upravit),
/// otočení o 90°. Tahy a texty žijí v relativních souřadnicích [0..1]
/// zobrazeného (already otočeného) obrazu, takže finální render v plném
/// rozlišení je jen přeškálování. Bez úprav odchází původní bajty —
/// EXIF/GPS z nich stáhne ImageProcessor při odeslání.
class PhotoPreviewScreen extends StatefulWidget {
  const PhotoPreviewScreen({
    super.key,
    required this.bytes,
    required this.fileName,
    this.mime,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mime;

  @override
  State<PhotoPreviewScreen> createState() => _PhotoPreviewScreenState();
}

enum _EditMode { none, draw }

class _Stroke {
  _Stroke({required this.color, required this.width, required this.points});

  final Color color;

  /// Šířka tahu jako podíl šířky obrazu (přežije škálování).
  final double width;
  final List<Offset> points; // relativní [0..1]
}

class _OverlayText {
  _OverlayText({
    required this.text,
    required this.color,
    required this.position,
  });

  String text;
  Color color;

  /// Střed textu, relativně [0..1] k zobrazenému obrazu.
  Offset position;

  /// Výška fontu jako podíl šířky obrazu.
  static const double fontScale = 0.05;
}

class _PhotoPreviewScreenState extends State<PhotoPreviewScreen> {
  static const _palette = <Color>[
    Colors.white,
    Colors.black,
    SepotColors.ember,
    SepotColors.sage,
    SepotColors.mist,
    SepotColors.warning,
    SepotColors.error,
  ];

  final _captionController = TextEditingController();
  ui.Image? _image;
  _EditMode _mode = _EditMode.none;
  Color _color = Colors.white;
  int _quarterTurns = 0;
  final List<_Stroke> _strokes = [];
  final List<_OverlayText> _texts = [];
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _image = frame.image);
      } else {
        frame.image.dispose();
      }
    } catch (_) {
      // Nedekódovatelné bajty (picker by je dát neměl) — zpátky bez
      // odeslání, ať uživatel nezůstane viset na věčném spinneru.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.photoPreviewDecodeFailed)),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _image?.dispose();
    super.dispose();
  }

  bool get _edited =>
      _strokes.isNotEmpty || _texts.isNotEmpty || _quarterTurns % 4 != 0;

  /// Otočení o 90° po směru: relativní bod (x, y) → (1 − y, x).
  void _rotate() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      for (final s in _strokes) {
        for (var i = 0; i < s.points.length; i++) {
          s.points[i] = Offset(1 - s.points[i].dy, s.points[i].dx);
        }
      }
      for (final t in _texts) {
        t.position = Offset(1 - t.position.dy, t.position.dx);
      }
    });
  }

  void _undo() {
    setState(() {
      if (_strokes.isNotEmpty) _strokes.removeLast();
    });
  }

  Future<void> _addText() async {
    final text = await _editTextDialog(initial: '');
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _texts.add(_OverlayText(
        text: text.trim(),
        color: _color,
        position: const Offset(0.5, 0.5),
      ));
    });
  }

  Future<void> _editText(_OverlayText item) async {
    final text = await _editTextDialog(initial: item.text, removable: true);
    if (text == null) return; // zrušeno
    setState(() {
      if (text.trim().isEmpty) {
        _texts.remove(item); // „Odebrat" vrací prázdný řetězec
      } else {
        item.text = text.trim();
        item.color = _color;
      }
    });
  }

  Future<String?> _editTextDialog({
    required String initial,
    bool removable = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextEditDialog(initial: initial, removable: removable),
    );
  }

  Future<void> _send() async {
    if (_rendering) return;
    setState(() => _rendering = true);
    try {
      final caption = _captionController.text.trim();
      final result = _edited
          ? PhotoPreviewResult(
              // Render je vždy PNG — mime říká pravdu o bajtech. Finální
              // formát rozhodne ImageProcessor (bez průhlednosti → JPEG).
              bytes: await _renderEdited(),
              fileName: 'photo.png',
              mime: 'image/png',
              caption: caption.isEmpty ? null : caption,
            )
          : PhotoPreviewResult(
              bytes: widget.bytes,
              fileName: widget.fileName,
              mime: widget.mime,
              caption: caption.isEmpty ? null : caption,
            );
      if (mounted) Navigator.pop(context, result);
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  /// Vykreslí otočený obraz + tahy + texty v plném rozlišení (strop 2048 px
  /// po delší straně — dál by to ImageProcessor stejně zmenšil).
  Future<Uint8List> _renderEdited() async {
    final src = _image!;
    final rotated = _quarterTurns.isOdd;
    final srcW = src.width.toDouble();
    final srcH = src.height.toDouble();
    final scale = math.min(
      1.0,
      ImageProcessor.maxDimension / math.max(srcW, srcH),
    );
    final outW = (rotated ? srcH : srcW) * scale;
    final outH = (rotated ? srcW : srcH) * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.save();
    switch (_quarterTurns % 4) {
      case 1:
        canvas.translate(outW, 0);
        canvas.rotate(math.pi / 2);
      case 2:
        canvas.translate(outW, outH);
        canvas.rotate(math.pi);
      case 3:
        canvas.translate(0, outH);
        canvas.rotate(3 * math.pi / 2);
    }
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, srcW, srcH),
      Rect.fromLTWH(0, 0, srcW * scale, srcH * scale),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    _paintOverlay(canvas, Size(outW, outH));

    final picture = recorder.endRecording();
    final image = await picture.toImage(outW.round(), outH.round());
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Tahy a texty — společná cesta pro živý náhled i finální render,
  /// aby odeslaná fotka vypadala přesně jako náhled.
  void _paintOverlay(Canvas canvas, Size size) {
    for (final stroke in _strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final points =
          stroke.points.map((p) => Offset(p.dx * size.width, p.dy * size.height));
      final path = Path()..addPolygon(points.toList(), false);
      canvas.drawPath(path, paint);
    }
    for (final item in _texts) {
      final painter = _textPainter(item, size);
      final center = Offset(
        item.position.dx * size.width,
        item.position.dy * size.height,
      );
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  TextPainter _textPainter(_OverlayText item, Size size) {
    return TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          fontFamily: kFontSans,
          color: item.color,
          fontSize: _OverlayText.fontScale * size.width,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(blurRadius: 4, color: Colors.black54),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final image = _image;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(l10n),
            Expanded(
              child: image == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SepotColors.ember,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) =>
                          _buildCanvas(image, constraints),
                    ),
            ),
            if (_mode == _EditMode.draw || _texts.isNotEmpty)
              _buildPalette(),
            _buildBottomBar(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: l10n.commonCancel,
          onPressed: () => Navigator.pop(context),
        ),
        const Spacer(),
        if (_strokes.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white),
            tooltip: l10n.photoPreviewUndo,
            onPressed: _undo,
          ),
        IconButton(
          icon: const Icon(Icons.rotate_90_degrees_cw_outlined,
              color: Colors.white),
          tooltip: l10n.photoPreviewRotate,
          onPressed: _image == null ? null : _rotate,
        ),
        IconButton(
          icon: Icon(
            Icons.gesture,
            color: _mode == _EditMode.draw ? SepotColors.ember : Colors.white,
          ),
          tooltip: l10n.photoPreviewDraw,
          onPressed: _image == null
              ? null
              : () => setState(() {
                    _mode = _mode == _EditMode.draw
                        ? _EditMode.none
                        : _EditMode.draw;
                  }),
        ),
        IconButton(
          icon: const Icon(Icons.title, color: Colors.white),
          tooltip: l10n.photoPreviewAddText,
          onPressed: _image == null ? null : _addText,
        ),
      ],
    );
  }

  Widget _buildCanvas(ui.Image image, BoxConstraints constraints) {
    final rotated = _quarterTurns.isOdd;
    final iw = (rotated ? image.height : image.width).toDouble();
    final ih = (rotated ? image.width : image.height).toDouble();
    final scale = math.min(
      constraints.maxWidth / iw,
      constraints.maxHeight / ih,
    );
    final size = Size(iw * scale, ih * scale);

    Offset toRelative(Offset local) =>
        Offset(local.dx / size.width, local.dy / size.height);

    return Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              // RawImage kreslí už dekódovaný _image — Image.memory by tytéž
              // bajty dekódoval podruhé (u 2048² ~16 MB RGBA navíc).
              child: RotatedBox(
                quarterTurns: _quarterTurns,
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _mode == _EditMode.draw
                    ? (d) => setState(() {
                          _strokes.add(_Stroke(
                            color: _color,
                            width: 0.008,
                            points: [toRelative(d.localPosition)],
                          ));
                        })
                    : null,
                onPanUpdate: _mode == _EditMode.draw
                    ? (d) => setState(() {
                          _strokes.last.points.add(toRelative(d.localPosition));
                        })
                    : null,
                child: CustomPaint(
                  painter: _OverlayPainter(
                    strokes: List.of(_strokes),
                    paintAll: _paintOverlay,
                  ),
                ),
              ),
            ),
            // Texty mají vlastní gesta (drag + tap), proto jedou nad
            // kreslicí vrstvou jako neviditelné hit-oblasti.
            for (final item in _texts)
              Positioned(
                left: item.position.dx * size.width - size.width / 2,
                top: item.position.dy * size.height - 24,
                width: size.width,
                height: 48,
                child: GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onTap: () => _editText(item),
                  onPanUpdate: (d) => setState(() {
                    final next = item.position + toRelative(d.delta);
                    item.position = Offset(
                      next.dx.clamp(0.02, 0.98),
                      next.dy.clamp(0.02, 0.98),
                    );
                  }),
                  child: Center(
                    child: Container(
                      // Neviditelný úchop kolem textu, ať se dá chytit prstem
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      color: Colors.transparent,
                      child: Opacity(
                        opacity: 0,
                        child: Text(
                          item.text,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: kFontSans,
                            fontSize: _OverlayText.fontScale * size.width,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPalette() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final color in _palette)
            GestureDetector(
              onTap: () => setState(() => _color = color),
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == color
                        ? SepotColors.textPrimary
                        : SepotColors.border,
                    width: _color == color ? 2.5 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _captionController,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(color: SepotColors.textPrimary),
              decoration: InputDecoration(
                counterText: '',
                filled: false,
                hintText: l10n.photoPreviewCaptionHint,
                hintStyle: const TextStyle(color: SepotColors.textMuted),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: SepotColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: SepotColors.ember),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: SepotColors.ember,
                foregroundColor: SepotColors.emberInk,
              ),
              tooltip: l10n.photoPreviewSend,
              onPressed: _image == null || _rendering ? null : _send,
              icon: _rendering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SepotColors.emberInk,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog textu na fotce — vlastní widget kvůli životnímu cyklu
/// TextEditingControlleru (dispose patří do State, ne za showDialog).
class _TextEditDialog extends StatefulWidget {
  const _TextEditDialog({required this.initial, required this.removable});

  final String initial;
  final bool removable;

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.photoPreviewTextDialogTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        if (widget.removable)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(
              context.l10n.photoPreviewRemoveText,
              style: const TextStyle(color: SepotColors.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.l10n.commonOk),
        ),
      ],
    );
  }
}

/// Živý náhled úprav — deleguje na tutéž kreslicí rutinu jako finální
/// render, jen v rozlišení obrazovky.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.strokes, required this.paintAll});

  final List<_Stroke> strokes;
  final void Function(Canvas canvas, Size size) paintAll;

  @override
  void paint(Canvas canvas, Size size) => paintAll(canvas, size);

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => true;
}
