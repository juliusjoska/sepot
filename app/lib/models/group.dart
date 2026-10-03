/// Skupina — párový fanout + správci.
///
/// Drží jen jméno a fingerprinty členů; routing a identity klíče členů
/// žijí v tabulce contacts (člen = běžný kontakt založený z rosteru).
/// Konverzace skupiny je řádek v conversations s contact_id = [id].
///
/// Ukládá se jako JSON blob (`groups.json`), takže nová pole v2 nepotřebují
/// migraci schématu — chybějící klíče doplní [Group.fromJson] lokálně.
class Group {
  Group({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.createdBy,
    DateTime? createdAt,
    this.left = false,
    List<String>? admins,
    this.epoch = 0,
    Set<String>? v2Members,
    this.needsResync = false,
    List<PendingGroupOp>? pendingOps,
    this.rejectedOpAt,
    this.provisional = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        admins = admins ?? [createdBy],
        v2Members = v2Members ?? <String>{},
        pendingOps = pendingOps ?? <PendingGroupOp>[] {
    normalizeAdmins();
  }

  /// UUID v4 skupiny (= `gid` na drátu, = contact_id konverzace).
  final String id;

  String name;

  /// Fingerprinty členů VČETNĚ mě (kompletní roster).
  List<String> memberIds;

  /// Fingerprint zakladatele.
  final String createdBy;

  final DateTime createdAt;

  /// Opustil jsem skupinu (nebo mě správce odebral) — historie zůstává,
  /// vstup je mrtvý a příchozí zprávy skupiny se zahazují.
  bool left;

  /// Správci — podmnožina [memberIds], u živé skupiny nikdy prázdná.
  List<String> admins;

  /// Epocha posledního autorizovaného stavu (0 = založení / migrace z v1).
  int epoch;

  /// Členové, kteří inzerovali podporu správců (`gv: 2`). Jen přibývá:
  /// kdyby šlo capability odebrat, mohl by kdokoli skupinu vrátit do
  /// kompatibilního režimu a obejít správce.
  Set<String> v2Members;

  /// Přišla operace, kterou nešlo navázat (mezera v epoše / rozchod
  /// historie) — čeká se na stav od správce.
  bool needsResync;

  /// Podržené operace z budoucích epoch; zkusí se znovu po každém posunu.
  List<PendingGroupOp> pendingOps;

  /// Kdy naposledy přišla změna skupiny od někoho, kdo k ní nemá právo.
  DateTime? rejectedOpAt;

  /// Správce jen odhadnutý, ne ověřený: skupina převzatá z verze bez
  /// správců nebo pozvánka od v1 klienta. `createdBy` tu znamená „od koho
  /// jsem pozvánku dostal“, ne skutečného zakladatele — člen přidaný
  /// ne-zakladatelem by jinak natrvalo odmítal pravého správce. První
  /// podepsaný stav od člena, který je v něm správcem, se proto přijme
  /// jako kotva (důvěra stejná jako u pozvánky samotné).
  bool provisional;

  /// Strop členů (doporučení: 128).
  static const maxMembers = 128;

  /// Víc podržených operací nedává smysl — mezeru stejně zacelí stav
  /// od správce; strop brání nafouknutí záznamu podvrženými zprávami.
  static const maxPendingOps = 16;

  bool isMember(String fingerprint) => memberIds.contains(fingerprint);

  bool isAdmin(String fingerprint) => admins.contains(fingerprint);

  /// Zakladatel si správce neodhaduje — `createdBy == me` je jistota.
  bool isProvisionalFor(String me) => provisional && createdBy != me;

  /// Vynucená skupina: všichni členové kromě [me] inzerují v2, takže
  /// nikdo nepotřebuje legacy `ginv`/`gmeta` od ne-správce. Dokud je ve
  /// skupině byť jediný v1 klient, řídí se starým pravidlem „kterýkoli
  /// člen smí měnit roster" a v2 ho musí tolerovat, jinak by se stav rozešel.
  bool isEnforced(String me) =>
      memberIds.every((f) => f == me || v2Members.contains(f));

  /// Drží invariant `admins ⊆ members`, neprázdné. Když správce zmizí
  /// mimo podepsaný řetěz (v1 `gleave`, migrace skupiny, kterou zakladatel
  /// už opustil), nastoupí deterministicky nejmenší fingerprint — každý
  /// klient tak dojde ke stejnému výsledku bez síťové domluvy.
  void normalizeAdmins() {
    final kept = {
      for (final a in admins)
        if (memberIds.contains(a)) a,
    }.toList()
      ..sort();
    if (kept.isEmpty && memberIds.isNotEmpty) {
      kept.add(([...memberIds]..sort()).first);
    }
    admins = kept;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'memberIds': memberIds,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'left': left,
        'admins': admins,
        'epoch': epoch,
        'v2': v2Members.toList()..sort(),
        if (needsResync) 'resync': true,
        if (pendingOps.isNotEmpty)
          'pending': [for (final p in pendingOps) p.toJson()],
        'rejectedAt': ?rejectedOpAt?.toIso8601String(),
        if (provisional) 'prov': true,
      };

  /// Skupina uložená verzí bez správců nemá `admins`/`epoch` — dopočítá se
  /// `admins = [createdBy]`, `epoch = 0`.
  /// Migrovaná skupina je [provisional] — viz tam proč.
  factory Group.fromJson(Map<String, dynamic> json) {
    final rejected = json['rejectedAt'] as String?;
    final migrated = !json.containsKey('admins');
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      memberIds: (json['memberIds'] as List<dynamic>).cast<String>().toList(),
      createdBy: json['createdBy'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      left: json['left'] as bool? ?? false,
      admins: (json['admins'] as List<dynamic>?)?.cast<String>().toList(),
      epoch: json['epoch'] as int? ?? 0,
      v2Members: (json['v2'] as List<dynamic>?)?.cast<String>().toSet(),
      needsResync: json['resync'] as bool? ?? false,
      pendingOps: [
        for (final p in (json['pending'] as List<dynamic>? ?? const []))
          PendingGroupOp.fromJson((p as Map).cast<String, dynamic>()),
      ],
      rejectedOpAt: rejected == null ? null : DateTime.parse(rejected),
      provisional: migrated || (json['prov'] as bool? ?? false),
    );
  }
}

/// Podržená správcovská operace: drátová podoba + sealed-sender autor, aby
/// šla později ověřit úplně stejně, jako kdyby právě přišla.
class PendingGroupOp {
  const PendingGroupOp({required this.senderFp, required this.wire});

  final String senderFp;
  final Map<String, dynamic> wire;

  int get epoch => wire['epoch'] as int? ?? 0;

  Map<String, dynamic> toJson() => {'s': senderFp, 'op': wire};

  factory PendingGroupOp.fromJson(Map<String, dynamic> json) => PendingGroupOp(
        senderFp: json['s'] as String,
        wire: (json['op'] as Map).cast<String, dynamic>(),
      );
}
