/// Admin-signed membership pro skupiny.
///
/// Původní skupiny nemají role: roster update přijímají od kteréhokoli člena. V2 přidává
/// admin/member role a KAŽDOU změnu členství/role/jména podepisuje admin svým
/// identity klíčem (XEdDSA). Ostatní klienti podpis ověří proti identity klíči
/// admina z rosteru — server tu roli nehraje (sealed sender, hloupý relay).
///
/// Podpis pokrývá VÝSLEDNÝ STAV (setříděné množiny členů a adminů + jméno +
/// epocha) zřetězený na hash předchozího stavu (`prev`) — admin autorizuje
/// konkrétní výsledek navázaný na známou historii, ne jen delta. Tím padá
/// nejednoznačnost i fork: kdo nesedí na `prev`, ví, že se rozešel a musí
/// resync.
///
/// Kanonická serializace je záměrně délkově-prefixovaná: přesun bajtů mezi poli
/// (fingerprint ↔ jméno apod.) MUSÍ změnit podepisované bajty, jinak by šlo
/// zaměnit význam podpisu.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal/libsignal.dart' show PublicKey;
import 'package:pointycastle/digests/sha256.dart';

/// Typ admin operace. Pořadí (index) je součást podpisu — NIKDY nepřehazovat,
/// jen přidávat na konec (jinak se rozbijí staré podpisy).
///
/// `sync` není změna: správce jím podepisuje svůj aktuální stav jako odpověď
/// na žádost o resync (mezera v epoše / rozchod historie u příjemce).
enum GroupAdminAction { add, remove, promote, demote, rename, sync }

/// Doménové separátory — jiný kontext = jiné podepisované bajty.
const String _opDomain = 'sepot-group-adm-v1';
const String _stateDomain = 'sepot-group-state-v1';

/// Jedna admin operace = autorizovaný přechod skupiny do výsledného stavu.
class GroupAdminOp {
  GroupAdminOp({
    required this.gid,
    required this.epoch,
    required this.action,
    required this.actor,
    required List<String> members,
    required List<String> admins,
    required this.name,
    required this.prev,
  })  : members = _sortedUnique(members),
        admins = _sortedUnique(admins);

  /// UUID skupiny (`gid` na drátu).
  final String gid;

  /// Epocha, kterou tato operace ustavuje (monotónní, prev + 1).
  final int epoch;

  final GroupAdminAction action;

  /// Fingerprint podepisujícího admina. MUSÍ se rovnat sealed-sender
  /// fingerprintu odesílatele (anti-spoof).
  final String actor;

  /// Výsledný roster (setříděné fingerprinty, včetně nezměněných členů).
  final List<String> members;

  /// Výsledná množina adminů (setříděné fingerprinty, podmnožina `members`).
  final List<String> admins;

  /// Výsledné jméno skupiny.
  final String name;

  /// Hash předchozího stavu (`stateHash` epochy `epoch-1`); prázdné pro
  /// založení (epoch 0).
  final Uint8List prev;

  /// Podepisované bajty — kanonické, délkově-prefixované, deterministické.
  Uint8List canonicalBytes() {
    final b = BytesBuilder(copy: false);
    b.add(_lpStr(_opDomain));
    b.add(_lpStr(gid));
    b.add(_u64be(epoch));
    b.addByte(action.index);
    b.add(_lpStr(actor));
    b.add(_lpList(members));
    b.add(_lpList(admins));
    b.add(_lpStr(name));
    b.add(_lp(prev));
    return b.toBytes();
  }

  /// Hash tohoto výsledného stavu — vstupuje jako `prev` do NÁSLEDUJÍCÍ
  /// operace (řetěz proti forku).
  Uint8List stateHash() => hashState(
        gid: gid,
        epoch: epoch,
        members: members,
        admins: admins,
        name: name,
      );

  /// XEdDSA podpis operace daným signerem (typicky `SepotCrypto.sign`).
  Uint8List signWith(Uint8List Function(List<int> message) signer) =>
      signer(canonicalBytes());

  /// Ověří podpis proti identity klíči admina (33 B serializovaný pub klíč).
  /// Volající NAVÍC musí ověřit, že `actor` je v aktuální množině adminů a že
  /// `actor` == sealed-sender fingerprint — to zde nevidíme.
  bool verify(Uint8List signature, Uint8List actorIdentityKey) {
    final pk = PublicKey.deserialize(bytes: actorIdentityKey.toList());
    return pk.verify(
      message: canonicalBytes().toList(),
      signature: signature.toList(),
    );
  }
}

/// Hash stavu skupiny (setříděné množiny) — sdílený mezi op.stateHash a
/// výpočtem `prev` u příjemce.
Uint8List hashState({
  required String gid,
  required int epoch,
  required List<String> members,
  required List<String> admins,
  required String name,
}) {
  final b = BytesBuilder(copy: false);
  b.add(_lpStr(_stateDomain));
  b.add(_lpStr(gid));
  b.add(_u64be(epoch));
  b.add(_lpList(_sortedUnique(members)));
  b.add(_lpList(_sortedUnique(admins)));
  b.add(_lpStr(name));
  return Uint8List.fromList(SHA256Digest().process(b.toBytes()));
}

// ── Kanonické kódování ────────────────────────────────────────────────────

List<String> _sortedUnique(List<String> xs) {
  final s = xs.toSet().toList()..sort();
  return s;
}

Uint8List _lp(List<int> bytes) {
  final b = BytesBuilder(copy: false);
  b.add(_u32be(bytes.length));
  b.add(bytes);
  return b.toBytes();
}

Uint8List _lpStr(String s) => _lp(utf8.encode(s));

Uint8List _lpList(List<String> items) {
  final b = BytesBuilder(copy: false);
  b.add(_u32be(items.length));
  for (final item in items) {
    b.add(_lpStr(item));
  }
  return b.toBytes();
}

Uint8List _u32be(int n) {
  final d = ByteData(4)..setUint32(0, n, Endian.big);
  return d.buffer.asUint8List();
}

Uint8List _u64be(int n) {
  final d = ByteData(8)..setUint64(0, n, Endian.big);
  return d.buffer.asUint8List();
}
