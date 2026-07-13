import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/models/attachment.dart';

/// Validace metadat přílohy z drátu — remote input od protistrany.
/// Vadný náhled nesmí shodit render bubliny, vadná krypto pole musí
/// zprávu zabít už při příjmu (ACK + zahodit), ne až při použití.
void main() {
  Map<String, dynamic> validWire() => {
        'bid': 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        'k': base64Encode(List.filled(32, 1)),
        'n': base64Encode(List.filled(12, 2)),
        'd': base64Encode(List.filled(32, 3)),
        's': 1024,
        'mime': 'image/jpeg',
      };

  test('validní wire projde a thumbnail dekóduje', () {
    final meta = AttachmentMeta.fromWire(
        {...validWire(), 'th': base64Encode([1, 2, 3])});
    expect(meta.thumbnail, [1, 2, 3]);
    expect(meta.key.length, 32);
  });

  test('vadný base64 náhled se zahodí, zpráva žije', () {
    final meta = AttachmentMeta.fromWire({...validWire(), 'th': '@@@!!'});
    expect(meta.thumbB64, isNull);
    expect(meta.thumbnail, isNull);
    expect(meta.blobId, validWire()['bid']);
  });

  test('vadná base64 krypto pole zprávu zabijí FormatException', () {
    for (final field in ['k', 'n', 'd']) {
      expect(
        () => AttachmentMeta.fromWire({...validWire(), field: 'ne base64!'}),
        throwsFormatException,
        reason: 'pole $field s nevalidní base64 musí hodit',
      );
    }
  });

  test('nesmyslná velikost hodí FormatException', () {
    expect(
      () => AttachmentMeta.fromWire({...validWire(), 's': 0}),
      throwsFormatException,
    );
    expect(
      () => AttachmentMeta.fromWire({...validWire(), 's': 600 * 1024 * 1024}),
      throwsFormatException,
    );
  });

  test('špatný typ pole hodí TypeError (poison cesta ACKuje)', () {
    expect(
      () => AttachmentMeta.fromWire({...validWire(), 'k': 42}),
      throwsA(isA<TypeError>()),
    );
  });
}
