/// Skupina — párový fanout MVP.
///
/// Drží jen jméno a fingerprinty členů; routing a identity klíče členů
/// žijí v tabulce contacts (člen = běžný kontakt založený z rosteru).
/// Konverzace skupiny je řádek v conversations s contact_id = [id].
class Group {
  Group({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.createdBy,
    DateTime? createdAt,
    this.left = false,
  }) : createdAt = createdAt ?? DateTime.now();

  /// UUID v4 skupiny (= `gid` na drátu, = contact_id konverzace).
  final String id;

  String name;

  /// Fingerprinty členů VČETNĚ mě (kompletní roster).
  List<String> memberIds;

  /// Fingerprint zakladatele.
  final String createdBy;

  final DateTime createdAt;

  /// Opustil jsem skupinu — historie zůstává, vstup je mrtvý a příchozí
  /// zprávy skupiny se zahazují.
  bool left;

  /// Strop členů (doporučení: 128).
  static const maxMembers = 128;

  bool isMember(String fingerprint) => memberIds.contains(fingerprint);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'memberIds': memberIds,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'left': left,
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        memberIds:
            (json['memberIds'] as List<dynamic>).cast<String>().toList(),
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        left: json['left'] as bool? ?? false,
      );
}
