import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/crypto/dek_wrap.dart';
import 'package:sepot/core/storage/attachment_store.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/message.dart';

/// Lokální úložiště — OS keystore (klíče) + SQLCipher DB (všechna data).
///
/// Klíčový model:
///   - DEK (32 B, náhodný) šifruje jedinou SQLCipher DB, kde žije VŠECHNO:
///     krypto stavy, kontakty, konverzace se zprávami i nastavení.
///   - Bez PINu: DEK leží raw v OS keystore (baseline ochrana OS).
///   - S PINem: DEK je zabalený Argon2id(PIN) + AES-256-GCM ([DekWrap]);
///     raw kopie se z keystore MAŽE. Ověření PINu = úspěšný unwrap,
///     žádný hash na porovnání neexistuje.
///
/// Lifecycle: appka startuje ZAMČENÁ ([isUnlocked] == false). Data jsou
/// dostupná až po [unlockWithPin] / [unlockWithoutPin] (nebo [enablePin]
/// při onboardingu, který DB rovnou otevře).

/// Nátlakový PIN je shodný se skutečným — nelze nastavit.
/// Příliš mnoho špatných PINů za sebou — další pokus až za [remaining].
class PinLockedException implements Exception {
  const PinLockedException(this.remaining);

  final Duration remaining;

  @override
  String toString() => 'PIN locked for ${remaining.inSeconds}s';
}

class DecoyPinConflict implements Exception {
  const DecoyPinConflict();
  @override
  String toString() => 'decoy PIN must differ from the regular PIN';
}

class SecureStorageService {
  static const _identityKey = 'local_identity';
  static const _seedPhraseKey = 'seed_phrase';
  static const _biometricsEnabledKey = 'biometrics_enabled';
  static const _onboardingCompleteKey = 'onboarding_complete';
  static const _rawDekKey = 'crypto_db_dek';
  static const _wrappedDekKey = 'wrapped_dek';
  // Biometrické odemčení: kopie DEK v OS keystore (TEE/StrongBox).
  // VĚDOMÝ tradeoff — s PINem jinak DEK existuje JEN za Argon2id(PIN);
  // biometrie ho vrací do keystore výměnou za pohodlí. Opt-in.
  static const _biometricDekKey = 'biometric_dek';
  // Legacy — PBKDF2 hash PINu, jen se uklízí
  static const _legacyPinHashKey = 'pin_hash';

  static const _decoyWrappedDekKey = 'wrapped_dek_decoy';
  // Brzda hádání PINu: počet chyb za sebou a čas, do kdy je zámek uzamčený.
  // V keystore (ne v DB) — DB je právě to, co se hádáním otevírá.
  static const _pinFailCountKey = 'pin_fail_count';
  static const _pinLockUntilKey = 'pin_lock_until';
  static const _pinFreeAttempts = 5;
  static const _pinLockBase = Duration(seconds: 30);
  static const _pinLockMax = Duration(minutes: 15);

  final FlutterSecureStorage _secureStorage;
  final String? _dbPathOverride;

  CryptoDb? _db;
  Uint8List? _dek;
  bool _decoyMode = false;

  /// Odemčeno nátlakovým (decoy) PINem → běžíme nad prázdnou decoy DB.
  /// V tomhle režimu úložiště nevydá skutečnou identitu ani frázi,
  /// nestartuje síť a nic z keystore nemění (viz jednotlivé metody).
  bool get isDecoyMode => _decoyMode;

  /// Identita ukazovaná v nátlakové relaci: náhodná, jen v paměti.
  LocalIdentity? _decoyIdentity;

  void _requireRealSession() {
    if (_decoyMode) throw StateError('Not available in a duress session');
  }

