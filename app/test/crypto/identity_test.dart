import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/mnemonic.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/models/identity.dart';

/// S1/S2 testy nad reálným libsignal backendem (nativní knihovna).
void main() {
  setUpAll(() async {
    await SepotCrypto.init();
  });

  group('S1: fingerprint a ID z klíče', () {
    test('fingerprint má 52 znaků Crockford base32, SEP- zkratka 14', () async {
      final identity = await LocalIdentity.create('Alice');
      expect(identity.fingerprint.display, hasLength(52));
      expect(identity.sepotId, startsWith('SEP-'));
      expect(identity.sepotId, hasLength(14));
      expect(identity.id, identity.fingerprint.display);
    });

    test('fingerprint je deterministický: stejný klíč → stejné ID', () async {
      final identity = await LocalIdentity.create('A');
      final again = SepotFingerprint.ofPublicKey(identity.identityPublicKey);
      expect(again, identity.fingerprint);
    });

    test('KAT: známý pubkey → známý fingerprint (BLAKE2b-256 + Crockford)',
        () {
      // Pevný "pubkey" (33 B, type byte 0x05 + 32 B vzestupně) — nezávislý
      // na libsignal, fixuje hash i base32 vrstvu proti tiché změně
      final pubkey = Uint8List.fromList(
        [0x05, ...List.generate(32, (i) => i)],
      );
      final fp = SepotFingerprint.ofPublicKey(pubkey);
      expect(fp.display, hasLength(52));
      // KAT hodnota vygenerovaná při zavedení S1 (2026-07-03) — pokud se
      // změní, změnil se hash vstup/algoritmus a VŠECHNA ID uživatelů
      expect(
        fp.display,
        '2TFMWYYW4MRZH3BR8QCWQZVVM20EPFEP40N91S6J9HXW1GGHATRG',
      );
    });

    test('klíče: privátní 32 B, veřejný 33 B, derivace sedí', () {
      final keys = SepotCrypto.generateIdentityKeys();
      expect(keys.privateKey, hasLength(32));
      expect(keys.publicKey, hasLength(33));
      expect(SepotCrypto.derivePublicKey(keys.privateKey), keys.publicKey);
    });

    test('serializovaný privátní klíč je clamping-stabilní', () {
      // deserialize→serialize musí být identita na už serializovaných
      // bajtech — na tom stojí mnemonic roundtrip (MASTER-DESIGN §3, F-3)
      for (var i = 0; i < 20; i++) {
        final keys = SepotCrypto.generateIdentityKeys();
        final roundtrip = SepotCrypto.derivePublicKey(keys.privateKey);
        expect(roundtrip, keys.publicKey);
        final mnemonicBack = SepotMnemonic.decode(
          SepotMnemonic.encode(keys.privateKey),
        );
        expect(mnemonicBack, keys.privateKey);
        expect(SepotCrypto.derivePublicKey(mnemonicBack), keys.publicKey);
      }
    });
  });

  group('S2: mnemonic recovery', () {
    test('recover z mnemonic obnoví identický klíč i fingerprint', () async {
      final original = await LocalIdentity.create('Alice');
      final words = original.mnemonic;
      expect(words, hasLength(24));

      final recovered = await LocalIdentity.recover(
        mnemonicWords: words,
        displayName: 'Alice (obnoveno)',
      );
      expect(recovered.identityPrivateKey, original.identityPrivateKey);
      expect(recovered.identityPublicKey, original.identityPublicKey);
      expect(recovered.fingerprint, original.fingerprint);
    });

    test('překlep v mnemonic → MnemonicInvalidError, ne tichá jiná identita',
        () async {
      final original = await LocalIdentity.create('Alice');
      final words = [...original.mnemonic]..[3] = 'abandon';
      expect(
        () => LocalIdentity.recover(
          mnemonicWords: words,
          displayName: 'x',
        ),
        throwsA(isA<MnemonicInvalidError>()),
      );
    });
  });

  group('Serializace', () {
    test('LocalIdentity JSON roundtrip (v2)', () async {
      final identity = await LocalIdentity.create('Alice');
      final back = LocalIdentity.fromJson(identity.toJson());
      expect(back.identityPrivateKey, identity.identityPrivateKey);
      expect(back.fingerprint, identity.fingerprint);
      expect(back.displayName, 'Alice');
    });

    test('starý (před-libsignal) JSON → FormatException', () {
      expect(
        () => LocalIdentity.fromJson({
          'id': 'uuid-v4-neco',
          'displayName': 'Starý formát',
        }),
        throwsFormatException,
      );
    });

    test('sepot://add/ share link roundtrip', () async {
      final identity = await LocalIdentity.create('Čeněk Šťastný');
      final link = identity.publicIdentity.toShareString();
      expect(link, startsWith('sepot://add/'));

      final parsed = PublicIdentity.fromShareString(link);
      expect(parsed, isNotNull);
      expect(parsed!.displayName, 'Čeněk Šťastný');
      expect(parsed.fingerprint, identity.fingerprint);
      expect(parsed.identityKey, identity.identityPublicKey);
    });

    test('fromShareString: odpad → null, ne výjimka', () {
      expect(PublicIdentity.fromShareString('nesmysl'), isNull);
      expect(PublicIdentity.fromShareString('sepot://add/%%%'), isNull);
      expect(PublicIdentity.fromShareString(''), isNull);
    });
  });
}
