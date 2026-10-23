import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/safety/lookalike_names.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/identity.dart';

/// Jméno zvolené odesílatelem se nesmí dát „obejít“ diakritikou, velikostí
/// písmen, cizí abecedou ani neviditelnými znaky.
void main() {
  Contact kontakt(String jmeno, {bool accepted = true, int seed = 1}) =>
      Contact.fromPublicIdentity(
        PublicIdentity(
          displayName: jmeno,
          identityKey: Uint8List.fromList(
              [0x05, ...List.generate(32, (i) => (i * seed + 3) & 0xff)]),
          createdAt: DateTime.utc(2026),
        ),
        accepted: accepted,
      );

  test('stejná kostra pro varianty téhož jména', () {
    final mama = nameSkeleton('Máma');
    for (final varianta in [
      'mama',
      'MAMA',
      ' Má ma ',
      'Máma!',
      'M\u00E1\u200Bma',
      '\u041C\u00E1\u043C\u0430', // cyrilské М, м, а
      'Ma\u0301ma', // kombinující čárka
      'Mámа\u202E',
    ]) {
      expect(nameSkeleton(varianta), mama, reason: varianta);
    }
  });

  test('homoglyfy l/I/1 a rn/m', () {
    expect(nameSkeleton('Pavel'), nameSkeleton('PaveI'));
    expect(nameSkeleton('Pavel'), nameSkeleton('Pave1'));
    expect(nameSkeleton('Marek'), nameSkeleton('rnarek'));
  });

  test('různá jména se nepletou', () {
    expect(nameSkeleton('Máma'), isNot(nameSkeleton('Táta')));
    expect(nameSkeleton('Jana'), isNot(nameSkeleton('Jan')));
  });

  test('porovnává jen s přijatými kontakty a ne se sebou', () {
    final mama = kontakt('Máma');
    final zadost = kontakt('MAMA', accepted: false, seed: 2);
    expect(lookalikeContact('mama', [mama, zadost]), same(mama));
    expect(lookalikeContact('mama', [zadost]), isNull);
    expect(lookalikeContact('mama', [mama], exceptId: mama.id), isNull);
    expect(lookalikeContact('', [kontakt('')]), isNull,
        reason: 'prázdné jméno nic nenese');
  });
}