  SecureStorageService({String? dbPath})
      : _secureStorage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          // this_device: identita a klíče nesmí putovat v iCloud Keychain
          // ani v záloze na jiný telefon — obnova jde přes 24 slov.
          iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device),
        ),
        _dbPathOverride = dbPath;

  // === Zámek a DB lifecycle ===

  bool get isUnlocked => _db != null;

  /// Otevřená šifrovaná DB — sdílí ji storage i messaging vrstva.
  CryptoDb get db =>
      _db ?? (throw StateError('Storage is locked — unlock first'));

  /// Odemčení bez PINu — DEK leží raw v OS keystore.
  Future<void> unlockWithoutPin() async {
    if (isUnlocked) return;
    if (await hasPin()) {
      throw StateError('PIN is set — use unlockWithPin');
    }
    final dek = await _getOrCreateRawDek();
    await _openDb(dek);
  }

  /// Odemčení PINem — Argon2id unwrap DEK. Špatný PIN = [WrongPinException].
  ///
  /// Nejdřív zkusí skutečný PIN. Když nesedí a je nastavený nátlakový
  /// (decoy) PIN, zkusí ten → otevře PRÁZDNOU decoy DB (plausible
  /// deniability: útočník vidí nastavený, ale „nepoužívaný" messenger).
  Future<void> unlockWithPin(String pin) async {
    if (isUnlocked) return;
    final wrapped = await _secureStorage.read(key: _wrappedDekKey);
    if (wrapped == null) {
      throw StateError('No PIN set — use unlockWithoutPin');
    }
    final locked = await pinLockRemaining();
    if (locked != null) throw PinLockedException(locked);

    final decoy = await _secureStorage.read(key: _decoyWrappedDekKey);
    try {
      // Oba bloby jednou derivací (sdílená sůl) — čas odemčení neprozradí,
      // který PIN padl.
      final (index, dek) = await DekWrap.unwrapFirstMatching(
        wrapped: [wrapped, ?decoy],
        pin: pin,
      );
      await _openDb(dek, decoy: index == 1);
      await _resetPinFailures();
    } on WrongPinException {
      await _notePinFailure();
      rethrow;
    }
  }

  /// Zbývající zámek po sérii špatných PINů; null = volno.
  Future<Duration?> pinLockRemaining() async {
    final raw = await _secureStorage.read(key: _pinLockUntilKey);
    final until = raw == null ? null : int.tryParse(raw);
    if (until == null) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(until)
        .difference(DateTime.now());
    return remaining > Duration.zero ? remaining : null;
  }

  Future<void> _notePinFailure() async {
    final raw = await _secureStorage.read(key: _pinFailCountKey);
    final failures = (raw == null ? 0 : int.tryParse(raw) ?? 0) + 1;
    await _secureStorage.write(key: _pinFailCountKey, value: '$failures');
    if (failures < _pinFreeAttempts) return;
    // 30 s po páté chybě, pak dvojnásobně až do 15 minut: šest číslic
    // (10⁶) tak trvá roky, Argon2id sám by brzdil jen ~2 s na pokus.
    var lock = _pinLockBase * (1 << (failures - _pinFreeAttempts));
    if (lock > _pinLockMax) lock = _pinLockMax;
    await _secureStorage.write(
      key: _pinLockUntilKey,
      value: '${DateTime.now().add(lock).millisecondsSinceEpoch}',
    );
  }

  Future<void> _resetPinFailures() async {
    await _secureStorage.delete(key: _pinFailCountKey);
    await _secureStorage.delete(key: _pinLockUntilKey);
  }

  /// Zapne PIN: zabalí DEK za Argon2id(PIN) a raw kopii z keystore smaže.
  /// Pokud DB ještě není otevřená (onboarding), rovnou ji otevře.
  Future<void> enablePin(String pin) async {
    _requireRealSession();
    final dek = _dek ?? await _getOrCreateRawDek();
    final wrapped = await DekWrap.wrap(dek: dek, pin: pin);
    await _secureStorage.write(key: _wrappedDekKey, value: wrapped);
    await _secureStorage.delete(key: _rawDekKey);
    if (!isUnlocked) {
      await _openDb(dek);
    }
  }

  /// Vypne PIN: DEK se vrátí raw do OS keystore.
  Future<void> disablePin() async {
    _requireRealSession();
    final dek = _dek ?? (throw StateError('Requires unlocked storage'));
    await _secureStorage.write(key: _rawDekKey, value: base64Encode(dek));
    await _secureStorage.delete(key: _wrappedDekKey);
  }

  /// Ověří skutečný PIN, aniž by cokoli změnil (unwrap a zahození DEK).
  /// Tímhle se potvrzují citlivé akce v odemčené appce (fráze, záloha,
  /// smazání účtu, změna PINu).
  ///
  /// Sdílí brzdu se zámkovou obrazovkou: kdo dostane do ruky odemčený
  /// telefon, nesmí tu hádat PIN rychleji než na zámku. Zamčeno =
  /// [PinLockedException].
  ///
  /// V nátlakové relaci vždy false: i kdyby někdo znal skutečný PIN, k frázi
  /// skutečné identity se odtud dostat nesmí (otevře si appku normálně).
  Future<bool> verifyPin(String pin) async {
    if (_decoyMode) return false;
    final wrapped = await _secureStorage.read(key: _wrappedDekKey);
    if (wrapped == null) return false;
    final locked = await pinLockRemaining();
    if (locked != null) throw PinLockedException(locked);
    try {
      await DekWrap.unwrap(wrapped: wrapped, pin: pin);
      await _resetPinFailures();
      return true;
    } on WrongPinException {
      await _notePinFailure();
      return false;
    }
  }

  /// Změna PINu — starý PIN se ověří unwrapem (špatný = [WrongPinException]).
  ///
  /// Nový PIN se nesmí trefit do nátlakového: jinak by běžné odemčení
  /// otevřelo decoy DB (unlockWithPin zkouší real→decoy) a uživatel by
  /// přišel o přístup ke svým datům.
  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    _requireRealSession();
    final wrapped = await _secureStorage.read(key: _wrappedDekKey);
    if (wrapped == null) throw StateError('No PIN set');
    final dek = await DekWrap.unwrap(wrapped: wrapped, pin: oldPin);

    final decoy = await _secureStorage.read(key: _decoyWrappedDekKey);
    if (decoy != null) {
      try {
        await DekWrap.unwrap(wrapped: decoy, pin: newPin);
        throw const DecoyPinConflict();
      } on WrongPinException {
        // OK — nový PIN se liší od nátlakového
      }
    }

    // Sůl zůstává: nátlakový blob ji sdílí (jedna derivace pro oba PINy)
    // a bez jeho PINu by se přebalit nedal. Jedna sůl pro dva PINy téhož
    // uživatele nic neoslabuje — sůl brání předpočítání napříč uživateli.
    final rewrapped = await DekWrap.wrap(
        dek: dek, pin: newPin, salt: DekWrap.saltOf(wrapped));
    await _secureStorage.write(key: _wrappedDekKey, value: rewrapped);
  }

  Future<bool> hasPin() async {
    return await _secureStorage.read(key: _wrappedDekKey) != null;
  }

  /// Nastaví nátlakový (decoy) PIN — jeho zadáním se otevře PRÁZDNÁ decoy
  /// DB. Vyžaduje nastavený běžný PIN a MUSÍ se od něj lišit.
  Future<void> enableDecoyPin(String decoyPin) async {
    _requireRealSession();
    final realWrapped = await _secureStorage.read(key: _wrappedDekKey);
    if (realWrapped == null) {
      throw StateError('Set a regular PIN first');
    }
    // Decoy PIN se musí lišit od skutečného (jinak by se decoy nikdy nespustil)
    try {
      await DekWrap.unwrap(wrapped: realWrapped, pin: decoyPin);
      throw const DecoyPinConflict();
    } on WrongPinException {
      // OK — decoy se liší od skutečného PINu
    }
    final rng = Random.secure();
    final decoyDek =
        Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    // Inicializuj prázdnou decoy DB (schéma) bez zásahu do aktuální DB
    final decoyPath = await _dbPath(decoy: true);
    CryptoDb.open(path: decoyPath, dek: decoyDek).close();
    // Stejná sůl jako skutečný blob → jedna Argon2id derivace pro oba PINy.
    final wrapped = await DekWrap.wrap(
        dek: decoyDek, pin: decoyPin, salt: DekWrap.saltOf(realWrapped));
    await _secureStorage.write(key: _decoyWrappedDekKey, value: wrapped);
  }

  Future<bool> hasDecoyPin() async {
    return await _secureStorage.read(key: _decoyWrappedDekKey) != null;
  }

  /// Zruší nátlakový PIN a smaže decoy DB.
  Future<void> disableDecoyPin() async {
    _requireRealSession();
    await _secureStorage.delete(key: _decoyWrappedDekKey);
    await _deleteDbFiles(await _dbPath(decoy: true));
  }

  Future<void> _deleteDbFiles(String path) async {
    for (final suffix in ['', '-wal', '-shm']) {
      try {
        final f = File('$path$suffix');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // best-effort úklid
      }
    }
  }

  /// Starší instalace měla PIN jako PBKDF2 hash — starý formát neumíme
  /// (a nechceme) ověřit, uživatel si PIN nastaví znovu. Číst PŘED
  /// unlockem ([_cleanupLegacy] marker maže).
  Future<bool> hasLegacyPin() async {
    return await _secureStorage.read(key: _legacyPinHashKey) != null;
  }

  /// Zamkne úložiště — zavře DB a zahodí DEK z paměti.
  void lock() {
    _db?.close();
    _db = null;
    _dek = null;
    _decoyMode = false;
    _decoyIdentity = null;
  }

  Future<void> _openDb(Uint8List dek, {bool decoy = false}) async {
    final path = await _dbPath(decoy: decoy);
    _db = CryptoDb.open(path: path, dek: dek);
    _dek = dek;
    _decoyMode = decoy;
    if (!decoy) await _cleanupLegacy();
  }

  Future<String> _dbPath({bool decoy = false}) async {
    if (_dbPathOverride != null) {
      return decoy ? '$_dbPathOverride.decoy' : _dbPathOverride;
    }
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/${decoy ? 'sepot_crypto_decoy.db' : 'sepot_crypto.db'}';
  }

  Future<Uint8List> _getOrCreateRawDek() async {
    final existing = await _secureStorage.read(key: _rawDekKey);
    if (existing != null) {
      return base64Decode(existing);
    }
    final rng = Random.secure();
    final dek = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    await _secureStorage.write(key: _rawDekKey, value: base64Encode(dek));
    return dek;
  }

  /// Úklid po starších instalacích: PBKDF2 pin_hash z keystore a hlavně
  /// PLAINTEXT Hive soubory z disku (obsahovaly zprávy nešifrovaně).
  /// Bez datové migrace — žádná produkční data neexistují.
  Future<void> _cleanupLegacy() async {
    try {
      await _secureStorage.delete(key: _legacyPinHashKey);
      final docs = await getApplicationDocumentsDirectory();
      for (final box in [
        AppConstants.identityBox,
        AppConstants.contactsBox,
        AppConstants.conversationsBox,
        AppConstants.messagesBox,
        AppConstants.settingsBox,
      ]) {
        for (final suffix in ['hive', 'lock']) {
          final f = File('${docs.path}/$box.$suffix');
          if (f.existsSync()) f.deleteSync();
        }
      }
    } catch (_) {
      // best-effort — nesmí shodit unlock
    }
  }

  /// Test-only: podstrč otevřenou DB bez OS keystore (Linux VM testy).
  @visibleForTesting
  void debugAttachDb(CryptoDb db) {
    _db = db;
  }

  // === Identita ===

  /// Ulož lokální identitu (šifrovaně v Keychain/Keystore)
  Future<void> saveIdentity(LocalIdentity identity) async {
    await _secureStorage.write(
      key: _identityKey,
      value: jsonEncode(identity.toJson()),
    );
  }

  /// Načti lokální identitu
  Future<LocalIdentity?> loadIdentity() async {
    if (_decoyMode) {
      // Nátlaková relace ukazuje náhodnou identitu jen z paměti — skutečný
      // klíč z keystore se do ní nikdy nedostane (nátlakový PIN musí být izolovaný).
      return _decoyIdentity ??= await LocalIdentity.create('');
    }
    final json = await _secureStorage.read(key: _identityKey);
    if (json == null) return null;
    try {
      return LocalIdentity.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on FormatException {
      // Identita ve starém (před-libsignal) formátu — bez migrace,
      // uživatel projde onboardingem znovu (žádná produkční data neexistují)
      await _secureStorage.delete(key: _identityKey);
      return null;
    }
  }

  /// Existuje identita?
  Future<bool> hasIdentity() async {
    return await _secureStorage.read(key: _identityKey) != null;
  }

  // === Seed Phrase ===

  Future<void> saveSeedPhrase(List<String> words) async {
    await _secureStorage.write(
      key: _seedPhraseKey,
      value: jsonEncode(words),
    );
  }

  Future<List<String>?> loadSeedPhrase() async {
    if (_decoyMode) return null;
    final json = await _secureStorage.read(key: _seedPhraseKey);
    if (json == null) return null;
    return (jsonDecode(json) as List).cast<String>();
  }

  // === Biometrie ===

  /// Zapne biometrické odemčení — uloží kopii DEK do OS keystore.
  /// Vyžaduje odemčené úložiště (typicky hned po zadání PINu v settings).
  /// Samotné ověření otisku/obličeje řeší UI přes local_auth PŘED voláním.
  Future<void> enableBiometrics() async {
    _requireRealSession();
    final dek = _dek ?? (throw StateError('Requires unlocked storage'));
    await _secureStorage.write(
      key: _biometricDekKey,
      value: base64Encode(dek),
    );
    await _secureStorage.write(key: _biometricsEnabledKey, value: 'true');
  }

  /// Vypne biometrii a kopii DEK z keystore smaže (zpět na čistý
  /// PIN-only model: DEK existuje jen za Argon2id).
  Future<void> disableBiometrics() async {
    _requireRealSession();
    await _secureStorage.delete(key: _biometricDekKey);
    await _secureStorage.write(key: _biometricsEnabledKey, value: 'false');
  }

  /// Odemčení po úspěšné biometrické výzvě (local_auth v UI).
  Future<void> unlockWithBiometrics() async {
    if (isUnlocked) return;
    final stored = await _secureStorage.read(key: _biometricDekKey);
    if (stored == null) {
      throw StateError('Biometric unlock is not set up');
    }
    await _openDb(base64Decode(stored));
  }

  Future<bool> isBiometricsEnabled() async {
    final value = await _secureStorage.read(key: _biometricsEnabledKey);
    return value == 'true' &&
        await _secureStorage.read(key: _biometricDekKey) != null;
  }

  // === Onboarding ===

  Future<void> setOnboardingComplete(bool complete) async {
    await _secureStorage.write(
      key: _onboardingCompleteKey,
      value: complete.toString(),
    );
  }

  Future<bool> isOnboardingComplete() async {
    final value = await _secureStorage.read(key: _onboardingCompleteKey);
    return value == 'true';
  }

  // === Kontakty (SQLCipher) ===

  Future<List<Contact>> loadContacts() async {
    return [
      for (final json in db.contactsJsonAll())
        Contact.fromJson(jsonDecode(json) as Map<String, dynamic>),
    ];
  }

  Future<void> saveContact(Contact contact) async {
    db.contactPut(contact.id, jsonEncode(contact.toJson()));
  }

  Future<void> deleteContact(String contactId) async {
    db.contactDelete(contactId);
  }

  // === Skupiny (SQLCipher) ===

  Future<List<Group>> loadGroups() async {
    return [
      for (final json in db.groupsJsonAll())
        Group.fromJson(jsonDecode(json) as Map<String, dynamic>),
    ];
  }

  Future<Group?> loadGroup(String id) async {
    final json = db.groupJson(id);
    if (json == null) return null;
    return Group.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> saveGroup(Group group) async {
    db.groupPut(group.id, jsonEncode(group.toJson()));
  }

  /// Smaže skupinu včetně konverzace (historie pryč — používat po
  /// opuštění, když už uživatel historii nechce).
  Future<void> deleteGroup(String id) async {
    db.groupDelete(id);
  }

  // === Konverzace (SQLCipher) ===

  Future<List<Conversation>> loadConversations() async {
    final conversations = [
      for (final json in db.conversationsJsonAll())
        Conversation.fromJson(jsonDecode(json) as Map<String, dynamic>),
    ];
    conversations.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return conversations;
  }

  Future<Conversation?> loadConversation(String contactId) async {
    final json = db.conversationJson(contactId);
    if (json == null) return null;
    return Conversation.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> saveConversation(Conversation conversation) async {
    db.conversationPut(
      conversation.contactId,
      jsonEncode(conversation.toJson()),
    );
  }

  /// Přidá zprávu do konverzace. Vrací false, když už tam zpráva s tímhle id
  /// je (opakované doručení) — volající pak přeskočí navazující kroky jako
  /// doručenku nebo stahování přílohy.
  Future<bool> addMessage(String contactId, Message message) async {
    var conv = await loadConversation(contactId);
    conv ??= Conversation(contactId: contactId);
    if (!conv.addMessage(message)) return false;
    await saveConversation(conv);
    return true;
  }

  /// Založí prázdnou konverzaci, pokud ještě není (nová skupina musí být
  /// v chat listu vidět i před první zprávou).
  Future<void> ensureConversation(String contactId) async {
    if (await loadConversation(contactId) != null) return;
    await saveConversation(Conversation(contactId: contactId));
  }

  /// Nahradí existující zprávu (dle id) — stav přílohy, doručenka…
  Future<void> updateMessage(String contactId, Message message) async {
    final conv = await loadConversation(contactId);
    if (conv == null) return;
    conv.updateMessage(message);
    await saveConversation(conv);
  }

  /// Smaže expirované mizící zprávy (v1 zjednodušení:
  /// TTL běží od času zprávy — symetrické pro obě strany bez read
  /// receiptů) včetně lokálních blobů příloh. Vrací true = něco smazáno.
  Future<bool> purgeExpiredMessages() async {
    if (!isUnlocked) return false;
    var changed = false;
    final now = DateTime.now();
    bool isExpired(Message m) =>
        m.disappearAfterSeconds != null &&
        m.timestamp
            .add(Duration(seconds: m.disappearAfterSeconds!))
            .isBefore(now);
    for (final snapshot in await loadConversations()) {
      if (!snapshot.messages.any(isExpired)) continue;
      // Konverzace se před zápisem načte znovu: mezi snímkem a zápisem
      // běží event loop (mazání blobů, příjem zpráv) a starý snímek by
      // přepsal zprávu přijatou mezitím — už ACKnutou, tedy navždy pryč.
      final conv = await loadConversation(snapshot.contactId);
      if (conv == null) continue;
      final expired = conv.messages.where(isExpired).toList();
      if (expired.isEmpty) continue;
      changed = true;
      conv.messages.removeWhere(isExpired);
      await saveConversation(conv);
      for (final m in expired) {
        final blobId = m.attachment?.blobId;
        if (blobId != null) {
          await AttachmentStore().delete(blobId);
        }
      }
    }
    return changed;
  }

  // === Nastavení (SQLCipher) ===

  Future<void> setSetting(String key, dynamic value) async {
    db.appSettingPut(key, jsonEncode(value));
  }

  Future<T?> getSetting<T>(String key) async {
    final json = db.appSettingGet(key);
    if (json == null) return null;
    return jsonDecode(json) as T?;
  }

  /// Smaž všechna data (factory reset) — DB soubor, klíče, keystore
  /// i lokální bloby příloh.
  Future<void> deleteAll() async {
    if (_decoyMode) {
      // Nátlaková relace: „smazat" smí jen prázdnou decoy DB — skutečná
      // data a keystore zůstávají (dřív to smazalo reálný účet).
      final decoyPath = await _dbPath(decoy: true);
      lock();
      await _deleteDbFiles(decoyPath);
      return;
    }
    final path = await _dbPath();
    final decoyPath = await _dbPath(decoy: true);
    lock();
    await _deleteDbFiles(path);
    await _deleteDbFiles(decoyPath);
    await AttachmentStore().deleteAll();
    await _secureStorage.deleteAll();
  }
}
