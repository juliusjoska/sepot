import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sepot/core/services/avatar_image.dart';
import 'package:sepot/models/avatar_ref.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/identity.dart';

/// Odkaz na fotku přichází od protistrany v profilu — nesmí projít nic,
/// co by šlo zneužít (cizí cesta k blobu, klíč špatné délky).
void main() {
  final ref = AvatarRef(
    blobId: 'a' * 32,
    key: Uint8List(32),
    nonce: Uint8List(12),
    digest: Uint8List(32),
  );

  test('drát tam a zpět', () {
    final back = AvatarRef.fromWire(ref.toWire())!;
    expect(back.blobId, ref.blobId);
    expect(back.key, ref.key);
  });

  test('podvržený odkaz = null', () {
    expect(AvatarRef.fromWire(null), isNull);
    expect(AvatarRef.fromWire({...ref.toWire(), 'b': '../../etc/passwd'}),
        isNull);
    expect(AvatarRef.fromWire({...ref.toWire(), 'k': 'AAAA'}), isNull);
    expect(AvatarRef.fromWire({...ref.toWire(), 'd': 'nebase64!'}), isNull);
  });

  test('kontakt si fotku pamatuje přes uložení', () {
    final contact = Contact(
      displayName: 'Alice',
      publicIdentity: PublicIdentity(
        displayName: 'Alice',
        identityKey: Uint8List.fromList(List.filled(33, 5)),
        createdAt: DateTime(2026, 9, 1),
      ),
      addedAt: DateTime(2026, 9, 1),
      avatar: ref,
    );
    final back = Contact.fromJson(contact.toJson());
    expect(back.avatar?.blobId, ref.blobId);
  });

  test('fotka se ořízne na čtverec, zmenší a ztratí EXIF', () async {
    final photo = img.Image(width: 800, height: 400)
      ..exif.imageIfd['Make'] = 'TestPhone';
    final jpeg = Uint8List.fromList(img.encodeJpg(photo));
    expect(img.decodeJpgExif(jpeg)?.imageIfd['Make'], isNotNull);

    final out = await prepareAvatarJpeg(jpeg);
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, avatarSide);
    expect(decoded.height, avatarSide);
    expect(img.decodeJpgExif(out)?.imageIfd['Make'], isNull);
  });

  test('nečitelný obrázek = null', () async {
    expect(await prepareAvatarJpeg(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
