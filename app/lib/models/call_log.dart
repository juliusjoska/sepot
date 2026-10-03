/// Záznam hovoru v chatu („Hovor · 3:12“, „Zmeškaný hovor“). Jen lokální:
/// každá strana si ho zapíše sama podle toho, jak hovor u ní skončil.
enum CallOutcome {
  /// Hovor proběhl (spojil se), [CallLog.durationSeconds] je jeho délka.
  completed,

  /// Příchozí, nikdo ho nevzal (nebo nabídka dorazila pozdě).
  missed,

  /// Odchozí, protistrana ho nevzala do vypršení zvonění.
  unanswered,

  /// Odmítnutý (mnou u příchozího, protistranou u odchozího).
  rejected,

  /// Protistrana měla jiný hovor.
  busy,

  /// Spojení se nepodařilo navázat (síť, firewall bez TURN).
  failed,
}

class CallLog {
  const CallLog({
    required this.outcome,
    required this.outgoing,
    required this.video,
    this.durationSeconds = 0,
  });

  final CallOutcome outcome;
  final bool outgoing;
  final bool video;
  final int durationSeconds;

  Map<String, dynamic> toJson() => {
        'o': outcome.name,
        'out': outgoing,
        'vid': video,
        if (durationSeconds > 0) 'dur': durationSeconds,
      };

  /// Neznámý výsledek z novější verze appky = null (řádek se nezobrazí,
  /// ale zpráva se načte).
  static CallLog? fromJson(Object? json) {
    if (json is! Map) return null;
    final outcome =
        CallOutcome.values.where((o) => o.name == json['o']).firstOrNull;
    if (outcome == null) return null;
    return CallLog(
      outcome: outcome,
      outgoing: json['out'] == true,
      video: json['vid'] == true,
      durationSeconds: (json['dur'] as num?)?.toInt() ?? 0,
    );
  }
}
