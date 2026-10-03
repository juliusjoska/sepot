import 'dart:async';

/// Kdo právě píše: konverzace → otisky pisatelů.
///
/// Indikátor nemá „konec psaní“ — odesílatel posílá „píšu“ nejvýš jednou
/// za pár sekund a tady každý záznam sám vyprší. Zpráva, která pak dorazí,
/// ho smaže hned ([clear]).
class TypingTracker {
  TypingTracker({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// Jak dlouho po posledním „píšu“ indikátor svítí. Musí být delší než
  /// interval, ve kterém odesílatel „píšu“ opakuje (4 s), jinak by blikal.
  static const showFor = Duration(seconds: 6);

  final DateTime Function() _now;
  final _expires = <String, Map<String, DateTime>>{};
  final _changes = StreamController<Map<String, Set<String>>>.broadcast();
  Timer? _sweep;

  Stream<Map<String, Set<String>>> get changes => _changes.stream;

  /// Aktuální pisatelé po konverzacích (bez vypršelých).
  Map<String, Set<String>> get current {
    final now = _now();
    return {
      for (final e in _expires.entries)
        if (e.value.values.any((t) => t.isAfter(now)))
          e.key: {
            for (final w in e.value.entries)
              if (w.value.isAfter(now)) w.key,
          },
    };
  }

  void mark(String convId, String writer) {
    (_expires[convId] ??= {})[writer] = _now().add(showFor);
    _emit();
    _sweep ??= Timer.periodic(const Duration(seconds: 1), (_) => prune());
  }

  void clear(String convId, String writer) {
    final writers = _expires[convId];
    if (writers?.remove(writer) == null) return;
    if (writers!.isEmpty) _expires.remove(convId);
    _emit();
  }

  /// Zahodí vypršelé záznamy; když už nikdo nepíše, zastaví časovač.
  void prune() {
    final now = _now();
    var changed = false;
    _expires.removeWhere((_, writers) {
      final before = writers.length;
      writers.removeWhere((_, t) => !t.isAfter(now));
      changed |= writers.length != before;
      return writers.isEmpty;
    });
    if (changed) _emit();
    if (_expires.isEmpty) {
      _sweep?.cancel();
      _sweep = null;
    }
  }

  void dispose() {
    _sweep?.cancel();
    _sweep = null;
    _expires.clear();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(current);
  }
}
