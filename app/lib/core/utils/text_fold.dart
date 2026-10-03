/// Porovnávání textu pro hledání: bez ohledu na velikost písmen a diakritiku.
/// Lidé na mobilu často píšou „prectu“ místo „přečtu“ — hledání to má najít.
library;

const _map = {
  'á': 'a', 'ä': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'ě': 'e', 'ë': 'e',
  'í': 'i', 'ľ': 'l', 'ĺ': 'l', 'ň': 'n', 'ó': 'o', 'ô': 'o', 'ö': 'o',
  'ř': 'r', 'ŕ': 'r', 'š': 's', 'ť': 't', 'ú': 'u', 'ů': 'u', 'ü': 'u',
  'ý': 'y', 'ž': 'z', 'ß': 'ss',
};

/// Malá písmena bez diakritiky. Délka se může změnit jen u „ß“, proto
/// pozice shod počítej přes [foldedIndexes], ne přes indexy výsledku.
String fold(String input) {
  final out = StringBuffer();
  for (final ch in input.toLowerCase().split('')) {
    out.write(_map[ch] ?? ch);
  }
  return out.toString();
}

/// Začátky všech výskytů [query] v [text] (indexy do PŮVODNÍHO textu).
/// Znaky se skládají po jednom, takže indexy sedí i pro zvýraznění.
List<int> foldedIndexes(String text, String query) {
  final q = fold(query);
  if (q.isEmpty) return const [];
  final chars = text.split('');
  final folded = chars.map(fold).toList();
  final hits = <int>[];
  for (var i = 0; i < chars.length; i++) {
    var j = i;
    var matched = '';
    while (j < chars.length && matched.length < q.length) {
      matched += folded[j];
      j++;
    }
    if (matched.startsWith(q)) hits.add(i);
  }
  return hits;
}
