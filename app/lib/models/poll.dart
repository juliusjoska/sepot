/// Anketa uvnitř zprávy.
///
/// Na drátě jede jako běžná textová zpráva s polem `poll` — starší verze
/// appky pole neznají a ukážou záložní text (otázku a možnosti), nové
/// z něj vykreslí anketu. Hlasy jsou samostatné řídicí zprávy `vote`;
/// klíč hlasu je otisk odesílatele ověřený sealed senderem, nikdy údaj
/// z obsahu.
class Poll {
  const Poll({
    required this.question,
    required this.options,
    this.multi = false,
    this.votes = const {},
  });

  static const minOptions = 2;
  static const maxOptions = 12;
  static const maxQuestionLength = 200;
  static const maxOptionLength = 100;

  final String question;
  final List<String> options;

  /// Smí jeden člověk zvolit víc možností.
  final bool multi;

  /// Otisk hlasujícího → zvolené indexy možností.
  final Map<String, List<int>> votes;

  /// Kolik lidí zvolilo možnost [index].
  int countFor(int index) =>
      votes.values.where((choice) => choice.contains(index)).length;

  /// Otisky lidí, kteří zvolili možnost [index].
  List<String> votersFor(int index) => [
        for (final e in votes.entries)
          if (e.value.contains(index)) e.key,
      ];

  int get voterCount => votes.length;

  /// Nový hlas [voter]. Neplatné indexy se zahodí, duplicity sloučí;
  /// u ankety s jednou volbou platí jen první. Prázdná volba = hlas zrušen.
  Poll withVote(String voter, List<int> choice) {
    final clean = <int>[
      for (final i in choice.toSet())
        if (i >= 0 && i < options.length) i,
    ]..sort();
    final picked = multi ? clean : clean.take(1).toList();
    final next = Map<String, List<int>>.from(votes);
    if (picked.isEmpty) {
      next.remove(voter);
    } else {
      next[voter] = picked;
    }
    return Poll(question: question, options: options, multi: multi, votes: next);
  }

  /// Co jde na drát (bez hlasů — ty cestují zvlášť).
  Map<String, dynamic> toWire() => {
        'q': question,
        'o': options,
        if (multi) 'm': true,
      };

  /// Anketa od protistrany. Cokoli mimo limity = null (zpráva se pak
  /// ukáže jako obyčejný text), aby cizí data nemohla rozbít vykreslení.
  static Poll? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final q = raw['q'];
    final o = raw['o'];
    if (q is! String || o is! List) return null;
    final question = q.trim();
    if (question.isEmpty || question.length > maxQuestionLength) return null;
    final options = [
      for (final item in o)
        if (item is String) item.trim(),
    ];
    if (options.length != o.length ||
        options.length < minOptions ||
        options.length > maxOptions ||
        options.any((x) => x.isEmpty || x.length > maxOptionLength)) {
      return null;
    }
    return Poll(question: question, options: options, multi: raw['m'] == true);
  }

  Map<String, dynamic> toJson() => {
        ...toWire(),
        'votes': votes,
      };

  static Poll? fromJson(Object? raw) {
    final poll = fromWire(raw);
    if (poll == null || raw is! Map) return poll;
    final stored = raw['votes'];
    var result = poll;
    if (stored is Map) {
      for (final e in stored.entries) {
        final choice = e.value;
        if (e.key is String && choice is List) {
          result = result.withVote(
              e.key as String, choice.whereType<int>().toList());
        }
      }
    }
    return result;
  }
}
