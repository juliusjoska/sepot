import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/attachment_cipher.dart';
import 'package:sepot/core/storage/attachment_store.dart';
import 'package:sepot/models/attachment.dart';
import 'package:sepot/models/message.dart';

Uint8List randomBytes(int n) {
  final rng = Random(42);
  return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
}

void main() {
  group('AttachmentCipher', () {
    test('roundtrip malý i velký payload', () async {
      for (final size in [1, 4096, 1024 * 1024]) {
        final plaintext = randomBytes(size);
        final enc = await AttachmentCipher.encrypt(plaintext);

        expect(enc.key.length, 32);
        expect(enc.nonce.length, 12);
        expect(enc.blob.length, size + AttachmentCipher.tagLength);
        expect(enc.plaintextSize, size);
        // ciphertext nesmí obsahovat plaintext (triviální sanity)
        expect(enc.blob.sublist(0, size), isNot(equals(plaintext)));

        final dec = await AttachmentCipher.decrypt(
          blob: enc.blob,
          key: enc.key,
          nonce: enc.nonce,
          expectedDigest: enc.digest,
        );
        expect(dec, equals(plaintext));
      }
    });

    test('tamper blobu = AttachmentIntegrityException (digest)', () async {
      final enc = await AttachmentCipher.encrypt(randomBytes(1024));
      final tampered = Uint8List.fromList(enc.blob);
      tampered[100] ^= 0xFF;
      expect(
        () => AttachmentCipher.decrypt(
          blob: tampered,
          key: enc.key,
          nonce: enc.nonce,
          expectedDigest: enc.digest,
        ),
        throwsA(isA<AttachmentIntegrityException>()),
      );
    });

    test('podvržený digest = AttachmentIntegrityException', () async {
      final enc = await AttachmentCipher.encrypt(randomBytes(1024));
      final wrongDigest = Uint8List.fromList(enc.digest);
      wrongDigest[0] ^= 0x01;
      expect(
        () => AttachmentCipher.decrypt(
          blob: enc.blob,
          key: enc.key,
          nonce: enc.nonce,
          expectedDigest: wrongDigest,
        ),
        throwsA(isA<AttachmentIntegrityException>()),
      );
    });

    test('špatný klíč = AttachmentIntegrityException (GCM tag)', () async {
      final enc = await AttachmentCipher.encrypt(randomBytes(1024));
      final wrongKey = Uint8List.fromList(enc.key);
      wrongKey[5] ^= 0x01;
      expect(
        () => AttachmentCipher.decrypt(
          blob: enc.blob,
          key: wrongKey,
          nonce: enc.nonce,
          expectedDigest: enc.digest,
        ),
        throwsA(isA<AttachmentIntegrityException>()),
      );
    });

    test('každá příloha má unikátní klíč i nonce', () async {
      final a = await AttachmentCipher.encrypt(randomBytes(64));
      final b = await AttachmentCipher.encrypt(randomBytes(64));
      expect(a.key, isNot(equals(b.key)));
      expect(a.nonce, isNot(equals(b.nonce)));
    });
  });

  group('AttachmentStore', () {
    late Directory tmp;
    late AttachmentStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sepot-att-');
      store = AttachmentStore(dirOverride: tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('save/load/exists/delete', () async {
      const blobId = 'aabbccddeeff00112233445566778899';
      final blob = randomBytes(512);

      expect(await store.exists(blobId), isFalse);
      expect(await store.load(blobId), isNull);

      await store.save(blobId, blob);
      expect(await store.exists(blobId), isTrue);
      expect(await store.load(blobId), equals(blob));

      await store.delete(blobId);
      expect(await store.exists(blobId), isFalse);
    });

    test('neplatný blob_id (path traversal) se odmítne', () async {
      for (final evil in [
        '../../../etc/passwd',
        'AABBCCDDEEFF00112233445566778899', // velká písmena
        'aabbccddeeff001122334455667788', // krátké
        'aabbccddeeff00112233445566778899aa', // dlouhé
        'aabbccddeeff0011223344556677889g', // ne-hex
      ]) {
        expect(
          () => store.save(evil, randomBytes(8)),
          throwsArgumentError,
          reason: evil,
        );
      }
    });
  });

  group('AttachmentMeta + Message serializace', () {
    final meta = AttachmentMeta(
      blobId: 'aabbccddeeff00112233445566778899',
      keyB64: base64Encode(randomBytes(32)),
      nonceB64: base64Encode(randomBytes(12)),
      digestB64: base64Encode(randomBytes(32)),
      size: 12345,
      mime: 'image/jpeg',
      width: 1600,
      height: 900,
      thumbB64: base64Encode(randomBytes(100)),
      state: AttachmentTransferState.ready,
    );

    test('wire roundtrip nenese lokální stav', () {
      final wire = meta.toWire();
      expect(wire.containsKey('state'), isFalse);
      final back = AttachmentMeta.fromWire(wire);
      expect(back.blobId, meta.blobId);
      expect(back.keyB64, meta.keyB64);
      expect(back.size, meta.size);
      expect(back.state, AttachmentTransferState.pending);
    });

    test('lokální JSON roundtrip drží stav', () {
      final back = AttachmentMeta.fromJson(meta.toJson());
      expect(back.state, AttachmentTransferState.ready);
      expect(back.thumbB64, meta.thumbB64);
    });

    test('nesmyslná velikost z drátu se odmítne', () {
      final wire = meta.toWire()..['s'] = -1;
      expect(() => AttachmentMeta.fromWire(wire), throwsFormatException);
    });

    test('Message s přílohou přežije JSON roundtrip', () {
      final msg = Message.attachment(
        senderId: 'me',
        recipientId: 'you',
        attachment: meta,
        caption: 'popisek',
      );
      expect(msg.type, MessageType.image);
      final back = Message.fromJson(
          jsonDecode(jsonEncode(msg.toJson())) as Map<String, dynamic>);
      expect(back.attachment, isNotNull);
      expect(back.attachment!.blobId, meta.blobId);
      expect(back.attachment!.state, AttachmentTransferState.ready);
      expect(back.content, 'popisek');
      expect(back.type, MessageType.image);
    });
  });
}
