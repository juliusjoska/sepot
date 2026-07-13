/// Příprava obrázků před odesláním.
///
/// Každá fotka se před šifrováním RE-ENKÓDUJE (resize na max 2048 px,
/// JPEG q80) — tím se zahodí VŠECHNA metadata včetně EXIF/GPS (privacy:
/// poloha focení nesmí odjet ani E2E kanálem, protistrana ji nemá co
/// vidět). PNG (screenshoty, průhlednost) zůstává PNG, GIF se posílá
/// beze změny (animace; EXIF u něj nehrozí).
///
/// Náhled (JPEG ≤ 48 KiB) jede přímo uvnitř E2E plaintextu zprávy —
/// příjemce vidí obrázek okamžitě, bez čekání na download blobu.
library;

import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.mime,
    required this.width,
    required this.height,
    required this.thumbnailJpeg,
  });

  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
  final Uint8List thumbnailJpeg;
}

class ImageProcessor {
  ImageProcessor._();

  static const int maxDimension = 2048;
  static const int jpegQuality = 80;
  static const int thumbDimension = 320;

  /// Náhled musí bezpečně projet obálkou (limit 256 KiB na CELOU
  /// sealed-sender obálku) — držet výrazně pod tím.
  static const int thumbMaxBytes = 48 * 1024;

  /// Zpracuje obrázek v izolátu (dekódování megapixelů by blokovalo UI).
  /// Vrací null, když bajty nejsou dekódovatelný obrázek — volající je
  /// pak pošle jako dokument.
  static Future<ProcessedImage?> process(
    Uint8List original, {
    String? mimeHint,
  }) {
    return Isolate.run(() {
      final decoded = img.decodeImage(original);
      if (decoded == null) return null;

      // GIF beze změny — re-encode by zabil animaci
      if (mimeHint == 'image/gif') {
        return ProcessedImage(
          bytes: original,
          mime: 'image/gif',
          width: decoded.width,
          height: decoded.height,
          thumbnailJpeg: _thumbnail(decoded),
        );
      }

      var image = img.bakeOrientation(decoded);
      if (max(image.width, image.height) > maxDimension) {
        image = image.width >= image.height
            ? img.copyResize(image, width: maxDimension)
            : img.copyResize(image, height: maxDimension);
      }

      // PNG s REÁLNOU průhledností zůstává PNG (JPEG alfa kanál neumí,
      // a re-encode PNG→PNG metadata stejně zahodí); vše ostatní JPEG q80.
      // Samotný alfa kanál nestačí — plně krytý RGBA PNG (screenshot,
      // canvas render z editoru fotek) je jako JPEG několikanásobně menší.
      final keepPng = mimeHint == 'image/png' && _hasTransparency(decoded);
      final bytes = keepPng
          ? Uint8List.fromList(img.encodePng(image))
          : Uint8List.fromList(img.encodeJpg(image, quality: jpegQuality));

      return ProcessedImage(
        bytes: bytes,
        mime: keepPng ? 'image/png' : 'image/jpeg',
        width: image.width,
        height: image.height,
        thumbnailJpeg: _thumbnail(image),
      );
    });
  }

  /// Má obraz aspoň jeden ne-plně-krytý pixel? Běží v izolátu spolu se
  /// zbytkem zpracování, O(n) sken je proti dekódu/enkódu zanedbatelný.
  static bool _hasTransparency(img.Image image) {
    if (image.numChannels < 4) return false;
    for (final pixel in image) {
      if (pixel.a < pixel.maxChannelValue) return true;
    }
    return false;
  }

  static Uint8List _thumbnail(img.Image source) {
    var thumb = max(source.width, source.height) > thumbDimension
        ? (source.width >= source.height
            ? img.copyResize(source, width: thumbDimension)
            : img.copyResize(source, height: thumbDimension))
        : source;
    // JPEG náhled nemá alfu — průhlednost složit na tmavé pozadí
    if (thumb.numChannels == 4) {
      final flat = img.Image(width: thumb.width, height: thumb.height);
      img.fill(flat, color: img.ColorRgb8(20, 20, 31));
      img.compositeImage(flat, thumb);
      thumb = flat;
    }
    var quality = 70;
    var encoded = Uint8List.fromList(img.encodeJpg(thumb, quality: quality));
    // Náhled je jen placeholder, než dorazí ostrá fotka — kvalitu držíme
    // rozumně (min 40), radši menší rozměr než rozsypaný obraz.
    while (encoded.length > thumbMaxBytes && quality > 40) {
      quality -= 10;
      encoded = Uint8List.fromList(img.encodeJpg(thumb, quality: quality));
    }
    return encoded;
  }
}
