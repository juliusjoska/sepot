/// Pravidla správců skupin oddělená od sítě a
/// úložiště: drátová podoba `gop`, ověření příchozí operace v pořadí 1–6
/// ze specifikace, tvorba odchozí operace s invarianty a podržení operací
/// z budoucích epoch.
///
/// Ověření podpisu se předává jako funkce — produkce volá libsignal
/// (`GroupAdminOp.verify`), testy pravidel tak běží i bez nativní knihovny.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sepot/core/crypto/group_admin.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/models/group.dart';

/// Ověří podpis [sig] operace [op] identity klíčem [identityKey].
typedef GroupOpSignatureCheck = bool Function(
    GroupAdminOp op, Uint8List sig, Uint8List identityKey);

bool _libsignalVerify(GroupAdminOp op, Uint8List sig, Uint8List ik) {
  try {
    return op.verify(sig, ik);
  } catch (_) {
    // Nedeserializovatelný klíč/podpis z drátu = neplatný podpis, ne pád
    // příjmové cesty.
    return false;
  }
}

/// Výsledek ověření příchozí operace.
enum GopVerdict {
  /// Platná a navazuje — aplikovat.
  apply,

  /// `by` nesedí se sealed-sender autorem (krok 1).
  spoof,

  /// Porušené invarianty nebo cizí skupina — nikdy nepůjde aplikovat.
  invalid,

  /// Podepsal někdo, kdo u mě není správce (krok 2).
  notAdmin,

  /// Podpis nesedí nebo neznám identity klíč podepisujícího (krok 3).
  badSignature,

  /// Epocha přeskakuje — chybí mi mezistav (krok 4, `>`).
  gap,

  /// Epochu už mám nebo jsem dál (krok 4, `<=`).
  stale,

  /// Navazuje na jiný předchozí stav než můj (krok 5).
  fork,
}

/// Drátová podoba `gop`: pole tabulky ze specifikace. Samostatně jako
/// `t: 'gop'`, v kompatibilním režimu vnořená pod klíčem `gop` v legacy
/// `ginv`/`gmeta` (v1 klient neznámé pole ignoruje a použije stín).
class GroupOpMessage {
  GroupOpMessage({required this.op, required this.sig, this.roster});

  final GroupAdminOp op;
  final Uint8List sig;

  /// Roster entry `[{f,n,ik,aid,da,v}]` — u přidání nových členů a u
  /// pozvánky, ať nový člen zná klíče a routing ostatních.
  final List<Map<String, dynamic>>? roster;

  Map<String, dynamic> toWire() => {
        'gid': op.gid,
        'epoch': op.epoch,
        'op': op.action.name,
        'by': op.actor,
        'members': op.members,
        'admins': op.admins,
        'gname': op.name,
        'prev': base64Encode(op.prev),
        'sig': base64Encode(sig),
        'roster': ?roster,
      };

  /// Null = poškozená nebo neznámá podoba (neznámý typ operace z novější
  /// verze se nedá ověřit, protože jeho index je součást podpisu).
  static GroupOpMessage? fromWire(Object? raw) {
    if (raw is! Map) return null;
    try {
      final m = raw.cast<String, dynamic>();
      final action = GroupAdminAction.values
          .where((a) => a.name == m['op'])
          .firstOrNull;
      final epoch = m['epoch'];
      if (action == null || epoch is! int || epoch < 0) return null;
      final rosterRaw = m['roster'];
      return GroupOpMessage(
        op: GroupAdminOp(
          gid: m['gid'] as String,
          epoch: epoch,
          action: action,
          actor: m['by'] as String,
          members: (m['members'] as List).cast<String>().toList(),
          admins: (m['admins'] as List).cast<String>().toList(),
          name: m['gname'] as String,
          prev: base64Decode(m['prev'] as String),
        ),
        sig: base64Decode(m['sig'] as String),
        roster: rosterRaw is List
            ? [
                for (final e in rosterRaw)
                  if (e is Map) e.cast<String, dynamic>(),
              ]
            : null,
      );
    } on Object {
      // Špatné typy polí (TypeError), vadné base64 (FormatException).
      return null;
    }
  }
}

/// Invarianty stavu, které musí držet každá operace bez ohledu na autora.
bool _stateValid(GroupAdminOp op) =>
    op.gid.isNotEmpty &&
    op.gid.length <= 64 &&
    op.name.trim().isNotEmpty &&
    op.members.length <= Group.maxMembers &&
    op.admins.isNotEmpty &&
    op.admins.every(op.members.contains);

