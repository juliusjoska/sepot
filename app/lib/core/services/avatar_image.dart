import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sepot/core/services/image_processor.dart';

/// Strana profilové fotky v pixelech — víc se v appce nikde nezobrazí.
const avatarSide = 256;

/// Vybranou fotku otočí podle EXIF, ořízne na středový čtverec, zmenší
/// a znovu zakóduje do JPEG bez metadat (EXIF, GPS, model telefonu).
/// Null = obrázek nejde přečíst.
Future<Uint8List?> prepareAvatarJpeg(Uint8List input) => Isolate.run(() {
      final img.Image? decoded;
      try {
        decoded = img.decodeImage(input);
      } on Object {
        // Dekodéry na poškozených datech háží místo null.
        return null;
      }
      if (decoded == null) return null;
      final upright = img.bakeOrientation(decoded);
      final side = math.min(upright.width, upright.height);
      final square = img.copyCrop(
        upright,
        x: (upright.width - side) ~/ 2,
        y: (upright.height - side) ~/ 2,
        width: side,
        height: side,
      );
      final small = img.copyResize(square,
          width: avatarSide,
          height: avatarSide,
          interpolation: img.Interpolation.average);
      ImageProcessor.stripMetadata(small);
      return Uint8List.fromList(img.encodeJpg(small, quality: 85));
    });
