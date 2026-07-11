import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

// Ověřuje jádro zálohy: HKDF z privátního klíče + AES-GCM roundtrip a že
// cizí klíč (jiná identita) zálohu nedešifruje. (BackupService.import/export
// volá storage = native; tady testujeme krypto vrstvu izolovaně.)
Future<SecretKey> derive(Uint8List pk) => Hkdf(hmac: Hmac.sha256(), outputLength: 32)
    .deriveKey(secretKey: SecretKey(pk), nonce: utf8.encode('sepot-backup-salt-v1'), info: utf8.encode('sepot-backup-v1'));

void main() {
  test('záloha: AES-GCM roundtrip klíčem odvozeným z identity', () async {
    final pk = Uint8List.fromList(List.generate(32, (i) => i));
    final key = await derive(pk);
    final nonce = Uint8List.fromList(List.filled(12, 7));
    final msg = utf8.encode('{"v":1,"conversations":[]}');
    final box = await AesGcm.with256bits().encrypt(msg, secretKey: key, nonce: nonce);
    final plain = await AesGcm.with256bits().decrypt(box, secretKey: key);
    expect(utf8.decode(plain), '{"v":1,"conversations":[]}');
  });

  test('cizí identita zálohu nedešifruje', () async {
    final key = await derive(Uint8List.fromList(List.filled(32, 1)));
    final other = await derive(Uint8List.fromList(List.filled(32, 2)));
    final box = await AesGcm.with256bits().encrypt(utf8.encode('tajne'),
        secretKey: key, nonce: Uint8List.fromList(List.filled(12, 3)));
    expect(() => AesGcm.with256bits().decrypt(box, secretKey: other),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });
}
