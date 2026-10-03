import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sepot/core/services/image_processor.dart';

/// Fotka z telefonu nese v EXIF polohu (GPS), model telefonu a čas focení.
/// Nic z toho nesmí odejít — ani v odeslané fotce, ani v jejím náhledu.
void main() {
  Uint8List photoWithGps({int width = 1200, int height = 800}) {
    final photo = img.Image(width: width, height: height);
    photo.exif.imageIfd['Make'] = 'TestPhone';
    photo.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(50, 1);
    return Uint8List.fromList(img.encodeJpg(photo));
  }

  bool hasExif(Uint8List jpeg) {
    final exif = img.decodeJpgExif(jpeg);
    return exif != null &&
        (exif.imageIfd['Make'] != null || exif.gpsIfd['GPSLatitude'] != null);
  }

  test('vstup testu opravdu nese EXIF i GPS', () {
    expect(hasExif(photoWithGps()), isTrue);
  });

  test('odeslaná fotka je bez EXIF a GPS', () async {
    final out =
        await ImageProcessor.process(photoWithGps(), mimeHint: 'image/jpeg');
    expect(hasExif(out!.bytes), isFalse);
  });

  test('zmenšovaná fotka je bez EXIF a GPS', () async {
    final out = await ImageProcessor.process(
        photoWithGps(width: 4000, height: 3000),
        mimeHint: 'image/jpeg');
    expect(hasExif(out!.bytes), isFalse);
  });

  test('náhled je bez EXIF a GPS', () async {
    final out =
        await ImageProcessor.process(photoWithGps(), mimeHint: 'image/jpeg');
    expect(hasExif(out!.thumbnailJpeg), isFalse);
  });

  test('JPEG umíme zbavit metadat', () async {
    expect(await ImageProcessor.canStripMetadata(photoWithGps()), isTrue);
  });

  // Hlavička kontejneru HEIF z iPhonu; knihovna ho nedekóduje, takže by
  // fotka odešla v originále — UI se musí zeptat.
  test('HEIC metadat zbavit neumíme', () async {
    final heic = Uint8List.fromList([
      0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0,
      ...'mif1heic'.codeUnits, ...List.filled(64, 0),
    ]);
    expect(await ImageProcessor.canStripMetadata(heic), isFalse);
  });
}
