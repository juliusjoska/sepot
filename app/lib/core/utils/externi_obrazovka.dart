/// Systémové obrazovky, které appku pošlou na pozadí, i když ji člověk
/// neopustil: výběr fotky, fotoaparát, výběr souboru, sdílení.
///
/// Okamžitý zámek (zamknout hned při odchodu na pozadí) by bez téhle výjimky
/// zamkl appku uprostřed posílání fotky a vybraná příloha by se ztratila.
class ExterniObrazovka {
  ExterniObrazovka._();

  static int _otevreno = 0;

  static bool get otevrena => _otevreno > 0;

  /// Obalí volání, které otevře systémovou obrazovku mimo appku.
  static Future<T> behem<T>(Future<T> Function() akce) async {
    _otevreno++;
    try {
      return await akce();
    } finally {
      _otevreno--;
    }
  }
}