/// Ověří příchozí operaci proti lokálnímu stavu [local] v pořadí kroků 1–6
/// (očíslované v těle funkce).
///
/// [actorIdentityKey] = identity klíč `by` z mých kontaktů (TOFU — nikdy
/// z téže zprávy, jinak by si útočník klíč přinesl sám).
GopVerdict checkGroupOp({
  required Group local,
  required GroupOpMessage msg,
  required String senderFp,
  required String me,
  required Uint8List? actorIdentityKey,
  GroupOpSignatureCheck verify = _libsignalVerify,
}) {
  final op = msg.op;
  // 1. Autor = sealed sender.
  if (op.actor != senderFp) return GopVerdict.spoof;
  if (op.gid != local.id || !_stateValid(op)) return GopVerdict.invalid;

  // 2. Oprávnění. U odhadnutých správců (viz Group.provisional) stačí, že
  // podepisující je člen a v podepsaném stavu správcem.
  final provisional = local.isProvisionalFor(me);
  final authorized = provisional
      ? local.isMember(op.actor) && op.admins.contains(op.actor)
      : local.isAdmin(op.actor);
  if (!authorized) return GopVerdict.notAdmin;

  // 3. Podpis.
  if (actorIdentityKey == null || !verify(op, msg.sig, actorIdentityKey)) {
    return GopVerdict.badSignature;
  }

  // 4. Epocha. Stav od správce (sync) i kotva odhadnuté skupiny nemají na
  // co navázat — rozhoduje jen to, že posouvají dopředu. Ostrá nerovnost
  // u sync brání přeskakování mezi dvěma stejně starými větvemi.
  if (op.action == GroupAdminAction.sync) {
    return op.epoch > local.epoch ? GopVerdict.apply : GopVerdict.stale;
  }
  if (provisional) {
    return op.epoch >= local.epoch ? GopVerdict.apply : GopVerdict.stale;
  }
  if (op.epoch <= local.epoch) return GopVerdict.stale;
  if (op.epoch > local.epoch + 1) return GopVerdict.gap;

  // 5. Řetěz: `prev` musí být hash mého aktuálního stavu.
  final mine = hashState(
    gid: local.id,
    epoch: local.epoch,
    members: local.memberIds,
    admins: local.admins,
    name: local.name,
  );
  if (!_bytesEqual(op.prev, mine)) return GopVerdict.fork;

  // 6. Aplikovat (volající přes applyGroupOp).
  return GopVerdict.apply;
}

/// Ověří operaci, kterou mě někdo přidává do skupiny, kterou ještě neznám.
/// Není s čím řetězit — důvěra je stejná jako u v1 pozvánky (kdo mě zve,
/// je člen), navíc musí být podepsaná správcem uvedeným v rosteru.
GopVerdict checkJoinOp({
  required GroupOpMessage msg,
  required String senderFp,
  required String me,
  required Uint8List? actorIdentityKey,
  GroupOpSignatureCheck verify = _libsignalVerify,
}) {
  final op = msg.op;
  if (op.actor != senderFp) return GopVerdict.spoof;
  if (!_stateValid(op) || !op.members.contains(me)) return GopVerdict.invalid;
  if (!op.admins.contains(op.actor)) return GopVerdict.notAdmin;
  if (actorIdentityKey == null || !verify(op, msg.sig, actorIdentityKey)) {
    return GopVerdict.badSignature;
  }
  return GopVerdict.apply;
}

/// Přepíše lokální stav výsledkem ověřené operace. Když ve výsledku
/// nejsem, správce mě odebral — skupina se chová jako opuštěná.
void applyGroupOp(Group group, GroupAdminOp op, String me) {
  group
    ..memberIds = [...op.members]
    ..admins = [...op.admins]
    ..name = op.name
    ..epoch = op.epoch
    ..provisional = false;
  if (!op.members.contains(me)) group.left = true;
}

/// Hash aktuálního stavu skupiny (vstupuje jako `prev` další operace).
Uint8List currentStateHash(Group g) => hashState(
      gid: g.id,
      epoch: g.epoch,
      members: g.memberIds,
      admins: g.admins,
      name: g.name,
    );

/// Postaví odchozí operaci s kontrolou oprávnění a invariantů. Hází
/// [NotGroupAdminError] / [LastGroupAdminError] dřív, než cokoli odejde.
GroupAdminOp buildGroupOp({
  required Group group,
  required String me,
  required GroupAdminAction action,
  List<String>? members,
  List<String>? admins,
  String? name,
}) {
  if (!group.isAdmin(me)) throw const NotGroupAdminError();
  final newMembers = members ?? group.memberIds;
  final newAdmins = admins ?? group.admins;
  if (newMembers.toSet().length > Group.maxMembers) {
    throw const GroupTooLargeError(Group.maxMembers);
  }
  // Poslední správce se nesmí odebrat ani zbavit role — skupina by zůstala
  // bez nikoho, kdo smí podepsat další změnu.
  if (newAdmins.isEmpty) throw const LastGroupAdminError();
  if (!newAdmins.every(newMembers.contains)) {
    throw StateError('group admins must be members');
  }
  final isSync = action == GroupAdminAction.sync;
  return GroupAdminOp(
    gid: group.id,
    epoch: isSync ? group.epoch : group.epoch + 1,
    action: action,
    actor: me,
    members: newMembers,
    admins: newAdmins,
    name: name ?? group.name,
    // Sync nic neřetězí, jen potvrzuje stav — viz checkGroupOp krok 4.
    prev: isSync ? Uint8List(0) : currentStateHash(group),
  );
}

/// Podrží operaci na později. Při přetečení se zahodí ty z nejvzdálenější
/// budoucnosti — podvržené operace s absurdní epochou tak nevytlačí
/// skutečně chybějící mezistav.
void holdGroupOp(Group group, PendingGroupOp pending) {
  final sig = pending.wire['sig'];
  if (group.pendingOps.any((p) => p.wire['sig'] == sig)) return;
  group.pendingOps = [...group.pendingOps, pending]
    ..sort((a, b) => a.epoch.compareTo(b.epoch));
  if (group.pendingOps.length > Group.maxPendingOps) {
    group.pendingOps = group.pendingOps.sublist(0, Group.maxPendingOps);
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
