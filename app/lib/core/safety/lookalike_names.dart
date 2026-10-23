/// Rozpoznání jmen, která se pletou s existujícím kontaktem.
///
/// Jméno v Šepotu si každý volí sám, takže „Máma“ od cizího klíče je
/// nejlevnější phishing. Porovnává se „kostra“ jména: bez velikosti
/// písmen, diakritiky, mezer, interpunkce a neviditelných znaků, s cyrilicí
/// a řečtinou převedenou na latinku. „MAMA“, „Мáма“ (cyrilské М) i
/// „Máma“ s neviditelnou mezerou uprostřed tak padnou na totéž jako „Máma“.
library;

import 'package:sepot/core/utils/text_fold.dart';
import 'package:sepot/models/contact.dart';

// Znaky, které na displeji vypadají jako latinka. Jen ty, co se v malých
// písmenech opravdu pletou; ne celý Unicode confusables seznam — falešná
// shoda tu nic nerozbije, jen přidá varování navíc.
const _confusables = {
  'а': 'a', 'в': 'b', 'е': 'e', 'ё': 'e', 'к': 'k', 'м': 'm', 'н': 'h',
  'о': 'o', 'р': 'p', 'с': 'c', 'т': 't', 'у': 'y', 'х': 'x', 'і': 'l',
  'ї': 'l', 'ј': 'j', 'ѕ': 's', 'ԁ': 'd', 'ɡ': 'g', 'α': 'a', 'β': 'b',
  'ε': 'e', 'ι': 'l', 'κ': 'k', 'ν': 'v', 'ο': 'o', 'ρ': 'p', 'τ': 't',
  'υ': 'u', 'χ': 'x', 'ү': 'y', '0': 'o', '1': 'l', 'i': 'l', '|': 'l',
  // Latinská diakritika mimo češtinu a slovenštinu (tu skládá už fold).
  'à': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a', 'ą': 'a', 'ç': 'c',
  'ć': 'c', 'è': 'e', 'ê': 'e', 'ē': 'e', 'ę': 'e', 'ì': 'l', 'î': 'l',
  'ï': 'l', 'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ò': 'o', 'õ': 'o', 'ø': 'o',
  'ő': 'o', 'ś': 's', 'ù': 'u', 'û': 'u', 'ű': 'u', 'ÿ': 'y', 'ź': 'z',
  'ż': 'z',
};

final _invisible = RegExp(
    '[\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180B-\u180E'
    '\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFE00-\uFE0F\uFEFF]');
final _combining = RegExp('[\u0300-\u036F]');
final _separators = RegExp(r'[\s\p{P}\p{S}]', unicode: true);

/// Kostra jména pro porovnání. Prázdný výsledek = jméno nic nenese.
String nameSkeleton(String name) {
  final folded = fold(name
      .replaceAll(_invisible, '')
      .replaceAll(_combining, '')
      .replaceAll(_separators, ''));
  final out = StringBuffer();
  for (final ch in folded.split('')) {
    out.write(_confusables[ch] ?? ch);
  }
  // „rn“ se v bezpatkovém písmu čte jako „m“.
  return out.toString().replaceAll('rn', 'm');
}

/// Přijatý kontakt, se kterým se [name] plete (null = nic podobného).
/// [exceptId] = sám odesílatel, ten se se sebou neporovnává.
Contact? lookalikeContact(
  String name,
  Iterable<Contact> contacts, {
  String? exceptId,
}) {
  final skeleton = nameSkeleton(name);
  if (skeleton.isEmpty) return null;
  for (final c in contacts) {
    if (!c.accepted || c.id == exceptId) continue;
    if (nameSkeleton(c.displayName) == skeleton) return c;
  }
  return null;
}
