import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart' show PrivateKey;
import 'package:sepot/core/crypto/group_admin.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';

/// Krypto jádro admin-signed skupin. Testuje kanonickou
/// serializaci (determinismus + nezáměnnost polí) a XEdDSA sign/verify.
///
/// Serializační testy jsou pure-Dart a běží všude. Sign/verify potřebuje
/// nativní libsignal (`liblibsignal_frb.so`) — v host `flutter test` bez ní
/// se skupina PŘESKOČÍ (stejně jako ostatní krypto testy; ostré ověření běží
/// na zařízení/CI s nativní knihovnou).
void main() {
  GroupAdminOp op({
    String gid = 'g-1',
    int epoch = 1,
    GroupAdminAction action = GroupAdminAction.add,
    String actor = 'fpA',
    List<String>? members,
    List<String>? admins,
    String name = 'Parta',
    Uint8List? prev,
  }) =>
      GroupAdminOp(
        gid: gid,
        epoch: epoch,
        action: action,
        actor: actor,
        members: members ?? ['fpB', 'fpA', 'fpC'],
        admins: admins ?? ['fpA'],
        name: name,
        prev: prev ?? Uint8List(0),
      );

  group('kanonická serializace', () {
    test('je deterministická a nezávislá na pořadí členů', () {
      final a = op(members: ['fpB', 'fpA', 'fpC']).canonicalBytes();
      final b = op(members: ['fpC', 'fpB', 'fpA']).canonicalBytes();
      expect(a, b, reason: 'setřídění rosteru → stejné bajty');
    });

    test('duplicitní člen roster neovlivní', () {
      final a = op(members: ['fpA', 'fpB', 'fpC']).canonicalBytes();
      final b = op(members: ['fpA', 'fpB', 'fpB', 'fpC']).canonicalBytes();
      expect(a, b);
    });

    test('přesun bajtů mezi poli změní podepisované bajty (délkový prefix)', () {
      // actor|name = "ab"|"c" vs "a"|"bc" — bez prefixu by konkatenace splynula
      final a = op(actor: 'ab', name: 'c').canonicalBytes();
      final b = op(actor: 'a', name: 'bc').canonicalBytes();
      expect(a, isNot(b));
    });

    test('typ operace je součást podpisu', () {
      final a = op(action: GroupAdminAction.add).canonicalBytes();
      final b = op(action: GroupAdminAction.remove).canonicalBytes();
      expect(a, isNot(b));
    });

    test('epocha, gid, admini a jméno mění bajty', () {
      final base = op().canonicalBytes();
      expect(op(epoch: 2).canonicalBytes(), isNot(base));
      expect(op(gid: 'g-2').canonicalBytes(), isNot(base));
      expect(op(admins: ['fpA', 'fpB']).canonicalBytes(), isNot(base));
      expect(op(name: 'Jiná').canonicalBytes(), isNot(base));
    });
  });

  group('stateHash řetěz', () {
    test('různý stav → různý hash, stejný stav → stejný hash', () {
      final h1 = op(epoch: 1).stateHash();
      final h1b = op(epoch: 1).stateHash();
      final h2 = op(epoch: 2).stateHash();
      expect(h1, h1b);
      expect(h1, isNot(h2));
      expect(h1.length, 32);
    });
  });

  group('XEdDSA sign/verify', () {
    var signalOk = false;
    setUpAll(() async {
      try {
        await SepotCrypto.init();
        signalOk = true;
      } catch (_) {
        signalOk = false; // nativní libsignal nedostupná (host bez .so)
      }
    });

    bool ensureSignal() {
      if (!signalOk) {
        markTestSkipped('nativní libsignal nedostupná v host testu');
      }
      return signalOk;
    }

    test('podpis admina se ověří jeho identity klíčem', () {
      if (!ensureSignal()) return;
      final priv = PrivateKey.generate();
      final pub = Uint8List.fromList(priv.getPublicKey().serialize());
      final o = op();
      final sig = o.signWith((m) => priv.sign(message: m));
      expect(o.verify(sig, pub), isTrue);
    });

    test('pozměněná operace se stejným podpisem NEprojde', () {
      if (!ensureSignal()) return;
      final priv = PrivateKey.generate();
      final pub = Uint8List.fromList(priv.getPublicKey().serialize());
      final sig = op(name: 'Parta').signWith((m) => priv.sign(message: m));
      // Útočník přepíše jméno, ale podpis nechá starý.
      final tampered = op(name: 'Ovládnuto');
      expect(tampered.verify(sig, pub), isFalse);
    });

    test('podpis jiného klíče neprojde (cizí admin)', () {
      if (!ensureSignal()) return;
      final signer = PrivateKey.generate();
      final impostor = Uint8List.fromList(
        PrivateKey.generate().getPublicKey().serialize(),
      );
      final o = op();
      final sig = o.signWith((m) => signer.sign(message: m));
      expect(o.verify(sig, impostor), isFalse);
    });
  });
}
