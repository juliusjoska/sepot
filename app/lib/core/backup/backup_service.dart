import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/identity.dart';

/// Šifrovaná záloha historie (kontakty + konverzace).
///
/// Klíč se odvozuje z privátního klíče identity (HKDF-SHA256) → zálohu
/// dešifruje POUZE tvoje identita (po obnově ze slov). Přílohy (bloby)
/// v záloze nejsou — obnoví se metadata zpráv, samotný soubor se případně
/// dotáhne z relaye znovu (dokud tam je).
class BackupService {
  BackupService(this._storage);

  final SecureStorageService _storage;

  // Formát: magic(8) ‖ nonce(12) ‖ ciphertext ‖ GCM tag(16)
  static const _magic = 'SEPOTBK1';
  static const _nonceLen = 12;
  static const _tagLen = 16;

  Future<SecretKey> _deriveKey(Uint8List privateKey) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(privateKey),
      nonce: utf8.encode('sepot-backup-salt-v1'),
      info: utf8.encode('sepot-backup-v1'),
    );
  }

  Uint8List _randomNonce() {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(_nonceLen, (_) => r.nextInt(256)));
  }

  /// Vytvoř šifrovanou zálohu — vrací bajty souboru `.sepotbackup`.
  Future<Uint8List> export(LocalIdentity identity) async {
    final contacts = await _storage.loadContacts();
    final conversations = await _storage.loadConversations();
    final payload = utf8.encode(jsonEncode({
      'v': 1,
      'contacts': contacts.map((c) => c.toJson()).toList(),
      'conversations': conversations.map((c) => c.toJson()).toList(),
    }));

    final key = await _deriveKey(identity.identityPrivateKey);
    final nonce = _randomNonce();
    final box = await AesGcm.with256bits()
        .encrypt(payload, secretKey: key, nonce: nonce);

    final out = BytesBuilder();
    out.add(utf8.encode(_magic));
    out.add(nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  /// Obnov ze zálohy. Vrací počet obnovených konverzací. Vyhodí typovanou
  /// chybu ([BackupCorruptedError], [BackupUnknownFormatError],
  /// [BackupWrongIdentityError]) u poškozeného souboru nebo zálohy cizí
  /// identity — UI ji překládá přes describeError.
  Future<int> import(LocalIdentity identity, Uint8List bytes) async {
    if (bytes.length < _magic.length + _nonceLen + _tagLen) {
      throw const BackupCorruptedError();
    }
    if (utf8.decode(bytes.sublist(0, _magic.length)) != _magic) {
      throw const BackupUnknownFormatError();
    }
    final nonce = bytes.sublist(_magic.length, _magic.length + _nonceLen);
    final body = bytes.sublist(_magic.length + _nonceLen);
    final ct = body.sublist(0, body.length - _tagLen);
    final mac = Mac(body.sublist(body.length - _tagLen));

    final key = await _deriveKey(identity.identityPrivateKey);
    List<int> plain;
    try {
      plain = await AesGcm.with256bits().decrypt(
        SecretBox(ct, nonce: nonce, mac: mac),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupWrongIdentityError();
    }

    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    for (final c in (json['contacts'] as List? ?? const [])) {
      await _storage.saveContact(Contact.fromJson(c as Map<String, dynamic>));
    }
    var restored = 0;
    for (final c in (json['conversations'] as List? ?? const [])) {
      await _storage
          .saveConversation(Conversation.fromJson(c as Map<String, dynamic>));
      restored++;
    }
    return restored;
  }
}
