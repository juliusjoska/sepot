import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/crypto/group_admin.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/services/group_admin_policy.dart';
import 'package:sepot/models/group.dart';

/// Pravidla správců skupin bez sítě a bez nativní
/// libsignal: migrace starých skupin, invarianty, ověření příchozí operace
/// v pořadí 1–6 a drátová podoba `gop`. Podpis tu zastupuje fake — skutečný
/// XEdDSA pokrývá group_admin_test.dart a groups_admin_flow_test.dart.
void main() {
  const a = 'fpA'; // zakladatel, správce
  const b = 'fpB';
  const c = 'fpC';
  const d = 'fpD';
  final ikA = Uint8List.fromList(List.filled(33, 1));
  final goodSig = Uint8List.fromList([7, 7, 7]);

  /// Fake podpis: platný je jen `goodSig` a jen s klíčem správce A.
  bool fakeVerify(GroupAdminOp op, Uint8List sig, Uint8List ik) =>
      _eq(sig, goodSig) && _eq(ik, ikA);

  Group mkGroup({int epoch = 0, List<String>? admins, bool provisional = false}) =>
      Group(
        id: 'g1',
        name: 'Chata',
        memberIds: [a, b, c],
        createdBy: a,
        admins: admins,
        epoch: epoch,
        provisional: provisional,
      );

  GroupOpMessage msgFor(
    Group local, {
    GroupAdminAction action = GroupAdminAction.add,
    String actor = a,
    int? epoch,
    List<String>? members,
    List<String>? admins,
    String? name,
    Uint8List? prev,
    Uint8List? sig,
  }) =>
      GroupOpMessage(
        op: GroupAdminOp(
          gid: local.id,
          epoch: epoch ?? local.epoch + 1,
          action: action,
          actor: actor,
          members: members ?? [...local.memberIds, d],
          admins: admins ?? local.admins,
          name: name ?? local.name,
          prev: prev ?? currentStateHash(local),
        ),
        sig: sig ?? goodSig,
      );

  GopVerdict check(Group local, GroupOpMessage msg,
          {String sender = a, Uint8List? ik}) =>
      checkGroupOp(
        local: local,
        msg: msg,
        senderFp: sender,
        me: b,
        actorIdentityKey: ik ?? ikA,
        verify: fakeVerify,
      );

  group('migrace a model', () {
    test('skupina uložená bez správců: admins=[createdBy], epoch=0', () {
      final stara = {
        'id': 'g1',
        'name': 'Chata',
        'memberIds': [a, b, c],
        'createdBy': a,
        'createdAt': '2026-07-10T10:00:00.000',
        'left': false,
      };
      final g = Group.fromJson(stara);
      expect(g.admins, [a]);
      expect(g.epoch, 0);
      expect(g.v2Members, isEmpty);
      expect(g.pendingOps, isEmpty);
      expect(g.provisional, isTrue,
          reason: 'createdBy u v1 může být jen ten, kdo mě pozval');
      expect(g.isProvisionalFor(a), isFalse,
          reason: 'zakladatel si správce neodhaduje');
      expect(g.isProvisionalFor(b), isTrue);
    });

    test('migrace skupiny, kterou zakladatel opustil: nastoupí nejmenší '
        'fingerprint (deterministicky u všech)', () {
      final g = Group.fromJson({
        'id': 'g1',
        'name': 'Chata',
        'memberIds': [c, b],
        'createdBy': a,
        'createdAt': '2026-07-10T10:00:00.000',
      });
      expect(g.admins, [b]);
    });

    test('JSON round-trip zachová všechna v2 pole', () {
      final g = mkGroup(epoch: 3, admins: [a, b])
        ..v2Members.addAll([b, c])
        ..needsResync = true
        ..rejectedOpAt = DateTime(2026, 9, 30, 12)
        ..pendingOps = [
          PendingGroupOp(senderFp: a, wire: {'epoch': 5, 'sig': 'x'}),
        ];
      final back = Group.fromJson(
          jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
      expect(back.admins, [a, b]);
      expect(back.epoch, 3);
      expect(back.v2Members, {b, c});
      expect(back.needsResync, isTrue);
      expect(back.rejectedOpAt, DateTime(2026, 9, 30, 12));
      expect(back.pendingOps.single.senderFp, a);
      expect(back.pendingOps.single.epoch, 5);
      expect(back.provisional, isFalse);
    });

    test('invariant: správci jsou podmnožina členů', () {
      final g = mkGroup(admins: [a, 'cizi']);
      expect(g.admins, [a]);
      g.memberIds = [b, c];
      g.normalizeAdmins();
      expect(g.admins, [b], reason: 'nikdy nezůstane bez správce');
    });
  });

  group('kompatibilní režim', () {
    test('dokud je ve skupině v1 člen, skupina není vynucená', () {
      final g = mkGroup()..v2Members.addAll([a]);
      expect(g.isEnforced(b), isFalse, reason: 'c neinzeruje v2');
      g.v2Members.add(c);
      expect(g.isEnforced(b), isTrue,
          reason: 'všichni kromě mě inzerují v2 (já v2 jsem)');
    });
  });

  group('ověření příchozí operace (pořadí 1–6)', () {
    test('poctivá navazující operace → apply', () {
      final g = mkGroup();
      expect(check(g, msgFor(g)), GopVerdict.apply);
    });

    test('1. SPOOF: by ≠ sealed-sender autor', () {
      final g = mkGroup();
      expect(check(g, msgFor(g), sender: c), GopVerdict.spoof);
    });

    test('2. NE-SPRÁVCE: podepsal člen bez role', () {
      final g = mkGroup();
      expect(check(g, msgFor(g, actor: c), sender: c), GopVerdict.notAdmin);
    });

    test('3. ŠPATNÝ PODPIS i neznámý klíč podepisujícího', () {
      final g = mkGroup();
      expect(check(g, msgFor(g, sig: Uint8List.fromList([1]))),
          GopVerdict.badSignature);
      expect(check(g, msgFor(g), ik: Uint8List.fromList(List.filled(33, 9))),
          GopVerdict.badSignature);
      expect(
          checkGroupOp(
            local: g,
            msg: msgFor(g),
            senderFp: a,
            me: b,
            actorIdentityKey: null,
            verify: fakeVerify,
          ),
          GopVerdict.badSignature);
    });

    test('4a. MEZERA v epoše → gap', () {
      final g = mkGroup(epoch: 2);
      expect(check(g, msgFor(g, epoch: 4)), GopVerdict.gap);
    });

    test('4b. ZASTARALÁ epocha (stejná i starší) → stale', () {
      final g = mkGroup(epoch: 2);
      expect(check(g, msgFor(g, epoch: 2)), GopVerdict.stale);
      expect(check(g, msgFor(g, epoch: 1)), GopVerdict.stale);
    });

    test('5. FORK: prev nesedí s mým stavem', () {
      final g = mkGroup(epoch: 2);
      final jinaHistorie = hashState(
          gid: 'g1', epoch: 2, members: [a, b], admins: [a], name: 'Chata');
      expect(check(g, msgFor(g, prev: jinaHistorie)), GopVerdict.fork);
    });

    test('invarianty příchozího stavu: prázdní správci, správce mimo členy, '
        'cizí skupina', () {
      final g = mkGroup();
      expect(check(g, msgFor(g, admins: [])), GopVerdict.invalid);
      expect(check(g, msgFor(g, members: [a, b], admins: [a, c])),
          GopVerdict.invalid);
      final cizi = GroupOpMessage(
        op: GroupAdminOp(
          gid: 'g2',
          epoch: 1,
          action: GroupAdminAction.add,
          actor: a,
          members: [a, b],
          admins: [a],
          name: 'X',
          prev: currentStateHash(g),
        ),
        sig: goodSig,
      );
      expect(check(g, cizi), GopVerdict.invalid);
    });

    test('sync od správce: jen ostře novější epocha', () {
      final g = mkGroup(epoch: 3);
      GroupOpMessage sync(int epoch) => msgFor(g,
          action: GroupAdminAction.sync, epoch: epoch, prev: Uint8List(0));
      expect(check(g, sync(5)), GopVerdict.apply);
      expect(check(g, sync(3)), GopVerdict.stale,
          reason: 'stejně stará větev nesmí přepínat stav tam a zpět');
    });

    test('odhadnutý správce: první podepsaný stav od člena-správce je kotva',
        () {
      // B dostal pozvánku od C (v1), takže si myslí, že správce je C.
      final g = Group(
        id: 'g1',
        name: 'Chata',
        memberIds: [a, b, c],
        createdBy: c,
        provisional: true,
      );
      expect(g.admins, [c]);
      final kotva = msgFor(g, epoch: 7, prev: Uint8List(0), admins: [a]);
      expect(check(g, kotva), GopVerdict.apply,
          reason: 'prev ani epochu nejde ověřit, správce je v podpisu');
      expect(check(g, msgFor(g, actor: d, admins: [d]), sender: d),
          GopVerdict.notAdmin, reason: 'nečlen kotvu dát nesmí');
    });
  });

  group('pozvánka s podpisem (join)', () {
    GroupOpMessage join({List<String>? members, List<String>? admins}) =>
        GroupOpMessage(
          op: GroupAdminOp(
            gid: 'g9',
            epoch: 0,
            action: GroupAdminAction.add,
            actor: a,
            members: members ?? [a, b],
            admins: admins ?? [a],
            name: 'Nová',
            prev: Uint8List(0),
          ),
          sig: goodSig,
        );

    GopVerdict checkJoin(GroupOpMessage m, {String sender = a}) => checkJoinOp(
          msg: m,
          senderFp: sender,
          me: b,
          actorIdentityKey: ikA,
          verify: fakeVerify,
        );

    test('platná pozvánka', () => expect(checkJoin(join()), GopVerdict.apply));
    test('bez mě → invalid',
        () => expect(checkJoin(join(members: [a, c])), GopVerdict.invalid));
    test('podepsal ne-správce → notAdmin',
        () => expect(checkJoin(join(admins: [b])), GopVerdict.notAdmin));
    test('spoof → spoof',
        () => expect(checkJoin(join(), sender: c), GopVerdict.spoof));
  });

  group('tvorba operace (odesílatel)', () {
    test('epocha +1, prev = hash mého stavu', () {
      final g = mkGroup(epoch: 4);
      final op = buildGroupOp(
          group: g, me: a, action: GroupAdminAction.rename, name: 'Jinak');
      expect(op.epoch, 5);
      expect(op.prev, currentStateHash(g));
      expect(op.name, 'Jinak');
    });

    test('ne-správce operaci nepostaví', () {
      expect(
          () => buildGroupOp(
              group: mkGroup(), me: b, action: GroupAdminAction.rename),
          throwsA(isA<NotGroupAdminError>()));
    });

    test('poslední správce se nesmí degradovat ani odebrat', () {
      final g = mkGroup();
      expect(
          () => buildGroupOp(
              group: g, me: a, action: GroupAdminAction.demote, admins: []),
          throwsA(isA<LastGroupAdminError>()));
      expect(
          () => buildGroupOp(
                group: g,
                me: a,
                action: GroupAdminAction.remove,
                members: [b, c],
                admins: [],
              ),
          throwsA(isA<LastGroupAdminError>()));
    });

    test('správce se smí degradovat, když zůstane jiný', () {
      final op = buildGroupOp(
        group: mkGroup(admins: [a, b]),
        me: a,
        action: GroupAdminAction.demote,
        admins: [b],
      );
      expect(op.admins, [b]);
    });

    test('sync nečísluje epochu ani neřetězí', () {
      final op = buildGroupOp(
          group: mkGroup(epoch: 6), me: a, action: GroupAdminAction.sync);
      expect(op.epoch, 6);
      expect(op.prev, isEmpty);
    });

    test('aplikace výsledku bez mě = odebrán', () {
      final g = mkGroup();
      applyGroupOp(
        g,
        buildGroupOp(
          group: g,
          me: a,
          action: GroupAdminAction.remove,
          members: [a, c],
        ),
        b,
      );
      expect(g.left, isTrue);
      expect(g.epoch, 1);
    });
  });

  group('drátová podoba gop', () {
    test('round-trip toWire → JSON → fromWire', () {
      final g = mkGroup(epoch: 2);
      final msg = GroupOpMessage(
        op: buildGroupOp(
          group: g,
          me: a,
          action: GroupAdminAction.promote,
          admins: [a, c],
        ),
        sig: goodSig,
        roster: [
          {'f': c, 'n': 'Cyril', 'ik': 'AA==', 'v': 2},
        ],
      );
      final wire = jsonDecode(jsonEncode(msg.toWire()));
      expect(wire['op'], 'promote');
      expect(wire['by'], a);
      final back = GroupOpMessage.fromWire(wire)!;
      expect(back.op.canonicalBytes(), msg.op.canonicalBytes(),
          reason: 'po cestě drátem se musí podepsané bajty shodovat');
      expect(back.sig, goodSig);
      expect(back.roster!.single['n'], 'Cyril');
    });

    test('poškozená podoba → null, ne výjimka', () {
      expect(GroupOpMessage.fromWire(null), isNull);
      expect(GroupOpMessage.fromWire({'op': 'add'}), isNull);
      expect(
          GroupOpMessage.fromWire({
            'gid': 'g1',
            'epoch': 1,
            'op': 'nova-operace-z-budoucna',
            'by': a,
            'members': [a],
            'admins': [a],
            'gname': 'X',
            'prev': '',
            'sig': '',
          }),
          isNull);
      expect(
          GroupOpMessage.fromWire({
            'gid': 'g1',
            'epoch': 1,
            'op': 'add',
            'by': a,
            'members': [a],
            'admins': [a],
            'gname': 'X',
            'prev': '%%%',
            'sig': '',
          }),
          isNull);
    });
  });

  group('podržené operace', () {
    test('seřazené podle epochy, bez duplicit, přetečení zahodí nejvzdálenější',
        () {
      final g = mkGroup();
      for (var e = Group.maxPendingOps + 5; e >= 2; e--) {
        holdGroupOp(g, PendingGroupOp(senderFp: a, wire: {'epoch': e, 'sig': '$e'}));
      }
      holdGroupOp(g, PendingGroupOp(senderFp: a, wire: {'epoch': 2, 'sig': '2'}));
      expect(g.pendingOps.length, Group.maxPendingOps);
      expect(g.pendingOps.first.epoch, 2);
      expect(g.pendingOps.last.epoch, Group.maxPendingOps + 1);
    });
  });
}

bool _eq(List<int> x, List<int> y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
