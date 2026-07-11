/// Perzistentní libsignal stores nad šifrovanou DB (SQLCipher).
///
/// Ratchet stavy, prekeys a identity protistran přežívají restart aplikace.
/// Vlastní identity keypair sem NEPATŘÍ — dostává se zvenčí (OS keystore),
/// store drží jen odkaz v paměti.
///
/// Trust model identity protistran: TOFU per účet (name), stejná sémantika
/// jako InMemoryIdentityKeyStore z balíčku, ale porovnává se SERIALIZOVANÁ
/// podoba klíče (opaque FFI handle nemá spolehlivé ==).
library;

import 'dart:typed_data';

import 'package:libsignal/libsignal.dart';
import 'package:sepot/core/storage/crypto_db.dart';

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class DbSessionStore implements SessionStore {
  DbSessionStore(this._db);

  final CryptoDb _db;

  @override
  Future<SessionRecord?> loadSession(ProtocolAddress address) async {
    final rows = _db.raw.select(
      'SELECT record FROM sessions WHERE name = ? AND device_id = ?',
      [address.name(), address.deviceId()],
    );
    if (rows.isEmpty) return null;
    return SessionRecord.deserialize(
      bytes: (rows.first['record'] as Uint8List).toList(),
    );
  }

  @override
  Future<void> storeSession(
    ProtocolAddress address,
    SessionRecord record,
  ) async {
    // Atomicky — částečně zapsaný ratchet stav = „bad MAC"
    _db.transaction(() {
      _db.raw.execute(
        'INSERT INTO sessions (name, device_id, record, updated_at) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT(name, device_id) DO UPDATE '
        'SET record = excluded.record, updated_at = excluded.updated_at',
        [
          address.name(),
          address.deviceId(),
          record.serialize(),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    });
  }

  @override
  Future<bool> containsSession(ProtocolAddress address) async {
    final rows = _db.raw.select(
      'SELECT 1 FROM sessions WHERE name = ? AND device_id = ?',
      [address.name(), address.deviceId()],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> deleteSession(ProtocolAddress address) async {
    _db.raw.execute(
      'DELETE FROM sessions WHERE name = ? AND device_id = ?',
      [address.name(), address.deviceId()],
    );
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    _db.raw.execute('DELETE FROM sessions WHERE name = ?', [name]);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final rows = _db.raw.select(
      'SELECT device_id FROM sessions WHERE name = ?',
      [name],
    );
    return [for (final r in rows) r['device_id'] as int];
  }
}

class DbIdentityKeyStore implements IdentityKeyStore {
  DbIdentityKeyStore(
    this._db, {
    required IdentityKeyPair identityKeyPair,
    required int registrationId,
  })  : _identityKeyPair = identityKeyPair,
        _registrationId = registrationId;

  final CryptoDb _db;
  final IdentityKeyPair _identityKeyPair;
  final int _registrationId;

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => _identityKeyPair;

  @override
  Future<int> getLocalRegistrationId() async => _registrationId;

  Uint8List? _stored(String name) {
    final rows = _db.raw.select(
      'SELECT identity FROM remote_identities WHERE name = ?',
      [name],
    );
    if (rows.isEmpty) return null;
    return rows.first['identity'] as Uint8List;
  }

  @override
  Future<bool> saveIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
  ) async {
    final name = address.name();
    final incoming = identityKey.serialize();
    final existing = _stored(name);
    if (existing != null && _bytesEqual(existing, incoming)) {
      return false; // beze změny
    }
    _db.raw.execute(
      'INSERT INTO remote_identities (name, identity, first_seen) '
      'VALUES (?, ?, ?) '
      'ON CONFLICT(name) DO UPDATE SET identity = excluded.identity',
      [name, incoming, DateTime.now().millisecondsSinceEpoch],
    );
    return true; // nová nebo ZMĚNĚNÁ identita (UI ukáže safety-number varování)
  }

  @override
  Future<PublicKey?> getIdentity(ProtocolAddress address) async {
    final stored = _stored(address.name());
    if (stored == null) return null;
    return PublicKey.deserialize(bytes: stored.toList());
  }

  @override
  Future<bool> isTrustedIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
    Direction direction,
  ) async {
    final stored = _stored(address.name());
    if (stored == null) return true; // TOFU
    return _bytesEqual(stored, identityKey.serialize());
  }
}

class DbPreKeyStore implements PreKeyStore {
  DbPreKeyStore(this._db);

  final CryptoDb _db;

  @override
  Future<PreKeyRecord?> loadPreKey(int preKeyId) async {
    final rows = _db.raw.select(
      'SELECT record FROM prekeys WHERE id = ?',
      [preKeyId],
    );
    if (rows.isEmpty) return null;
    return PreKeyRecord.deserialize(
      bytes: (rows.first['record'] as Uint8List).toList(),
    );
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    _db.raw.execute(
      'INSERT INTO prekeys (id, record) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET record = excluded.record',
      [preKeyId, record.serialize()],
    );
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async {
    return _db.raw
        .select('SELECT 1 FROM prekeys WHERE id = ?', [preKeyId]).isNotEmpty;
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    // One-time prekey se po použití MAŽE (forward secrecy první zprávy)
    _db.raw.execute('DELETE FROM prekeys WHERE id = ?', [preKeyId]);
  }

  @override
  Future<List<int>> getAllPreKeyIds() async {
    final rows = _db.raw.select('SELECT id FROM prekeys ORDER BY id');
    return [for (final r in rows) r['id'] as int];
  }
}

class DbSignedPreKeyStore implements SignedPreKeyStore {
  DbSignedPreKeyStore(this._db);

  final CryptoDb _db;

  @override
  Future<SignedPreKeyRecord?> loadSignedPreKey(int signedPreKeyId) async {
    final rows = _db.raw.select(
      'SELECT record FROM signed_prekeys WHERE id = ?',
      [signedPreKeyId],
    );
    if (rows.isEmpty) return null;
    return SignedPreKeyRecord.deserialize(
      bytes: (rows.first['record'] as Uint8List).toList(),
    );
  }

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) async {
    _db.raw.execute(
      'INSERT INTO signed_prekeys (id, record) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET record = excluded.record',
      [signedPreKeyId, record.serialize()],
    );
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async {
    return _db.raw.select(
      'SELECT 1 FROM signed_prekeys WHERE id = ?',
      [signedPreKeyId],
    ).isNotEmpty;
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    _db.raw.execute(
      'DELETE FROM signed_prekeys WHERE id = ?',
      [signedPreKeyId],
    );
  }

  @override
  Future<List<int>> getAllSignedPreKeyIds() async {
    final rows = _db.raw.select('SELECT id FROM signed_prekeys ORDER BY id');
    return [for (final r in rows) r['id'] as int];
  }
}

class DbKyberPreKeyStore implements KyberPreKeyStore {
  DbKyberPreKeyStore(this._db);

  final CryptoDb _db;

  @override
  Future<KyberPreKeyRecord?> loadKyberPreKey(int kyberPreKeyId) async {
    final rows = _db.raw.select(
      'SELECT record FROM kyber_prekeys WHERE id = ?',
      [kyberPreKeyId],
    );
    if (rows.isEmpty) return null;
    return KyberPreKeyRecord.deserialize(
      bytes: (rows.first['record'] as Uint8List).toList(),
    );
  }

  @override
  Future<void> storeKyberPreKey(
    int kyberPreKeyId,
    KyberPreKeyRecord record,
  ) async {
    _db.raw.execute(
      'INSERT INTO kyber_prekeys (id, record) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET record = excluded.record',
      [kyberPreKeyId, record.serialize()],
    );
  }

  @override
  Future<bool> containsKyberPreKey(int kyberPreKeyId) async {
    return _db.raw.select(
      'SELECT 1 FROM kyber_prekeys WHERE id = ?',
      [kyberPreKeyId],
    ).isNotEmpty;
  }

  @override
  Future<void> markKyberPreKeyUsed(int kyberPreKeyId) async {
    // Last-resort Kyber prekey se NEMAŽE (nahrazuje chybějící OTP,
    // ochrana proti replay útoku) — jen se značí použití
    _db.raw.execute(
      'UPDATE kyber_prekeys SET used = 1 WHERE id = ?',
      [kyberPreKeyId],
    );
  }

  @override
  Future<void> removeKyberPreKey(int kyberPreKeyId) async {
    _db.raw.execute('DELETE FROM kyber_prekeys WHERE id = ?', [kyberPreKeyId]);
  }

  @override
  Future<List<int>> getAllKyberPreKeyIds() async {
    final rows = _db.raw.select('SELECT id FROM kyber_prekeys ORDER BY id');
    return [for (final r in rows) r['id'] as int];
  }
}
