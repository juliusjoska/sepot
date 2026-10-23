/// Orchestrace zpráv — sváže SepotCrypto (libsignal), RelayClient
/// a lokální storage do jednoho toku:
///
///   odeslání:  text → content JSON → sealedEncrypt → obálka → relay
///   příjem:    DELIVER → sealedDecrypt → mapování na kontakt přes
///              fingerprint sender identity klíče → uložení → ACK
///
/// ACK se posílá až PO uložení zprávy (relay pak obálku hard-maže).
///
/// Content formát v1 = JSON uvnitř E2E ciphertextu (relay ho NIKDY nevidí):
///   text:    `{ v:1, t:'txt', id:<uuid>, txt:<text>, p:{...} }`
///   příloha: `{ v:1, t:'att', id:<uuid>, txt:<popisek?>, att:{...}, p:{...} }`
///     kde att = AttachmentMeta.toWire() (blob_id + klíč + nonce + digest
///     + mime/rozměry + inline náhled) — blob sám jde MIMO obálku přes
///     POST/GET /v1/attachments, relay vidí jen
///     šifrované bajty bez vazby na zprávu.
///   p: `{ n:<jméno>, aid:<hex accountId>, da:<b64 delivery address> }`
/// Profil `p` je self-declared KROMĚ vazby na identitu — ta je daná
/// kryptograficky (senderIdentityKey ze sealed sender decrypt).
/// TODO: content na protobuf, až se ustálí pole (mizící zprávy).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:libsignal/libsignal.dart'
    show IdentityKeyPair, PrivateKey, ProtocolAddress;
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/crypto/attachment_cipher.dart';
import 'package:sepot/core/crypto/group_admin.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/network/relay_client.dart';
import 'package:sepot/core/network/relay_transport.dart';
import 'package:sepot/core/safety/lookalike_names.dart';
import 'package:sepot/core/services/group_admin_policy.dart';
import 'package:sepot/core/services/image_processor.dart';
import 'package:sepot/core/services/typing_tracker.dart';
import 'package:sepot/core/storage/attachment_store.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/persistent_stores.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/attachment.dart';
import 'package:sepot/models/avatar_ref.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/models/poll.dart';
import 'package:sepot/proto/sepot.pb.dart' as pb;
import 'package:uuid/uuid.dart';

class MessagingService {
  MessagingService({
    required this.storage,
    this.relayUrl = AppConstants.relayUrl,
    AttachmentStore? attachments,
  }) : _attachments = attachments ?? AttachmentStore();

  final SecureStorageService storage;
  final String relayUrl;
  final AttachmentStore _attachments;

  /// UI notifikace o změně dat (nové zprávy, nový kontakt).
  void Function()? onUpdate;

  /// Přijatá zpráva (po uložení + ACK) — provider přes ni ukazuje
  /// systémovou notifikaci, když appka není v popředí.
  /// `convId` = gid u skupiny, jinak id kontaktu — podle něj se řídí
  /// ztlumení (ztlumená skupina ≠ ztlumený chat s autorem).
  void Function(Contact contact, Message message, String convId)?
      onMessageReceived;

  /// TURN údaje pro hovor (null = relay je nevydal, zkusí se jen STUN).
  Future<pb.TurnCredentials?> turnCredentials() async {
    final relay = _relay;
    if (relay == null || relay.state != RelayConnectionState.connected) {
      return null;
    }
    try {
      return await relay.requestTurn();
    } on TimeoutException {
      return null;
    }
  }

  /// Příchozí signalizace hovoru (nabídka, odpověď, zavěšení…).
  void Function(Contact contact, Map<String, dynamic> signal)? onCallSignal;

  CryptoDb? _db;
  SepotCrypto? _crypto;
  RelayClient? _relay;
  LocalIdentity? _identity;
  Uint8List? _senderCert;
  Uint8List? _trustRoot;
  DateTime? _certFetchedAt;

  /// Pinovaný trust root relaye se při obnově certu neshodoval — signál
  /// MITM / podvrženého relaye zachycený i na pozadí (kde by výjimka jinak
  /// zmizela). UI to může přečíst a varovat i mimo cestu odeslání.
  bool _trustRootMismatch = false;
  bool get trustRootMismatch => _trustRootMismatch;
  StreamSubscription<dynamic>? _deliverSub;
  StreamSubscription<RelayConnectionState>? _stateSub;
  Timer? _registerRetryTimer;
  Timer? _purgeTimer;
  StreamSubscription<int>? _prekeysLowSub;

  /// Typy E2E obsahu, které tahle verze umí zpracovat. Cokoli jiného se
  /// ACKne a zahodí (po upgradu už nejde dešifrovat znovu). Veřejná
  /// konstanta kvůli testu: v 1.2.0 tu chyběl `call` a každá nabídka
  /// hovoru se tiše zahodila — hovory vůbec nešly přijmout.
  static const knownContentTypes = {
    'txt', 'att', 'rx', 'edit', 'del', 'dlv', 'rr', 'typ', 'vote', 'call',
    ..._groupControlTypes,
  };

  /// Prodleva dalšího pokusu o registraci; roste do [_registerRetryMax].
  Duration _registerRetryDelay = const Duration(seconds: 30);
  static const _registerRetryMax = Duration(minutes: 10);

  /// Relay odmítl registraci jako konflikt identity (409) — typicky starší
  /// relay bez převzetí identity po obnově ze 24 slov. UI může vysvětlit.
  bool _registrationConflict = false;
  bool get registrationConflict => _registrationConflict;

  /// Rozpracované dodávky: `stop()` (auto-lock) na ně počká, jinak by DB
  /// zmizela mezi dešifrováním (ratchet už postoupil) a zápisem a zpráva
  /// by byla nenávratně pryč.
  int _inFlight = 0;
  Completer<void>? _drained;

  /// Operace nad ratchet stavem jdou postupně. libsignal načte relaci,
  /// šifruje a uloží ji zpět s `await` na Dart store uprostřed — dva
  /// souběžné běhy nad touž relací by odvodily stejný message key a druhá
  /// obálka by u příjemce propadla. Doručenky, „píše…“ i outbox běží
  /// `unawaited` vedle uživatelského odeslání, takže zámek je nutný.
  Future<void> _chain = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _chain.then((_) => op());
    _chain = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Nejvyšší počet znaků jména kontaktu/profilu z drátu nebo odkazu.
  static const maxDisplayNameLength = 64;

  static String clipName(String name) => name.length > maxDisplayNameLength
      ? name.substring(0, maxDisplayNameLength)
      : name;

  /// Kolik one-time prekeys doplnit, když relay hlásí nedostatek.
  static const _otpBatch = 50;
  static const _spkRotation = Duration(days: 7);
  static const _kyberRotation = Duration(days: 30);

  /// Běží právě dodatečné odeslání zaseklých zpráv? Reconnectů může přijít
  /// několik rychle za sebou a dva souběžné průchody by tutéž zprávu poslaly
  /// dvakrát.
  bool _outboxRunning = false;

  /// Transport relaye: false = přímé WSS, true = přes Tor (SOCKS5/Orbot na
  /// `.onion`). Čte se z nastavení při startu, přepíná se za běhu
  /// ([setTorEnabled]) přestavením [RelayClient].
  bool _useTor = false;
  int _socksPort = 9050;

  /// Poslední push registrace — přežije přestavení relaye (nový RelayClient
  /// začíná bez ní), aby po přepnutí Tor/přímo push dál fungoval.
  pb.RegisterPush? _lastPush;

  bool get isStarted => _crypto != null;

  // ── „píše…“ ────────────────────────────────────────────────────────
  //
  // Stejně jako potvrzení přečtení: volitelné, výchozí vypnuto, reciproční.
  // Jde šifrovaným kanálem jako obálka EPHEMERAL — relay ji doručí jen
  // živému spojení, offline příjemce se nebudí a nic se neukládá.

  static const typingSettingKey = 'typing_indicators_enabled';

  /// Nejvýš jedno „píšu“ za tuhle dobu na konverzaci.
  static const _typingThrottle = Duration(seconds: 4);

  /// Po DROPPED (příjemce offline) chvíli nic neposílat: každá zahozená
  /// obálka posune ratchet a příjemce by pak mezeru musel přeskakovat.
  static const _typingBackoff = Duration(minutes: 1);

  /// Ve větší skupině by každé „píšu“ znamenalo desítky obálek.
  static const _typingMaxGroup = 20;

  final typing = TypingTracker();
  final _typingSentAt = <String, DateTime>{};
  final _typingBackoffUntil = <String, DateTime>{};

  Future<bool> _typingEnabled() async =>
      (await storage.getSetting<bool>(typingSettingKey)) ?? false;

  /// Dá protistraně (členům skupiny) vědět, že píšu. Volat při psaní —
  /// omezení frekvence řeší metoda sama. Best-effort, nikdy nehází.
  Future<void> sendTyping(String convId) async {
    if (!isStarted || !await _typingEnabled()) return;
    final now = DateTime.now();
    final last = _typingSentAt[convId];
    if (last != null && now.difference(last) < _typingThrottle) return;
    _typingSentAt[convId] = now;

    final group = await storage.loadGroup(convId);
    if (group != null &&
        (group.left || group.memberIds.length > _typingMaxGroup)) {
      return;
    }
    final contacts = await storage.loadContacts();
    final targets = contacts.where((c) =>
        !c.blocked &&
        (group == null
            ? c.id == convId && c.accepted
            : group.memberIds.contains(c.id) && c.id != _identity?.id));
    for (final c in targets) {
      final until = _typingBackoffUntil[c.id];
      if (until != null && until.isAfter(now)) continue;
      unawaited(_sendTypingTo(c, group?.id));
    }
  }

  Future<void> _sendTypingTo(Contact contact, String? gid) async {
    try {
      final status = await _sendSealed(
        contact,
        {
          'v': 1,
          'id': const Uuid().v4(),
          't': 'typ',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'gid': ?gid,
        },
        ephemeral: true,
      );
      if (status == pb.Receipt_Status.STATUS_DROPPED) {
        _typingBackoffUntil[contact.id] =
            DateTime.now().add(_typingBackoff);
      } else {
        _typingBackoffUntil.remove(contact.id);
      }
    } catch (_) {
      // „píše…“ je jen ozdoba — výpadek sítě nesmí nic rozbít ani hlásit.
    }
  }
  bool get isTorEnabled => _useTor;
  RelayConnectionState get connectionState =>
      _relay?.state ?? RelayConnectionState.disconnected;
  Stream<RelayConnectionState>? get connectionStream => _relay?.stateStream;

  String? get accountId {
    final aid = _db?.kvGet('account_id');
    return aid == null ? null : utf8.decode(aid);
  }

  Uint8List? get myDeliveryAddress => _db?.kvGet('delivery_address');

  /// Nastartuje krypto vrstvu a spojení. Volat po odemčení aplikace
  /// (existující identita) i po dokončení onboardingu.
  ///
  /// DB je sdílená se [SecureStorageService] — storage musí být odemčený
  /// jinak StateError. Selhání sítě NEshodí start — registrace/
  /// připojení se opakují na pozadí; krypto a lokální data fungují okamžitě.
  Future<void> start(LocalIdentity identity) async {
    if (isStarted) return;
    _identity = identity;

    final db = storage.db;
    _db = db;

    // registration ID: 1..16380, jednou vygenerovat a držet
    final regIdRaw = db.kvGet('registration_id');
    final int regId;
    if (regIdRaw == null) {
      regId = 1 +
          (RelayClient.randomBytes(2).buffer.asByteData().getUint16(0) %
              16380);
      db.kvPut('registration_id', utf8.encode(regId.toString()));
    } else {
      regId = int.parse(utf8.decode(regIdRaw));
    }

    _myAvatar = AvatarRef.fromJson(
        await storage.getSetting<Map<String, dynamic>>(_myAvatarKey));

    // Transport podle uloženého nastavení (odemčený storage — čte se z DB).
    _useTor = (await storage.getSetting<bool>('tor_enabled')) ?? false;
    _socksPort = (await storage.getSetting<int>('tor_socks_port')) ?? 9050;

    final existingAccount = accountId;
    final crypto = SepotCrypto.fromPrivateKey(
      privateKey: identity.identityPrivateKey,
      accountId: existingAccount ?? 'unbound',
      registrationId: regId,
      storesFactory: (IdentityKeyPair keyPair) => SepotStores(
        session: DbSessionStore(db),
        identity: DbIdentityKeyStore(
          db,
          identityKeyPair: keyPair,
          registrationId: regId,
        ),
        preKey: DbPreKeyStore(db),
        signedPreKey: DbSignedPreKeyStore(db),
        kyberPreKey: DbKyberPreKeyStore(db),
      ),
    );
    _crypto = crypto;

    final relay = _buildRelay();
    _relay = relay;
    _deliverSub = relay.deliveries.listen(_onDeliver);
    _prekeysLowSub = relay.prekeysLow.listen(_replenishPreKeys);
    // Po každém (re)connectu dorazit, co zůstalo viset ve frontě odchozích.
    _stateSub = relay.stateStream.listen((state) {
      if (state == RelayConnectionState.connected) {
        unawaited(_flushOutbox());
        unawaited(_refreshMyAvatarIfOld());
        unawaited(_rotatePreKeysIfDue());
      }
    });

    if (existingAccount != null) {
      relay.restoreSession(
        accountId: existingAccount,
        deviceUuid: utf8.decode(db.kvGet('device_uuid')!),
      );
      relay.start();
      // Na pozadí: TrustRootChangedError by jinak byla neošetřená async
      // výjimka — zachytíme ji do flagu, síťové chyby řeší _refreshSenderCert.
      unawaited(_refreshSenderCert().catchError((Object e) {
        if (e is TrustRootChangedError) _trustRootMismatch = true;
      }));
    } else {
      unawaited(_registerWithRetry());
    }

    // Mizící zprávy: úklid hned po startu a pak průběžně
    unawaited(_purgeExpired());
    _purgeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _purgeExpired(),
    );
  }

  /// Sestaví [RelayClient] podle aktuálního transportu. Tor jede na
  /// `.onion` (Tor obálka šifruje), přímý režim na výchozí `relayUrl`.
  RelayClient _buildRelay() {
    final url = _useTor ? AppConstants.relayOnion : relayUrl;
    final transport = _useTor
        ? TorTransport(socksPort: _socksPort)
        : DirectTransport();
    return RelayClient(baseUrl: url, crypto: _crypto!, transport: transport);
  }

  /// Zapne/vypne routování přes Tor. Uloží volbu a — pokud služba běží —
  /// přestaví spojení na `.onion`/přímé bez nutnosti restartu appky.
  /// Krypto stav, identita ani pinovaný trust root se nemění.
  Future<void> setTorEnabled(bool enabled, {int socksPort = 9050}) async {
    await storage.setSetting('tor_enabled', enabled);
    await storage.setSetting('tor_socks_port', socksPort);
    if (!isStarted) {
      _useTor = enabled;
      _socksPort = socksPort;
      return;
    }
    if (_useTor == enabled && _socksPort == socksPort) return;
    _useTor = enabled;
    _socksPort = socksPort;
    await _rebuildRelay();
  }

  /// Zahodí starý [RelayClient] (i s jeho transportem) a nastartuje nový.
  /// Sender certifikát se zneplatní (vyzvedne se přes nový transport);
  /// push registrace se znovu odešle. Trust root zůstává pinovaný.
  Future<void> _rebuildRelay() async {
    await _deliverSub?.cancel();
    await _stateSub?.cancel();
    await _relay?.dispose();
    _senderCert = null;
    _certFetchedAt = null;

    final relay = _buildRelay();
    _relay = relay;
    _deliverSub = relay.deliveries.listen(_onDeliver);
    _prekeysLowSub = relay.prekeysLow.listen(_replenishPreKeys);
    // Po každém (re)connectu dorazit, co zůstalo viset ve frontě odchozích.
    _stateSub = relay.stateStream.listen((state) {
      if (state == RelayConnectionState.connected) {
        unawaited(_flushOutbox());
        unawaited(_refreshMyAvatarIfOld());
        unawaited(_rotatePreKeysIfDue());
      }
    });

    final existingAccount = accountId;
    if (existingAccount != null) {
      relay.restoreSession(
        accountId: existingAccount,
        deviceUuid: utf8.decode(_db!.kvGet('device_uuid')!),
      );
      relay.start();
      // Na pozadí: TrustRootChangedError by jinak byla neošetřená async
      // výjimka — zachytíme ji do flagu, síťové chyby řeší _refreshSenderCert.
      unawaited(_refreshSenderCert().catchError((Object e) {
        if (e is TrustRootChangedError) _trustRootMismatch = true;
      }));
      if (_lastPush != null) relay.registerPush(_lastPush!);
    } else {
      unawaited(_registerWithRetry());
    }
  }

  Future<void> _purgeExpired() async {
    try {
      if (await storage.purgeExpiredMessages()) {
        onUpdate?.call();
      }
    } catch (_) {
      // best-effort — sweep nesmí shodit messaging
    }
  }

  Future<void> _registerWithRetry() async {
    try {
      await _register();
    } on RelayException catch (e) {
      // 409 = identita na relayi existuje a relay neumí převzetí (starší
      // verze). Opakovat má smysl (relay se aktualizuje), ale ne každých
      // 30 s navždy — a UI má vědět proč.
      _registrationConflict = e.statusCode == 409;
      _scheduleRegisterRetry();
      return;
    } catch (_) {
      _scheduleRegisterRetry();
      return;
    }
    _registrationConflict = false;
    _registerRetryDelay = const Duration(seconds: 30);
    _relay!.start();
    await _refreshSenderCert();
  }

  void _scheduleRegisterRetry() {
    _registerRetryTimer?.cancel();
    _registerRetryTimer = Timer(_registerRetryDelay, _registerWithRetry);
    final doubled = _registerRetryDelay * 2;
    _registerRetryDelay =
        doubled > _registerRetryMax ? _registerRetryMax : doubled;
    onUpdate?.call();
  }

  int? _kvInt(CryptoDb db, String key) {
    final raw = db.kvGet(key);
    return raw == null ? null : int.tryParse(utf8.decode(raw));
  }

  /// Relay po AUTH hlásí docházející one-time prekeys → vygenerovat dávku
  /// a nahrát. Bez toho byl účet po vyčerpání zásoby natrvalo bez OTP
  /// a každá nová relace k němu běžela bez jednorázového klíče.
  Future<void> _replenishPreKeys(int remaining) async {
    final db = _db;
    final crypto = _crypto;
    final relay = _relay;
    if (db == null || crypto == null || relay == null || accountId == null) {
      return;
    }
    try {
      // Registrace nahrála id 1–100; další dávky navazují.
      final next = _kvInt(db, 'otp_next_id') ?? 101;
      final otps = await _serial(
          () => crypto.generateOneTimePreKeys(startId: next, count: _otpBatch));
      await relay.uploadKeys(oneTimePreKeys: otps);
      db.kvPut('otp_next_id', utf8.encode('${next + _otpBatch}'));
    } catch (_) {
      // Síť / starší relay bez /v1/keys — relay to zopakuje po dalším AUTH.
    }
  }

  /// Rotace signed prekey (týdně) a last-resort Kyber prekey (měsíčně),
  /// Staré klíče zůstávají ve store — relace z bundle
  /// staženého těsně před rotací je ještě potřebují.
  Future<void> _rotatePreKeysIfDue() async {
    final db = _db;
    final crypto = _crypto;
    final relay = _relay;
    if (db == null || crypto == null || relay == null || accountId == null) {
      return;
    }
    final now = DateTime.now();
    bool due(String key, Duration period) {
      final at = _kvInt(db, key);
      return at == null ||
          now.difference(DateTime.fromMillisecondsSinceEpoch(at)) > period;
    }

    final spkDue = due('spk_rotated_at', _spkRotation);
    final kyberDue = due('kyber_rotated_at', _kyberRotation);
    if (!spkDue && !kyberDue) return;
    try {
      SepotSignedPreKey? spk;
      SepotKyberPreKey? kyber;
      if (spkDue) {
        final id = _kvInt(db, 'spk_next_id') ?? 2;
        spk = await _serial(() => crypto.generateSignedPreKey(
            id: id, timestampMs: now.millisecondsSinceEpoch));
      }
      if (kyberDue) {
        final id = _kvInt(db, 'kyber_next_id') ?? 2;
        kyber = await _serial(() => crypto.generateKyberPreKey(
            id: id, timestampMs: now.millisecondsSinceEpoch));
      }
      await relay.uploadKeys(signedPreKey: spk, kyberPreKey: kyber);
      final stamp = utf8.encode('${now.millisecondsSinceEpoch}');
      db.transaction(() {
        if (spk != null) {
          db.kvPut('spk_next_id', utf8.encode('${spk.id + 1}'));
          db.kvPut('spk_rotated_at', stamp);
        }
        if (kyber != null) {
          db.kvPut('kyber_next_id', utf8.encode('${kyber.id + 1}'));
          db.kvPut('kyber_rotated_at', stamp);
        }
      });
    } catch (_) {
      // Starší relay bez /v1/keys nebo offline — zkusí se po dalším connectu.
    }
  }

  Future<void> _register() async {
    final db = _db!;
    final crypto = _crypto!;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final bundle = await crypto.generatePreKeyBundle(
      preKeyId: 1,
      signedPreKeyId: 1,
      kyberPreKeyId: 1,
      timestampMs: nowMs,
    );
    // bundle nese OTP id 1; dalších 99 do zásoby
    final otps = await crypto.generateOneTimePreKeys(startId: 2, count: 99);
    final deliveryAddress = RelayClient.randomBytes(32);

    final reg = await _relay!.register(
      bundle: bundle,
      oneTimePreKeys: [
        SepotOneTimePreKey(id: bundle.preKeyId!, publicKey: bundle.preKeyPublic!),
        ...otps,
      ],
      deliveryAddress: deliveryAddress,
    );

    final stamp = utf8.encode('$nowMs');
    db.transaction(() {
      db.kvPut('account_id', utf8.encode(reg.accountId));
      db.kvPut('device_uuid', utf8.encode(reg.deviceUuid));
      db.kvPut('delivery_address', deliveryAddress);
      // Id pro doplňování a rotace klíčů navazují na registraci.
      db.kvPut('otp_next_id', utf8.encode('101'));
      db.kvPut('spk_next_id', utf8.encode('2'));
      db.kvPut('kyber_next_id', utf8.encode('2'));
      db.kvPut('spk_rotated_at', stamp);
      db.kvPut('kyber_rotated_at', stamp);
    });
    onUpdate?.call();
  }

  Future<void> _refreshSenderCert() async {
    try {
      final (cert, trustRoot) = await _relay!.fetchSenderCertificate();
      final pinned = _db!.kvGet('trust_root');
      if (pinned == null) {
        _db!.kvPut('trust_root', trustRoot);
      } else if (!_listEquals(pinned, trustRoot)) {
        // Jiný trust root = jiný relay / MITM — tvrdě odmítnout
        throw const TrustRootChangedError();
      }
      _senderCert = cert;
      _trustRoot = Uint8List.fromList(pinned ?? trustRoot);
      _certFetchedAt = DateTime.now();
    } on TrustRootChangedError {
      // Bezpečnostní signál (MITM / podvržený relay), ne přechodná chyba —
      // propustíme dál. Cert se nepřijal, takže první odeslání skončí touž
      // výjimkou i ve viditelné cestě a UI ji ukáže. Pozadové (unawaited)
      // volání ji zachytí do `trustRootMismatch`.
      rethrow;
    } on Object {
      // Síť/offline/timeout: fetchSenderCertificate může hodit i
      // SocketException/ClientException (http bez timeoutu, běžný offline
      // start), nejen RelayException. Spolkneme — zkusí se při odeslání.
    }
  }

  Future<Uint8List> _senderCertificate() async {
    final stale = _certFetchedAt == null ||
        DateTime.now().difference(_certFetchedAt!) >
            const Duration(hours: 12);
    if (_senderCert == null || stale) {
      await _refreshSenderCert();
    }
    final cert = _senderCert;
    if (cert == null) {
      throw const RelayUnavailableError();
    }
    return cert;
  }

  // ── Odeslání ────────────────────────────────────────────────────────

  /// S [poll] je [text] záložní podoba ankety pro starší appky.
  Future<Message> sendText(Contact contact, String text,
      {String? replyToId, Poll? poll}) async {
    final identity = _identity ?? (throw StateError('Service not started'));
    final ttl = await _conversationTtl(contact.id);

    // Optimisticky ulož jako „odesílá se" (⏱ hned v UI), pak přepni podle
    // reálného potvrzení relaye.
    final message = Message.text(
      senderId: identity.id,
      recipientId: contact.id,
      content: text,
      replyToId: replyToId,
      disappearAfterSeconds: ttl,
      status: MessageStatus.sending,
      poll: poll,
    );
    await storage.addMessage(contact.id, message);
    onUpdate?.call();

    try {
      final delivered = await _sendContent(contact, {
        'v': 1,
        't': 'txt',
        'id': message.id,
        'ts': message.timestamp.millisecondsSinceEpoch,
        'txt': text,
        're': ?replyToId,
        'ttl': ?ttl,
        'poll': ?poll?.toWire(),
        'p': _profile(),
      });
      final sent = message.copyWith(
        isDelivered: delivered,
        status: delivered ? MessageStatus.delivered : MessageStatus.sent,
      );
      await storage.updateMessage(contact.id, sent);
      onUpdate?.call();
      return sent;
    } catch (e) {
      await storage.updateMessage(
          contact.id, message.copyWith(status: MessageStatus.failed));
      onUpdate?.call();
      rethrow;
    }
  }

  /// Odešle přílohu: obrázky se nejdřív re-enkódují (EXIF/GPS pryč,
  /// max 2048 px) a dostanou inline náhled; dokumenty jdou beze změny.
  /// Blob se šifruje per-file klíčem, nahraje na relay a lokálně se drží
  /// STEJNÝ šifrovaný blob (odesílatel i příjemce renderují touž cestou).
  Future<Message> sendAttachment(
    Contact contact, {
    required Uint8List bytes,
    required String fileName,
    String? mime,
    String? caption,
    int? durationMs,
  }) async {
    final identity = _identity ?? (throw StateError('Service not started'));
    final meta = await _prepareAttachment(
      bytes: bytes,
      fileName: fileName,
      mime: mime,
      durationMs: durationMs,
    );

    final ttl = await _conversationTtl(contact.id);
    final message = Message.attachment(
      senderId: identity.id,
      recipientId: contact.id,
      attachment: meta,
      caption: caption,
      disappearAfterSeconds: ttl,
      status: MessageStatus.sending,
    );
    await storage.addMessage(contact.id, message);
    onUpdate?.call();

    // Stejné ošetření jako u textu: bez něj zůstala příloha po výpadku
    // spojení viset na „odesílá se" navždy. Označit jako failed ji dostane
    // do fronty odchozích ([_flushOutbox]) — blob je na relayi nahraný,
    // dosílá se jen meta.
    try {
      final delivered = await _sendContent(contact, {
        'v': 1,
        't': 'att',
        'id': message.id,
        'ts': message.timestamp.millisecondsSinceEpoch,
        if (caption != null && caption.isNotEmpty) 'txt': caption,
        'ttl': ?ttl,
        'att': meta.toWire(),
        'p': _profile(),
      });

      final sent = message.copyWith(
        isDelivered: delivered,
        status: delivered ? MessageStatus.delivered : MessageStatus.sent,
      );
      await storage.updateMessage(contact.id, sent);
      onUpdate?.call();
      return sent;
    } catch (_) {
      await storage.updateMessage(
          contact.id, message.copyWith(status: MessageStatus.failed));
      onUpdate?.call();
      rethrow;
    }
  }

  /// Zpracuje a nahraje přílohu: obrázky re-enkóduje (EXIF/GPS pryč,
  /// max 2048 px) a přidá inline náhled; blob zašifruje per-file klíčem,
  /// nahraje na relay a lokálně uloží. Meta pak jede E2E kanálem —
  /// u skupin STEJNÁ meta všem členům (blob se nahrává jen jednou).
  Future<AttachmentMeta> _prepareAttachment({
    required Uint8List bytes,
    required String fileName,
    String? mime,
    int? durationMs,
    bool upload = true,
  }) async {
    final guessedMime = mime ??
        lookupMimeType(fileName, headerBytes: bytes) ??
        'application/octet-stream';

    var payload = bytes;
    var finalMime = guessedMime;
    String? name = fileName;
    int? width;
    int? height;
    String? thumbB64;

    if (guessedMime.startsWith('image/')) {
      final processed =
          await ImageProcessor.process(bytes, mimeHint: guessedMime);
      if (processed != null) {
        payload = processed.bytes;
        finalMime = processed.mime;
        width = processed.width;
        height = processed.height;
        thumbB64 = base64Encode(processed.thumbnailJpeg);
        // Původní název fotky ven nejde (bývá v něm datum/čas focení)
        name = null;
      }
    }

    if (payload.length > AppConstants.maxAttachmentBytes) {
      throw const AttachmentTooLargeError(AppConstants.maxAttachmentBytes);
    }

    final encrypted = await AttachmentCipher.encrypt(payload);
    final blobId = upload
        ? await _relay!.uploadAttachment(encrypted.blob)
        : _localBlobId();
    await _attachments.save(blobId, encrypted.blob);

    return AttachmentMeta(
      blobId: blobId,
      keyB64: base64Encode(encrypted.key),
      nonceB64: base64Encode(encrypted.nonce),
      digestB64: base64Encode(encrypted.digest),
      size: encrypted.plaintextSize,
      mime: finalMime,
      name: name,
      width: width,
      height: height,
      thumbB64: thumbB64,
      durationMs: durationMs,
      state: AttachmentTransferState.ready,
    );
  }

  /// Příloha poznámky pro sebe: stejné zpracování i šifrování jako při
  /// odeslání, ale blob zůstane jen v telefonu — na relay nemá co dělat.
  Future<AttachmentMeta> prepareNoteAttachment({
    required Uint8List bytes,
    required String fileName,
    String? mime,
    int? durationMs,
  }) =>
      _prepareAttachment(
        bytes: bytes,
        fileName: fileName,
        mime: mime,
        durationMs: durationMs,
        upload: false,
      );

  /// Stejný tvar jako id blobu na relayi (32 hex), aby úložiště příloh
  /// nemuselo rozlišovat původ.
  String _localBlobId() {
    final rnd = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// TTL mizících zpráv nastavené na konverzaci (null = vypnuto).
  Future<int?> _conversationTtl(String contactId) async {
    final conv = await storage.loadConversation(contactId);
    return conv?.disappearAfterSeconds;
  }

  Map<String, dynamic> _profile() {
    final identity = _identity!;
    final da = myDeliveryAddress;
    return {
      'n': identity.displayName,
      'aid': ?accountId,
      // Do doběhnutí vlastní registrace na relay ještě routing nemáme —
      // pole vynecháme (protistrana ho doplní z pozdějšího profilu), NIKDY
      // `da!` (null-check pád = „Null check operator used on a null value").
      'da': ?(da == null ? null : base64Encode(da)),
      // Profil BEZ 'av' = fotku jsem odebral (protistrana ji smaže).
      'av': ?_myAvatar?.toWire(),
    };
  }

  // ── Profilová fotka ─────────────────────────────────────────────────

  static const _myAvatarKey = 'my_avatar';

  /// Blob na relayi žije 30 dní — s týdenní rezervou se nahraje znovu,
  /// aby ho stáhli i lidé, kteří mi napíšou poprvé až za měsíc.
  static const _avatarRefreshAfter = Duration(days: 23);

  AvatarRef? _myAvatar;
  final _avatarCache = <String, Uint8List>{};

  AvatarRef? get myAvatar => _myAvatar;

  /// Nastaví moji fotku ([jpeg] už zmenšený a bez metadat). Protistrany
  /// se o ní dozví s další zprávou (odkaz jede v profilu).
  Future<void> setMyAvatar(Uint8List jpeg) async {
    final relay = _relay ?? (throw StateError('Service not started'));
    final encrypted = await AttachmentCipher.encrypt(jpeg);
    final blobId = await relay.uploadAttachment(encrypted.blob);
    await _attachments.save(blobId, encrypted.blob);
    final old = _myAvatar;
    _myAvatar = AvatarRef(
      blobId: blobId,
      key: encrypted.key,
      nonce: encrypted.nonce,
      digest: encrypted.digest,
      uploadedAt: DateTime.now(),
    );
    await storage.setSetting(_myAvatarKey, _myAvatar!.toJson());
    _avatarCache[blobId] = jpeg;
    if (old != null) await _forgetAvatar(old);
    onUpdate?.call();
  }

  Future<void> removeMyAvatar() async {
    final old = _myAvatar;
    if (old == null) return;
    _myAvatar = null;
    await storage.setSetting(_myAvatarKey, null);
    await _forgetAvatar(old);
    onUpdate?.call();
  }

  Future<void> _forgetAvatar(AvatarRef ref) async {
    _avatarCache.remove(ref.blobId);
    await _attachments.delete(ref.blobId);
  }

  /// Znovu nahraje TENTÝŽ šifrovaný blob pod novým id (klíč se nemění),
  /// než na relayi vyprší. Best-effort — zkusí se při dalším připojení.
  Future<void> _refreshMyAvatarIfOld() async {
    final ref = _myAvatar;
    final relay = _relay;
    if (ref == null || relay == null) return;
    final uploaded = ref.uploadedAt;
    if (uploaded != null &&
        DateTime.now().difference(uploaded) < _avatarRefreshAfter) {
      return;
    }
    try {
      final blob = await _attachments.load(ref.blobId);
      if (blob == null) return;
      final blobId = await relay.uploadAttachment(blob);
      await _attachments.save(blobId, blob);
      _myAvatar = AvatarRef(
        blobId: blobId,
        key: ref.key,
        nonce: ref.nonce,
        digest: ref.digest,
        uploadedAt: DateTime.now(),
      );
      await storage.setSetting(_myAvatarKey, _myAvatar!.toJson());
      await _attachments.delete(ref.blobId);
    } catch (_) {
      // Bez sítě / relay ještě nezná zařízení — zkusí se příště.
    }
  }

  /// Stáhne fotku kontaktu, ověří velikost a digest a uloží ji šifrovanou.
  Future<void> _downloadAvatar(AvatarRef ref) async {
    final relay = _relay;
    if (relay == null || await _attachments.exists(ref.blobId)) return;
    try {
      final blob = await relay.downloadAttachment(ref.blobId);
      if (blob.length > AvatarRef.maxBlobBytes) return;
      final digest = await AttachmentCipher.sha256(blob);
      if (!_listEquals(digest, ref.digest)) return;
      await _attachments.save(ref.blobId, blob);
      onUpdate?.call();
    } catch (_) {
      // Blob vypršel nebo síť selhala — ukáží se iniciály, další profil
      // (s obnoveným blobem) to zkusí znovu.
    }
  }

  /// Dešifrovaná fotka pro UI (null = není stažená / vadná → iniciály).
  Future<Uint8List?> loadAvatar(AvatarRef ref) async {
    final cached = _avatarCache[ref.blobId];
    if (cached != null) return cached;
    final blob = await _attachments.load(ref.blobId);
    if (blob == null) {
      unawaited(_downloadAvatar(ref));
      return null;
    }
    try {
      final bytes = await AttachmentCipher.decrypt(
        blob: blob,
        key: ref.key,
        nonce: ref.nonce,
        expectedDigest: ref.digest,
      );
      _avatarCache[ref.blobId] = bytes;
      return bytes;
    } on Object {
      return null;
    }
  }

  // ── Reakce / editace / mazání (control zprávy) ──────────────────────
  //
  // Nevytvářejí novou bublinu — mění existující zprávu podle jejího id
  // (`ref`). Poctivá hranice jako u mizících zpráv: je to dohoda klientů,
  // protistrana mohla obsah už vidět.

  /// Můj fingerprint (klíč do mapy reakcí).
  String get _myFingerprint => _identity!.fingerprint.display;

  /// Přidá/odebere moji reakci na zprávu. `emoji == null` = odebrat.
  Future<void> sendReaction(
      Contact contact, String targetId, String? emoji) async {
    await _mutateLocalMessage(contact.id, targetId, (m) {
      final r = Map<String, String>.from(m.reactions);
      if (emoji == null) {
        r.remove(_myFingerprint);
      } else {
        r[_myFingerprint] = emoji;
      }
      return m.copyWith(reactions: r);
    });
    await _sendControl(contact, {
      't': 'rx',
      'ref': targetId,
      'e': ?emoji,
    });
  }

  /// Upraví text mojí odeslané zprávy.
  Future<void> editMessage(
      Contact contact, String targetId, String newText) async {
    await _mutateLocalMessage(contact.id, targetId,
        (m) => m.copyWith(content: newText, editedAt: DateTime.now()));
    await _sendControl(contact, {'t': 'edit', 'ref': targetId, 'txt': newText});
  }

  /// Pošle odesílateli potvrzení přečtení pro dané zprávy — jen když mám
  /// read receipts ZAPNUTÉ (default vypnuto). Best-effort. Ve skupině
  /// (`gid`) jde jen autorovi zpráv, ne všem členům.
  Future<void> sendReadReceipts(Contact contact, List<String> messageIds,
      {String? gid}) async {
    if (messageIds.isEmpty) return;
    // Neznámý odesílatel se nedozví, že jsem jeho zprávu otevřel.
    if (gid == null && !contact.accepted) return;
    final enabled =
        (await storage.getSetting<bool>('read_receipts_enabled')) ?? false;
    if (!enabled) return;
    await _sendControl(contact, {'t': 'rr', 'ids': messageIds, 'gid': ?gid});
  }

  /// Smaže zprávu pro všechny (tombstone u obou stran).
  Future<void> deleteMessage(Contact contact, String targetId) async {
    await _mutateLocalMessage(contact.id, targetId,
        (m) => m.copyWith(isDeleted: true, content: '', reactions: const {}));
    await _sendControl(contact, {'t': 'del', 'ref': targetId});
  }

  /// Odešle control zprávu (best-effort; lokální změna už proběhla).
  Future<void> _sendControl(
      Contact contact, Map<String, dynamic> extra) async {
    try {
      await _sendContent(contact, {
        'v': 1,
        'id': const Uuid().v4(),
        // Čas vzniku, ne doručení — potvrzení přečtení z offline telefonu
        // má ukázat, kdy si to člověk přečetl, ne kdy se připojil.
        'ts': DateTime.now().millisecondsSinceEpoch,
        ...extra,
        'p': _profile(),
      });
    } catch (_) {
      // síť selhala — lokální stav zůstává, protistrana se dozví později
      // jen když znovu odešleme (v1: bez retry fronty pro control zprávy)
    }
  }

  /// Signalizace hovoru (`t:'call'`). Na rozdíl od ostatních
  /// řídicích zpráv chybu nepolyká — hovor, který neodešel, musí UI ukončit.
  /// [ring] = nabídka: relay offline příjemce budí VoIP pushem.
  Future<pb.Receipt_Status?> sendCallSignal(
    Contact contact,
    Map<String, dynamic> signal, {
    bool ring = false,
  }) {
    final content = {
      'v': 1,
      'id': const Uuid().v4(),
      'ts': DateTime.now().millisecondsSinceEpoch,
      't': 'call',
      ...signal,
    };
    final tap = debugSendTap;
    if (tap != null) {
      tap(contact.id, content);
      return Future.value(pb.Receipt_Status.STATUS_DELIVERED_ONLINE);
    }
    return _sendSealed(contact, content, ring: ring);
  }

  /// Najde zprávu podle id v konverzaci a aplikuje transformaci.
  Future<void> _mutateLocalMessage(String contactId, String messageId,
      Message Function(Message) transform) async {
    final conv = await storage.loadConversation(contactId);
    if (conv == null) return;
    final i = conv.messages.indexWhere((m) => m.id == messageId);
    if (i < 0) return;
    await storage.updateMessage(contactId, transform(conv.messages[i]));
    onUpdate?.call();
  }

  // ── Skupiny (párový fanout) ─────────────────────────────────────────

  static const _groupControlTypes = {'ginv', 'gleave', 'gmeta', 'gop', 'gsync'};
  //
  // Skupina nemá vlastní krypto vrstvu — každá zpráva jede existujícím
  // párovým Double Ratchet kanálem každému členovi zvlášť (`gid` v E2E
  // obsahu ji směruje do skupinové konverzace). Autor = sealed-sender
  // fingerprint, nikdy self-declared pole.

  /// Založí skupinu a rozešle pozvánku (`ginv` s úplným rosterem). Pozvánka
  /// nese i podepsaný stav epochy 0, takže v2 členové znají správce hned;
  /// v1 členové použijí samotný `ginv`.
  /// Všichni členové musí mít routing (aid+da) — bez něj jim fanout
  /// nemá kam doručit.
  Future<Group> createGroup(String name, List<Contact> members) async {
    if (_identity == null) throw StateError('Service not started');
    if (members.isEmpty) throw const GroupNeedsMemberError();
    if (members.length + 1 > Group.maxMembers) {
      throw GroupTooLargeError(Group.maxMembers);
    }
    for (final m in members) {
      final p = m.publicIdentity;
      if (p.accountId == null || p.deliveryAddress == null) {
        throw MemberNoDeliveryAddressError(m.displayName);
      }
    }

    final group = Group(
      id: const Uuid().v4(),
      name: name.trim(),
      memberIds: [_myFingerprint, ...members.map((m) => m.id)],
      createdBy: _myFingerprint,
    );
    await storage.saveGroup(group);
    // Konverzace vznikne prvním addMessage; založ ji hned, ať je v chat
    // listu vidět i prázdná skupina.
    await storage.ensureConversation(group.id);
    onUpdate?.call();

    final genesis = GroupAdminOp(
      gid: group.id,
      epoch: 0,
      action: GroupAdminAction.add,
      actor: _myFingerprint,
      members: group.memberIds,
      admins: group.admins,
      name: group.name,
      prev: Uint8List(0),
    );
    await _fanoutInvite(group, op: _signOp(genesis));
    return group;
  }

  /// Přidá členy: rozšíří roster a rozešle nový úplný stav VŠEM členům
  /// (noví z něj poprvé uvidí skupinu). Správce přidává podepsanou
  /// operací; ne-správce jen v kompatibilním režimu starým `ginv`, jak to
  /// v1 klienti ve skupině stejně umějí.
  Future<void> addGroupMembers(Group group, List<Contact> added) async {
    final ids = {...group.memberIds};
    for (final m in added) {
      final p = m.publicIdentity;
      if (p.accountId == null || p.deliveryAddress == null) {
        throw MemberNoDeliveryAddressError(m.displayName);
      }
      ids.add(m.id);
    }
    if (ids.length > Group.maxMembers) {
      throw GroupTooLargeError(Group.maxMembers);
    }
    if (group.isAdmin(_myFingerprint)) {
      await _publishAdminOp(
        group,
        buildGroupOp(
          group: group,
          me: _myFingerprint,
          action: GroupAdminAction.add,
          members: ids.toList(),
        ),
      );
      return;
    }
    if (group.isEnforced(_myFingerprint)) throw const NotGroupAdminError();
    group.memberIds = ids.toList();
    await storage.saveGroup(group);
    onUpdate?.call();
    await _fanoutInvite(group);
  }

  /// Odebere člena (jen správce). Odebraný dostane výsledný stav taky —
  /// v2 klient se z něj dozví, že ve skupině už není.
  Future<void> removeGroupMember(Group group, String fingerprint) async {
    if (fingerprint == _myFingerprint) return leaveGroup(group);
    await _publishAdminOp(
      group,
      buildGroupOp(
        group: group,
        me: _myFingerprint,
        action: GroupAdminAction.remove,
        members: group.memberIds.where((f) => f != fingerprint).toList(),
        admins: group.admins.where((f) => f != fingerprint).toList(),
      ),
    );
  }

  /// Udělí nebo odebere roli správce (jen správce). Sebe smí správce
  /// degradovat, jen když zůstane jiný správce.
  Future<void> setGroupAdmin(
      Group group, String fingerprint, bool admin) async {
    if (!group.isMember(fingerprint)) return;
    if (group.isAdmin(fingerprint) == admin) return;
    await _publishAdminOp(
      group,
      buildGroupOp(
        group: group,
        me: _myFingerprint,
        action: admin ? GroupAdminAction.promote : GroupAdminAction.demote,
        admins: admin
            ? [...group.admins, fingerprint]
            : group.admins.where((f) => f != fingerprint).toList(),
      ),
    );
  }

  /// Přejmenuje skupinu (jen správce; lokálně hned, členům best-effort).
  Future<void> renameGroup(Group group, String newName) async {
    await _publishAdminOp(
      group,
      buildGroupOp(
        group: group,
        me: _myFingerprint,
        action: GroupAdminAction.rename,
        name: newName.trim(),
      ),
    );
  }

  /// Opustí skupinu: oznámí členům `gleave`, lokálně označí `left`
  /// (historie zůstává, vstup i příjem jsou mrtvé).
  ///
  /// Správce navíc odchod podepíše jako odebrání sebe sama, aby v2 členové
  /// zůstali na stejném řetězu. Kdyby odcházel poslední správce, předá
  /// roli nejmenšímu fingerprintu — tomu, koho by si bez podpisu stejně
  /// vybrali všichni přes Group.normalizeAdmins, takže `gleave` i podepsaná
  /// operace vedou ke stejnému výsledku.
  Future<void> leaveGroup(Group group) async {
    final others = group.memberIds.where((f) => f != _myFingerprint).toList();
    if (group.isAdmin(_myFingerprint) && others.isNotEmpty) {
      var admins = group.admins.where((f) => f != _myFingerprint).toList();
      if (admins.isEmpty) admins = [([...others]..sort()).first];
      await _publishAdminOp(
        group,
        buildGroupOp(
          group: group,
          me: _myFingerprint,
          action: GroupAdminAction.remove,
          members: others,
          admins: admins,
        ),
      );
    }
    await _fanoutToGroup(
      group,
      {
        'v': 1,
        't': 'gleave',
        'id': const Uuid().v4(),
        'gid': group.id,
        'p': _profile(),
      },
      recipients: others,
    );
    group.left = true;
    group.memberIds = others;
    group.normalizeAdmins();
    await storage.saveGroup(group);
    onUpdate?.call();
  }

  /// Odešle text do skupiny. Sémantika stavu: aspoň jeden
  /// člen přijal → `sent`; všichni selhali → `failed`; `delivered` až po
  /// první doručence.
  Future<Message> sendGroupText(Group group, String text,
      {String? replyToId, Poll? poll, List<String> mentions = const []}) async {
    final identity = _identity ?? (throw StateError('Service not started'));
    final ttl = await _conversationTtl(group.id);

    final message = Message.text(
      senderId: identity.id,
      recipientId: group.id,
      content: text,
      replyToId: replyToId,
      disappearAfterSeconds: ttl,
      status: MessageStatus.sending,
      poll: poll,
      mentions: mentions,
    );
    await storage.addMessage(group.id, message);
    onUpdate?.call();

    try {
      final anyOk = await _fanoutToGroup(group, {
        'v': 1,
        't': 'txt',
        'id': message.id,
        'ts': message.timestamp.millisecondsSinceEpoch,
        'gid': group.id,
        'txt': text,
        're': ?replyToId,
        'ttl': ?ttl,
        'poll': ?poll?.toWire(),
        if (mentions.isNotEmpty) 'mn': mentions,
        'p': _profile(),
      });
      final sent = message.copyWith(
          status: anyOk ? MessageStatus.sent : MessageStatus.failed);
      await storage.updateMessage(group.id, sent);
      onUpdate?.call();
      return sent;
    } catch (e) {
      // Výjimka mimo per-member cestu (např. build obsahu) by jinak nechala
      // zprávu navždy ve stavu „odesílá se" (⏱). Označit jako selhalou.
      await storage.updateMessage(
          group.id, message.copyWith(status: MessageStatus.failed));
      onUpdate?.call();
      rethrow;
    }
  }

  /// Odešle přílohu do skupiny — blob se šifruje a nahrává JEDNOU,
  /// všem členům jede stejná meta (klíč+nonce+digest) E2E kanály.
  Future<Message> sendGroupAttachment(
    Group group, {
    required Uint8List bytes,
    required String fileName,
    String? mime,
    String? caption,
    int? durationMs,
  }) async {
    final identity = _identity ?? (throw StateError('Service not started'));
    final meta = await _prepareAttachment(
      bytes: bytes,
      fileName: fileName,
      mime: mime,
      durationMs: durationMs,
    );

    final ttl = await _conversationTtl(group.id);
    final message = Message.attachment(
      senderId: identity.id,
      recipientId: group.id,
      attachment: meta,
      caption: caption,
      disappearAfterSeconds: ttl,
      status: MessageStatus.sending,
    );
    await storage.addMessage(group.id, message);
    onUpdate?.call();

    try {
      final anyOk = await _fanoutToGroup(group, {
        'v': 1,
        't': 'att',
        'id': message.id,
        'ts': message.timestamp.millisecondsSinceEpoch,
        'gid': group.id,
        if (caption != null && caption.isNotEmpty) 'txt': caption,
        'ttl': ?ttl,
        'att': meta.toWire(),
        'p': _profile(),
      });
      final sent = message.copyWith(
          status: anyOk ? MessageStatus.sent : MessageStatus.failed);
      await storage.updateMessage(group.id, sent);
      onUpdate?.call();
      return sent;
    } catch (e) {
      await storage.updateMessage(
          group.id, message.copyWith(status: MessageStatus.failed));
      onUpdate?.call();
      rethrow;
    }
  }

  /// Můj hlas v anketě (prázdná volba = hlas zrušen). Lokálně hned,
  /// ostatním jako řídicí zpráva — ve skupině všem členům, ať počty sedí
  /// každému.
  Future<void> votePoll(String convId, String pollId, List<int> choice,
      {Group? group, Contact? contact}) async {
    await _mutateLocalMessage(convId, pollId, (m) {
      final poll = m.poll;
      return poll == null
          ? m
          : m.copyWith(poll: poll.withVote(_myFingerprint, choice));
    });
    final control = {'t': 'vote', 'ref': pollId, 'o': choice};
    if (group != null) {
      await _fanoutToGroup(group, {
        'v': 1,
        'id': const Uuid().v4(),
        'ts': DateTime.now().millisecondsSinceEpoch,
        'gid': group.id,
        ...control,
        'p': _profile(),
      });
    } else if (contact != null) {
      await _sendControl(contact, control);
    }
  }

  /// Reakce ve skupině (emoji == null = odebrat).
  Future<void> sendGroupReaction(
      Group group, String targetId, String? emoji) async {
    await _mutateLocalMessage(group.id, targetId, (m) {
      final r = Map<String, String>.from(m.reactions);
      if (emoji == null) {
        r.remove(_myFingerprint);
      } else {
        r[_myFingerprint] = emoji;
      }
      return m.copyWith(reactions: r);
    });
    await _fanoutToGroup(group, {
      'v': 1,
      't': 'rx',
      'id': const Uuid().v4(),
      'gid': group.id,
      'ref': targetId,
      'e': ?emoji,
      'p': _profile(),
    });
  }

  /// Editace mojí zprávy ve skupině.
  Future<void> editGroupMessage(
      Group group, String targetId, String newText) async {
    await _mutateLocalMessage(group.id, targetId,
        (m) => m.copyWith(content: newText, editedAt: DateTime.now()));
    await _fanoutToGroup(group, {
      'v': 1,
      't': 'edit',
      'id': const Uuid().v4(),
      'gid': group.id,
      'ref': targetId,
      'txt': newText,
      'p': _profile(),
    });
  }

  /// Smazání mojí zprávy pro všechny členy.
  Future<void> deleteGroupMessage(Group group, String targetId) async {
    await _mutateLocalMessage(group.id, targetId,
        (m) => m.copyWith(isDeleted: true, content: '', reactions: const {}));
    await _fanoutToGroup(group, {
      'v': 1,
      't': 'del',
      'id': const Uuid().v4(),
      'gid': group.id,
      'ref': targetId,
      'p': _profile(),
    });
  }

  /// Rozešle `ginv` s úplným rosterem všem členům kromě mě. S [op] nese
  /// pozvánka i podepsaný stav pro v2 členy (v1 klient pole `gop` ignoruje).
  Future<void> _fanoutInvite(Group group, {GroupOpMessage? op}) async {
    final roster = await _buildRoster(group);
    await _fanoutToGroup(group, {
      'v': 1,
      't': 'ginv',
      'id': const Uuid().v4(),
      'gid': group.id,
      'gname': group.name,
      'roster': roster,
      'gop': ?op?.toWire(),
      'p': _profile(),
    });
  }

  /// Podepíše operaci mým identity klíčem (XEdDSA, stejný klíč jako AUTH).
  GroupOpMessage _signOp(GroupAdminOp op,
      {List<Map<String, dynamic>>? roster}) {
    final key = PrivateKey.deserialize(
        bytes: _identity!.identityPrivateKey.toList());
    return GroupOpMessage(
      op: op,
      sig: op.signWith(
          (m) => Uint8List.fromList(key.sign(message: m).toList())),
      roster: roster,
    );
  }

  /// Aplikuje mou správcovskou operaci lokálně a rozešle ji starým i novým
  /// členům (odebraný se tak dozví, že už ve skupině není).
  ///
  /// Dokud je ve skupině člen bez v2, jede operace uvnitř legacy `ginv` /
  /// `gmeta` — v1 klient z nich převezme výsledný roster a jméno, v2 klient
  /// ověří vnořený `gop` a stín ignoruje. Jedna obálka místo dvou: nemůže
  /// se stát, že stín dorazí bez operace nebo v opačném pořadí.
  Future<void> _publishAdminOp(Group group, GroupAdminOp op) async {
    final before = {...group.memberIds};
    applyGroupOp(group, op, _myFingerprint);
    await storage.saveGroup(group);
    onUpdate?.call();

    final recipients = {...before, ...group.memberIds}..remove(_myFingerprint);
    final enforced = group.isEnforced(_myFingerprint);
    final isRename = op.action == GroupAdminAction.rename;
    // Roster potřebuje nový člen (add) a v1 stín `ginv`; `gmeta` ho nenese.
    final roster = (enforced ? op.action == GroupAdminAction.add : !isRename)
        ? await _buildRoster(group)
        : null;
    final Map<String, dynamic> content;
    if (enforced) {
      content = {
        'v': 1,
        't': 'gop',
        'id': const Uuid().v4(),
        ..._signOp(op, roster: roster).toWire(),
        'p': _profile(),
      };
    } else if (isRename) {
      content = {
        'v': 1,
        't': 'gmeta',
        'id': const Uuid().v4(),
        'gid': group.id,
        'gname': group.name,
        'gop': _signOp(op).toWire(),
        'p': _profile(),
      };
    } else {
      content = {
        'v': 1,
        't': 'ginv',
        'id': const Uuid().v4(),
        'gid': group.id,
        'gname': group.name,
        'roster': roster,
        'gop': _signOp(op).toWire(),
        'p': _profile(),
      };
    }
    await _fanoutToGroup(group, content, recipients: recipients);
  }

  /// Testovací vstup do skupinové příjmové cesty bez relaye a krypta:
  /// dosadí identitu příjemce a zavolá handlery, jejichž bezpečnostní
  /// pravidla (anti-spoof rosteru, membership guard) chceme ověřit
  /// izolovaně. `senderFp` v produkci VŽDY pochází ze sealed senderu.
  @visibleForTesting
  void debugSetIdentity(LocalIdentity identity) => _identity = identity;

  @visibleForTesting
  Future<void> debugHandleGroupInvite(
          String senderFp, Map<String, dynamic> content) =>
      _handleGroupInvite(senderFp, content);

  /// Libovolná správa skupiny (`ginv`/`gmeta`/`gleave`/`gop`/`gsync`).
  @visibleForTesting
  Future<void> debugHandleGroupControl(
          String senderFp, Map<String, dynamic> content) =>
      _handleGroupControl(senderFp, content['t'] as String?, content);

  @visibleForTesting
  Future<Group?> debugGroupForIncoming(String gid, String senderFp) =>
      _groupForIncoming(gid, senderFp);

  /// Když je nastavený, odchozí obsah místo relaye dostane test
  /// (fingerprint příjemce + content JSON) a odeslání se bere jako úspěšné.
  @visibleForTesting
  void Function(String toFingerprint, Map<String, dynamic> content)?
      debugSendTap;

  /// Roster = [{f, n, ik, aid, da, v}] pro všechny členy včetně mě.
  /// Člen bez routingu se vynechá (příjemci mu psát nemohou, ale
  /// zprávy od něj membership guardem projdou). `v: 2` = člen inzeroval
  /// podporu správců; v1 klient pole ignoruje.
  Future<List<Map<String, dynamic>>> _buildRoster(Group group) async {
    final contacts = await storage.loadContacts();
    final byFp = {for (final c in contacts) c.id: c};
    final roster = <Map<String, dynamic>>[];

    final me = shareableIdentity!;
    roster.add({
      'f': _myFingerprint,
      'n': me.displayName,
      'ik': base64Encode(me.identityKey),
      // Před doběhnutím registrace routing nemám — vynechat, ne `!`.
      'aid': ?me.accountId,
      'da': ?(me.deliveryAddress == null
          ? null
          : base64Encode(me.deliveryAddress!)),
      'v': groupProtocolVersion,
    });

    for (final fp in group.memberIds) {
      if (fp == _myFingerprint) continue;
      final c = byFp[fp];
      final p = c?.publicIdentity;
      if (p == null || p.accountId == null || p.deliveryAddress == null) {
        continue;
      }
      roster.add({
        'f': fp,
        'n': c!.displayName,
        'ik': base64Encode(p.identityKey),
        'aid': p.accountId,
        'da': base64Encode(p.deliveryAddress!),
        if (group.v2Members.contains(fp)) 'v': groupProtocolVersion,
      });
    }
    return roster;
  }

  /// Verze skupinového protokolu, kterou inzeruju (`gv` v obsahu, `v`
  /// v rosteru). 2 = rozumím správcům a `gop`.
  static const groupProtocolVersion = 2;

  /// Fanout obsahu členům kromě mě (nebo jen [recipients]). Vrací true,
  /// když aspoň jedno odeslání prošlo (per-member retry v1 není — stejná
  /// hranice jako u 1:1 control zpráv). Každý skupinový obsah nese `gv`,
  /// aby ostatní poznali, kdy už ve skupině žádný v1 klient není.
  Future<bool> _fanoutToGroup(Group group, Map<String, dynamic> content,
      {Iterable<String>? recipients}) async {
    final contacts = await storage.loadContacts();
    final byFp = {for (final c in contacts) c.id: c};
    final payload = {...content, 'gv': groupProtocolVersion};
    var anyOk = false;
    for (final fp in recipients ?? group.memberIds) {
      if (fp == _myFingerprint) continue;
      final c = byFp[fp];
      if (c == null || c.blocked) continue;
      try {
        await _sendContent(c, payload);
        anyOk = true;
      } catch (_) {
        // člen offline/bez routingu — v1 bez per-member retry fronty
      }
    }
    return anyOk;
  }

  /// Membership guard příchozího skupinového obsahu: skupina existuje,
  /// neopustil jsem ji a odesílatel je člen. Jinak null → drop.
  Future<Group?> _groupForIncoming(String gid, String senderFp) async {
    final group = await storage.loadGroup(gid);
    if (group == null || group.left) return null;
    if (!group.isMember(senderFp)) return null;
    return group;
  }

  /// Zapamatuje si, že člen inzeruje v2 (`gv` je v obsahu každé skupinové
  /// zprávy v2 klienta). Vrací true, když se stav skupiny změnil.
  bool _noteCapability(Group group, String fp, Map<String, dynamic> content) {
    final gv = content['gv'];
    if (gv is! int || gv < groupProtocolVersion) return false;
    if (!group.isMember(fp)) return false;
    return group.v2Members.add(fp);
  }

  // ── Správa skupin: příjem ───────────────────────────────────────────
  //
  // Pravda o členství/rolích/jménu je řetěz podepsaných operací `gop`.
  // Legacy `ginv`/`gmeta` od ne-správce se bere jen
  // v kompatibilním režimu (ve skupině je aspoň jeden v1 člen) — v1 klient
  // jinou cestu nemá a odmítnutí by skupinu rozdělilo.

  /// Jak často nejvýš žádat správce o stav jedné skupiny. Chrání před
  /// smyčkou i zahlcením, když správce nemá co poslat nebo je offline.
  static const _groupSyncRequestEvery = Duration(minutes: 10);

  /// Jak často nejvýš odpovídat stejnému členovi na žádost o stav.
  static const _groupSyncAnswerEvery = Duration(minutes: 1);

  final _groupSyncRequestedAt = <String, DateTime>{};
  final _groupSyncAnsweredAt = <String, DateTime>{};

  Future<void> _handleGroupControl(
      String senderFp, String? type, Map<String, dynamic> content) async {
    final gid = content['gid'];
    if (gid is! String || gid.isEmpty || gid.length > 64) return;
    if (type == 'gsync') return _answerGroupSync(senderFp, gid, content);

    final opRaw = type == 'gop' ? content : content['gop'];
    if (opRaw != null) {
      final msg = GroupOpMessage.fromWire(opRaw);
      final consumed = msg != null &&
          msg.op.gid == gid &&
          await _handleGroupOp(senderFp, msg, content['roster']);
      // Odmítnutý vnořený `gop` nechá promluvit legacy stín: odesílatel je
      // pak posuzován jako kterýkoli v1 člen (kompatibilní režim).
      if (consumed || type == 'gop') return;
    }

    switch (type) {
      case 'ginv':
        await _handleGroupInvite(senderFp, content);
      case 'gmeta':
        await _handleLegacyMeta(senderFp, gid, content);
      case 'gleave':
        await _handleLeave(senderFp, gid);
    }
  }

  /// Zpracuje podepsanou operaci. Vrací true, když je tím zpráva vyřízená
  /// (aplikovaná, zastaralá, podržená); false = operace neplatí a legacy
  /// stín se má posoudit podle pravidel kompatibilního režimu.
  Future<bool> _handleGroupOp(
      String senderFp, GroupOpMessage msg, Object? outerRoster) async {
    final local = await storage.loadGroup(msg.op.gid);
    if (local == null) return _joinFromOp(senderFp, msg, outerRoster);
    // Opuštěná skupina se znovu neotevírá (stejně jako v1 pozvánka).
    if (local.left) return true;

    final keys = await _identityKeysByFp();
    final verdict = checkGroupOp(
      local: local,
      msg: msg,
      senderFp: senderFp,
      me: _myFingerprint,
      actorIdentityKey: keys[msg.op.actor],
    );
    switch (verdict) {
      case GopVerdict.apply:
        await _applyVerifiedOp(local, msg, senderFp, outerRoster);
        return true;
      case GopVerdict.stale:
        return true;
      case GopVerdict.gap:
        await _holdAndResync(local, senderFp, msg, outerRoster);
        return true;
      case GopVerdict.fork:
        // Operace navazuje na stav, který nemám — nejde ji podržet (nikdy
        // nenaváže). Stav od správce s vyšší epochou ji stejně obsahuje.
        local.needsResync = true;
        await storage.saveGroup(local);
        onUpdate?.call();
        await _requestGroupSync(local, senderFp);
        return true;
      case GopVerdict.notAdmin when msg.op.epoch > local.epoch + 1:
        // Z budoucnosti: podepisující mohl správcem (nebo i členem) být
        // jmenován v epoše, která mi chybí. Neaplikovat, ale ani nezahodit.
        await _holdAndResync(local, senderFp, msg, outerRoster);
        return true;
      case GopVerdict.notAdmin:
      case GopVerdict.badSignature:
      case GopVerdict.spoof:
      case GopVerdict.invalid:
        local.rejectedOpAt = DateTime.now();
        await storage.saveGroup(local);
        onUpdate?.call();
        return false;
    }
  }

  Future<Map<String, Uint8List>> _identityKeysByFp() async => {
        for (final c in await storage.loadContacts())
          c.id: c.publicIdentity.identityKey,
      };

  Future<void> _applyVerifiedOp(Group group, GroupOpMessage msg,
      String senderFp, Object? outerRoster) async {
    applyGroupOp(group, msg.op, _myFingerprint);
    group.v2Members.add(senderFp);
    await _absorbOpRoster(group, msg, outerRoster);
    await _drainPendingOps(group);
    group.needsResync = group.pendingOps.isNotEmpty;
    await storage.saveGroup(group);
    onUpdate?.call();
  }

  /// Z rosteru ověřené operace založí kontakty nových členů (stejná TOFU
  /// pravidla jako `ginv`) a převezme jejich inzerovanou v2 — tu tu ručí
  /// podepsaný správce.
  Future<void> _absorbOpRoster(
      Group group, GroupOpMessage msg, Object? outerRoster) async {
    final roster = _validRosterEntries(msg.roster ?? outerRoster);
    roster.removeWhere((f, _) => !group.isMember(f));
    await _ingestRoster(roster.values);
    for (final e in roster.values) {
      if (e['v'] == groupProtocolVersion) group.v2Members.add(e['f'] as String);
    }
  }

  Future<void> _holdAndResync(Group group, String senderFp,
      GroupOpMessage msg, Object? outerRoster) async {
    final roster = msg.roster ??
        (outerRoster is List
            ? [
                for (final e in outerRoster)
                  if (e is Map) e.cast<String, dynamic>(),
              ]
            : null);
    holdGroupOp(
      group,
      PendingGroupOp(
        senderFp: senderFp,
        wire: GroupOpMessage(op: msg.op, sig: msg.sig, roster: roster)
            .toWire(),
      ),
    );
    group.needsResync = true;
    await storage.saveGroup(group);
    onUpdate?.call();
    await _requestGroupSync(group, senderFp);
  }

  /// Zkusí podržené operace znovu po posunu stavu. Každá se ověřuje celá
  /// znovu (správci se mezitím mohli změnit).
  Future<void> _drainPendingOps(Group group) async {
    var progressed = true;
    while (progressed && group.pendingOps.isNotEmpty) {
      progressed = false;
      final keys = await _identityKeysByFp();
      for (final p in [...group.pendingOps]) {
        final msg = GroupOpMessage.fromWire(p.wire);
        final verdict = msg == null
            ? GopVerdict.invalid
            : checkGroupOp(
                local: group,
                msg: msg,
                senderFp: p.senderFp,
                me: _myFingerprint,
                actorIdentityKey: keys[msg.op.actor],
              );
        final stillFuture = verdict == GopVerdict.gap ||
            (verdict == GopVerdict.notAdmin &&
                msg!.op.epoch > group.epoch + 1);
        if (stillFuture) continue;
        group.pendingOps = group.pendingOps.where((x) => x != p).toList();
        if (verdict == GopVerdict.apply) {
          applyGroupOp(group, msg!.op, _myFingerprint);
          group.v2Members.add(p.senderFp);
          await _absorbOpRoster(group, msg, null);
          progressed = true;
          break;
        }
      }
    }
  }

  /// Požádá správce (a odesílatele operace, která nenavázala) o aktuální
  /// podepsaný stav. Omezené frekvencí — odpověď žádost nikdy nevyvolá,
  /// takže smyčka nevznikne.
  Future<void> _requestGroupSync(Group group, String hintFp) async {
    final now = DateTime.now();
    final last = _groupSyncRequestedAt[group.id];
    if (last != null && now.difference(last) < _groupSyncRequestEvery) return;
    _groupSyncRequestedAt[group.id] = now;
    await _fanoutToGroup(
      group,
      {
        'v': 1,
        't': 'gsync',
        'id': const Uuid().v4(),
        'gid': group.id,
        'ep': group.epoch,
        'p': _profile(),
      },
      recipients: {...group.admins, if (group.isMember(hintFp)) hintFp},
    );
  }

  /// Odpověď správce na žádost o stav: můj aktuální stav podepsaný jako
  /// `sync`. Jen členovi, jen když jsem opravdu dál, a jen jednou za chvíli.
  Future<void> _answerGroupSync(
      String senderFp, String gid, Map<String, dynamic> content) async {
    final group = await _groupForIncoming(gid, senderFp);
    if (group == null || !group.isAdmin(_myFingerprint)) return;
    final theirs = content['ep'];
    if (theirs is! int || theirs >= group.epoch) return;

    final key = '$gid|$senderFp';
    final now = DateTime.now();
    final last = _groupSyncAnsweredAt[key];
    if (last != null && now.difference(last) < _groupSyncAnswerEvery) return;
    _groupSyncAnsweredAt[key] = now;

    final snapshot = _signOp(
      buildGroupOp(
        group: group,
        me: _myFingerprint,
        action: GroupAdminAction.sync,
      ),
      roster: await _buildRoster(group),
    );
    await _fanoutToGroup(
      group,
      {
        'v': 1,
        't': 'gop',
        'id': const Uuid().v4(),
        ...snapshot.toWire(),
        'p': _profile(),
      },
      recipients: [senderFp],
    );
  }

  /// Pozvánka do skupiny, kterou ještě neznám, s podepsaným stavem. Klíč
  /// podepisujícího: z mých kontaktů, jinak z rosteru (fingerprint ověřený
  /// proti klíči — stejná důvěra jako u v1 pozvánky).
  Future<bool> _joinFromOp(
      String senderFp, GroupOpMessage msg, Object? outerRoster) async {
    final op = msg.op;
    final roster = _validRosterEntries(msg.roster ?? outerRoster);
    final keys = await _identityKeysByFp();
    final rosterIk = roster[op.actor]?['ik'] as String?;
    final verdict = checkJoinOp(
      msg: msg,
      senderFp: senderFp,
      me: _myFingerprint,
      actorIdentityKey:
          keys[op.actor] ?? (rosterIk == null ? null : base64Decode(rosterIk)),
    );
    if (verdict != GopVerdict.apply) return false;

    roster.removeWhere((f, _) => !op.members.contains(f));
    await _ingestRoster(roster.values);
    final group = Group(
      id: op.gid,
      name: op.name,
      memberIds: op.members,
      createdBy: op.actor,
      admins: op.admins,
      epoch: op.epoch,
      v2Members: {
        senderFp,
        for (final e in roster.values)
          if (e['v'] == groupProtocolVersion) e['f'] as String,
      },
    );
    await storage.saveGroup(group);
    await storage.ensureConversation(group.id);
    onUpdate?.call();
    return true;
  }

  /// Roster entry, jejichž fingerprint sedí s identity klíčem (anti-spoof);
  /// ostatní se tiše vynechají. Nad strop členů = nic.
  Map<String, Map<String, dynamic>> _validRosterEntries(Object? rosterRaw) {
    final members = <String, Map<String, dynamic>>{};
    if (rosterRaw is! List || rosterRaw.length > Group.maxMembers) {
      return members;
    }
    for (final raw in rosterRaw) {
      if (raw is! Map) continue;
      final e = raw.cast<String, dynamic>();
      final f = e['f'];
      final ikB64 = e['ik'];
      if (f is! String || ikB64 is! String) continue;
      final Uint8List ik;
      try {
        ik = base64Decode(ikB64);
      } on FormatException {
        continue;
      }
      if (SepotFingerprint.ofPublicKey(ik).display != f) continue;
      members[f] = e;
    }
    return members;
  }

  /// Neznámé členy založ jako běžné (neověřené) kontakty; existujícím
  /// nanejvýš doplň chybějící routing (jen při shodě identity klíče).
  Future<void> _ingestRoster(Iterable<Map<String, dynamic>> entries) async {
    final contacts = await storage.loadContacts();
    final byFp = {for (final c in contacts) c.id: c};
    for (final e in entries) {
      final f = e['f'] as String;
      if (f == _myFingerprint) continue;
      final aid = e['aid'] as String?;
      final daB64 = e['da'] as String?;
      final known = byFp[f];
      if (known != null) {
        final p = known.publicIdentity;
        if (aid != null &&
            daB64 != null &&
            (p.accountId == null || p.deliveryAddress == null)) {
          await storage.saveContact(Contact(
            displayName: known.displayName,
            publicIdentity: p.withRouting(
              accountId: aid,
              deliveryAddress: base64Decode(daB64),
            ),
            addedAt: known.addedAt,
            verified: known.verified,
            notes: known.notes,
            blocked: known.blocked,
            avatar: known.avatar,
            accepted: known.accepted,
          ));
        }
        continue;
      }
      final name = (e['n'] as String?)?.trim();
      // Člena skupiny jsem si nepřidal já: jméno mu dal on sám (nebo ten,
      // kdo roster poslal). Jako u příchozí zprávy je to žádost.
      await storage.saveContact(Contact.fromPublicIdentity(
        PublicIdentity(
          // Prázdné jméno = UI si doplní lokalizovaný fallback
          displayName: (name == null || name.isEmpty) ? '' : clipName(name),
          identityKey: base64Decode(e['ik'] as String),
          createdAt: DateTime.now(),
          accountId: aid,
          deliveryAddress: daB64 == null ? null : base64Decode(daB64),
        ),
        accepted: false,
      ));
    }
  }

  /// Zpracuje legacy `ginv` (pozvánka / aktualizace rosteru bez podpisu).
  /// Bezpečnostní pravidla: fingerprint každého záznamu
  /// musí sedět s jeho identity klíčem, odesílatel i já musíme být
  /// v rosteru, identity klíč existujícího kontaktu se NIKDY nepřepisuje.
  ///
  /// U známé skupiny jen PŘIDÁVÁ: v1 klient jinou změnu než přidání
  /// neumí, takže chybějící člen v jeho rosteru znamená nanejvýš, že ho
  /// nezná — ne že ho má kdo odebrat. Odebírá jen podepsaný `gop` a `gleave`.
  Future<void> _handleGroupInvite(
      String senderFp, Map<String, dynamic> content) async {
    final gid = content['gid'] as String?;
    final gname = (content['gname'] as String?)?.trim();
    final rosterRaw = content['roster'] as List?;
    if (gid == null || gid.isEmpty || gid.length > 64) return;
    if (gname == null || gname.isEmpty || rosterRaw == null) return;
    if (rosterRaw.length > Group.maxMembers) return;

    final members = _validRosterEntries(rosterRaw);
    if (!members.containsKey(senderFp)) return;
    if (!members.containsKey(_myFingerprint)) return;
    final senderV2 = members[senderFp]!['v'] == groupProtocolVersion;

    final existing = await storage.loadGroup(gid);
    if (existing != null) {
      if (existing.left) return;
      // Aktualizaci rosteru smí poslat jen stávající člen.
      if (!existing.isMember(senderFp)) return;
      if (senderV2) existing.v2Members.add(senderFp);
      _noteCapability(existing, senderFp, content);
      final merged = {...existing.memberIds, ...members.keys};
      if (merged.length > Group.maxMembers) return;
      if (!existing.isAdmin(senderFp) &&
          existing.isEnforced(_myFingerprint)) {
        existing.rejectedOpAt = DateTime.now();
        await storage.saveGroup(existing);
        onUpdate?.call();
        return;
      }
      await _ingestRoster(members.values);
      existing
        ..memberIds = merged.toList()
        ..name = gname;
      await storage.saveGroup(existing);
      onUpdate?.call();
      return;
    }

    await _ingestRoster(members.values);
    // Bez podpisu nevím, kdo je skutečný správce — odhad je odesílatel,
    // první podepsaný stav ho opraví (Group.provisional).
    final group = Group(
      id: gid,
      name: gname,
      memberIds: members.keys.toList(),
      createdBy: senderFp,
      provisional: true,
      v2Members: {if (senderV2) senderFp},
    );
    await storage.saveGroup(group);
    await storage.ensureConversation(gid);
    onUpdate?.call();
  }

  /// Legacy přejmenování (`gmeta` bez podpisu): od správce vždy, od
  /// ostatních jen v kompatibilním režimu.
  Future<void> _handleLegacyMeta(
      String senderFp, String gid, Map<String, dynamic> content) async {
    final group = await _groupForIncoming(gid, senderFp);
    if (group == null) return;
    _noteCapability(group, senderFp, content);
    final gname = (content['gname'] as String?)?.trim();
    if (!group.isAdmin(senderFp) && group.isEnforced(_myFingerprint)) {
      group.rejectedOpAt = DateTime.now();
    } else if (gname != null && gname.isNotEmpty) {
      group.name = gname;
    }
    await storage.saveGroup(group);
    onUpdate?.call();
  }

  /// Odchod smí oznámit každý sám za sebe; odešel-li poslední správce,
  /// nastoupí náhradník podle Group.normalizeAdmins.
  Future<void> _handleLeave(String senderFp, String gid) async {
    final group = await _groupForIncoming(gid, senderFp);
    if (group == null) return;
    group.memberIds = group.memberIds.where((f) => f != senderFp).toList();
    group.normalizeAdmins();
    await storage.saveGroup(group);
    onUpdate?.call();
  }

  /// Společná odesílací cesta: session bootstrap (X3DH s anti-MITM
  /// kontrolou identity klíče), sealed encrypt, obálka na relay.
  /// Vrací true = doručeno online, false = uloženo do offline fronty.
  /// Kolik zaseklých zpráv poslat na jeden průchod. Po delším výpadku sítě
  /// jich může být hodně; dávka drží start spojení svižný a zbytek dojde
  /// při dalším ticku.
  static const _outboxBatch = 30;

  /// Jak staré zaseklé zprávy ještě dosílat. Co leží dýl, patří uživateli
  /// do rukou — poslat týden starou zprávu bez zeptání by překvapilo.
  static const _outboxMaxAge = Duration(hours: 24);

  /// Došle zprávy, které zůstaly viset po výpadku spojení.
  ///
  /// Bez tohohle skončila každá zpráva odeslaná do mrtvého socketu jako
  /// `failed` (nebo věčné `sending` u příloh) a znovu ji poslal jedině
  /// uživatel ručně. Volá se po každém úspěšném (re)connectu; id zprávy
  /// zůstává stejné, takže protistrana duplicitu zahodí
  /// ([Conversation.addMessage]).
  Future<void> _flushOutbox() async {
    if (_outboxRunning || !isStarted) return;
    _outboxRunning = true;
    try {
      final identity = _identity;
      if (identity == null) return;
      final cutoff = DateTime.now().subtract(_outboxMaxAge);

      final stuck = <(String convId, Message message)>[];
      for (final conv in await storage.loadConversations()) {
        for (final m in conv.messages) {
          if (m.senderId != identity.id) continue;
          if (m.status != MessageStatus.failed &&
              m.status != MessageStatus.sending) {
            continue;
          }
          if (m.timestamp.isBefore(cutoff) || m.isDeleted) continue;
          stuck.add((conv.contactId, m));
        }
      }
      if (stuck.isEmpty) return;

      stuck.sort((a, b) => a.$2.timestamp.compareTo(b.$2.timestamp));
      for (final (convId, message) in stuck.take(_outboxBatch)) {
        if (connectionState != RelayConnectionState.connected) break;
        await _resend(convId, message);
      }
      onUpdate?.call();
    } finally {
      _outboxRunning = false;
    }
  }

  /// Jeden pokus o dodatečné odeslání. Trvalé chyby (chybný klíč protistrany,
  /// kontakt bez doručovací adresy) nechají zprávu `failed` a dál se
  /// neopakují — opakovat má smysl jen to, co shodila síť.
  Future<void> _resend(String convId, Message message) async {
    try {
      final group = await storage.loadGroup(convId);
      final bool delivered;
      if (group != null) {
        delivered = await _fanoutToGroup(group, _outboxWire(message, gid: convId));
      } else {
        final contact = (await storage.loadContacts())
            .where((c) => c.id == convId)
            .firstOrNull;
        if (contact == null) return;
        delivered = await _sendContent(contact, _outboxWire(message));
      }
      await storage.updateMessage(
        convId,
        message.copyWith(
          isDelivered: delivered,
          status: delivered ? MessageStatus.delivered : MessageStatus.sent,
        ),
      );
    } on SepotUserError {
      // Srozumitelná chyba = stav, který se opakováním nespraví (chybí
      // doručovací adresa, nesedí identity klíč, podvržený relay).
      await storage.updateMessage(
        convId,
        message.copyWith(status: MessageStatus.failed),
      );
    } on Object {
      // Síť/timeout — nechat viset a zkusit po příštím reconnectu.
      await storage.updateMessage(
        convId,
        message.copyWith(status: MessageStatus.failed),
      );
    }
  }

  /// Obsah zprávy pro drát při dodatečném odeslání. Drží se tvaru, který
  /// posílá [sendText]/[sendAttachment] — včetně `id`, aby šlo o TUTÉŽ
  /// zprávu, ne novou.
  Map<String, dynamic> _outboxWire(Message message, {String? gid}) {
    final isAttachment = message.attachment != null;
    final caption = message.content;
    return {
      'v': 1,
      't': isAttachment ? 'att' : 'txt',
      'id': message.id,
      'ts': message.timestamp.millisecondsSinceEpoch,
      'gid': ?gid,
      if (isAttachment) 'att': message.attachment!.toWire(),
      if (!isAttachment || (caption != null && caption.isNotEmpty))
        'txt': caption ?? '',
      're': ?message.replyToId,
      'ttl': ?message.disappearAfterSeconds,
      // Anketa a zmínky patří k téže zprávě i při dodatečném odeslání —
      // bez nich by po reconnectu dorazil jen holý záložní text.
      'poll': ?message.poll?.toWire(),
      if (message.mentions.isNotEmpty) 'mn': message.mentions,
      'p': _profile(),
    };
  }

  Future<bool> _sendContent(
    Contact contact,
    Map<String, dynamic> content,
  ) async {
    final tap = debugSendTap;
    if (tap != null) {
      tap(contact.id, content);
      return true;
    }
    return await _sendSealed(contact, content) ==
        pb.Receipt_Status.STATUS_DELIVERED_ONLINE;
  }

  /// Zašifruje obsah pro kontakt a pošle obálku. U [ephemeral] se nová
  /// session nezakládá (X3DH kvůli „píše…“ nedává smysl) — bez session
  /// vrací null.
  Future<pb.Receipt_Status?> _sendSealed(
    Contact contact,
    Map<String, dynamic> content, {
    bool ephemeral = false,
    bool ring = false,
  }) async {
    final crypto = _crypto ?? (throw StateError('Service not started'));
    final relay = _relay!;

    // Vlastní registrace na relay ještě nedoběhla (čerstvá instalace,
    // pomalá síť, Tor bez Orbotu) → nemáme sender adresu ani sender cert.
    // Srozumitelná chyba místo null-check pádu; registrace běží na pozadí.
    if (accountId == null || myDeliveryAddress == null) {
      throw const NotYetRegisteredError();
    }

    final peer = contact.publicIdentity;
    final peerAid = peer.accountId;
    final peerDa = peer.deliveryAddress;
    if (peerAid == null || peerDa == null) {
      throw const ContactNoDeliveryAddressError();
    }
    final peerAddr = ProtocolAddress(name: peerAid, deviceId: 1);

    // Krypto část jde přes [_serial] (viz komentář u pole): relace se
    // načte, zašifruje a uloží bez souběhu. Odeslání po síti už zámek
    // nedrží — čekání na receipt by blokovalo všechny ostatní.
    final sealed = await _serial<Uint8List?>(() async {
      await _dropForeignSession(crypto, peerAddr, contact);
      // První zpráva: X3DH z bundle. Identity klíč v bundle MUSÍ sedět
      // s klíčem z kontaktu (jinak by relay mohl podstrčit vlastní).
      if (!await crypto.hasSession(peerAddr)) {
        if (ephemeral) return null;
        final bundle = await relay.fetchBundle(peerDa);
        if (!_listEquals(bundle.identityKey, peer.identityKey)) {
          await _noteIdentityChanged(contact);
          throw const IdentityKeyMismatchError();
        }
        await crypto.processRemoteBundle(peerAddr, bundle);
      }
      return crypto.sealedEncrypt(
        recipient: peerAddr,
        plaintext: utf8.encode(jsonEncode(content)),
        senderCertificate: await _senderCertificate(),
      );
    });
    if (sealed == null) return null;

    final receipt = await relay.sendEnvelope(
      dstAddress: peerDa,
      payload: sealed,
      hint: ephemeral
          ? pb.ContentHint.CONTENT_HINT_EPHEMERAL
          : ring
              ? pb.ContentHint.CONTENT_HINT_CALL
              : pb.ContentHint.CONTENT_HINT_DEFAULT,
    );
    return receipt.status;
  }

  /// libsignal 5.0.9 nad prázdným paměťovým storem identit důvěřuje
  /// čemukoli (TOFU bez paměti): příchozí PreKey zpráva s cizím klíčem pod
  /// stejnou adresou relaci tiše přepíše a další odpověď by šla jemu.
  /// Klíč relace proto porovnáváme s klíčem kontaktu sami; nesedí-li,
  /// relace se zahodí (nová vznikne z bundle, který se ověřuje výše)
  /// a kontakt dostane varování.
  Future<void> _dropForeignSession(
      SepotCrypto crypto, ProtocolAddress peerAddr, Contact contact) async {
    if (!await crypto.hasSession(peerAddr)) return;
    final bound = await crypto.sessionIdentity(peerAddr);
    if (bound == null ||
        _listEquals(bound, contact.publicIdentity.identityKey)) {
      return;
    }
    await crypto.dropSession(peerAddr);
    await _noteIdentityChanged(contact);
  }

  @visibleForTesting
  Future<void> debugDropForeignSession(
          SepotCrypto crypto, ProtocolAddress peerAddr, Contact contact) =>
      _dropForeignSession(crypto, peerAddr, contact);

  // ── Příjem ──────────────────────────────────────────────────────────

  /// Dodávky se zpracovávají postupně (viz [_serial]) a evidují jako
  /// rozpracované, aby na ně [stop] počkal.
  void _onDeliver(pb.Envelope envelope) {
    _inFlight++;
    unawaited(_serial(() => _handleDelivery(envelope))
        .then((_) {}, onError: (_) {})
        .whenComplete(() {
      _inFlight--;
      if (_inFlight == 0) _drained?.complete();
    }));
  }

  Future<void> _handleDelivery(pb.Envelope envelope) async {
    final crypto = _crypto;
    final trustRoot = _trustRoot;
    // Zamčené úložiště (auto-lock stihl zamknout dřív, než jsme se dostali
    // na řadu): nedešifrovat — ratchet by postoupil a zápis by selhal.
    // Relay obálku doručí znovu po odemčení.
    if (crypto == null || trustRoot == null || !storage.isUnlocked) return;

    final SepotSealedMessage opened;
    try {
      opened = await crypto.sealedDecrypt(
        ciphertext: Uint8List.fromList(envelope.payload),
        trustRoot: trustRoot,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Nedešifrovatelná/cizí obálka: NEACKovat, ať ji fronta podrží
      // (může jít o dočasný stav — např. cert refresh).
      return;
    }
    await _processOpened(opened, envelope.msgUuid);
  }

  @visibleForTesting
  Future<void> debugProcessOpened(
          SepotSealedMessage opened, List<int> msgUuid) =>
      _processOpened(opened, msgUuid);

  /// Zpracuje už dešifrovanou obálku: kontakt, typ obsahu, uložení, ACK.
  Future<void> _processOpened(
      SepotSealedMessage opened, List<int> msgUuid) async {
    // Od tohohle bodu ratchet postoupil — obálku na relayi už NIKDY znovu
    // nedešifrujeme (duplicitní decrypt libsignal odmítne). Vadný OBSAH se
    // proto ACKuje a zahazuje: redelivery nemůže nic spravit, jen by
    // trvale otravovala frontu při každém reconnectu.
    try {
      final content =
          jsonDecode(utf8.decode(opened.plaintext)) as Map<String, dynamic>;
      final type = content['t'] as String?;
      const known = knownContentTypes;
      if (content['v'] != 1 || !known.contains(type)) {
        // Neznámý typ/verze: obsah je pro tuhle verzi navždy nečitelný
        // a po upgradu ho stejně nejde znovu dešifrovat — ACK a zahodit.
        _relay?.ack(msgUuid);
        return;
      }

      final contact = await _findOrCreateContact(opened, content);
      final senderFp = contact.id;

      // Blokovaný kontakt: zahoď cokoliv od něj (ACK, ať se nefrontuje),
      // nic neukládej ani nezobrazuj a neposílej doručenku.
      if (contact.blocked) {
        _relay?.ack(msgUuid);
        return;
      }

      // Hovory jen 1:1; skupinový gid tu nemá co dělat.
      // Nic se neukládá — záznam „Hovor · 3:12“ si zapíše obsluha hovoru.
      // Žádost o zprávu nezvoní: cizí klíč by jinak rozezvonil telefon
      // s vlastním zvoleným jménem („Máma volá“).
      if (type == 'call') {
        if (content['gid'] == null && contact.accepted) {
          onCallSignal?.call(contact, content);
        }
        _relay?.ack(msgUuid);
        return;
      }

      // Správa skupin: pozvánka/roster, odchod, přejmenování, podepsané
      // operace správců a žádost o jejich stav. Autorita = sealed-sender
      // fingerprint; guardy uvnitř handlerů. ACK vždy (retry z fronty
      // nepomůže).
      if (_groupControlTypes.contains(type)) {
        await _handleGroupControl(senderFp, type, content);
        _relay?.ack(msgUuid);
        return;
      }

      // Skupinový obsah: membership guard (skupinu znám, neopustil jsem
      // ji, odesílatel je člen) — jinak tichý drop s ACK.
      final gid = content['gid'] as String?;
      final group =
          gid == null ? null : await _groupForIncoming(gid, senderFp);
      if (gid != null && group == null) {
        _relay?.ack(msgUuid);
        return;
      }
      if (group != null && _noteCapability(group, senderFp, content)) {
        await storage.saveGroup(group);
      }
      // Konverzace, do které obsah patří: skupina (gid), jinak 1:1.
      final convId = gid ?? contact.id;

      // „píše…“: jen když ho sám sdílím a jen čerstvé — zdržené v síti
      // by ukazovalo psaní, které už dávno skončilo.
      if (type == 'typ') {
        final fresh = DateTime.now().difference(wireSentAt(content['ts'])) <
            TypingTracker.showFor;
        if (fresh && await _typingEnabled()) typing.mark(convId, senderFp);
        _relay?.ack(msgUuid);
        return;
      }

      // Doručenka (✓✓) a potvrzení přečtení: zapíšou čas od daného
      // příjemce. Off-line zprávy se ✓✓ dočkají, až si je protistrana
      // vyzvedne. Potvrzení přečtení respektujeme jen když ho sám sdílím
      // (reciproční, default vypnuto).
      if (type == 'dlv' || type == 'rr') {
        final read = type == 'rr';
        final enabled = !read ||
            ((await storage.getSetting<bool>('read_receipts_enabled')) ??
                false);
        if (enabled) {
          // whereType přeskočí netypové prvky — podvržené 'ids' nesmí
          // shodit příjem (jinak by se obálka bez ACK doručovala donekonečna).
          final ids = read
              ? (content['ids'] as List?)?.whereType<String>() ??
                  const <String>[]
              : [?content['ref'] as String?];
          final at = wireSentAt(content['ts']);
          final recipients = group == null
              ? 1
              : group.memberIds.where((f) => f != _identity!.id).length;
          for (final id in ids) {
            await _mutateLocalMessage(
              convId,
              id,
              (m) => m.isMine(_identity!.id)
                  ? applyReceipt(m,
                      from: senderFp, at: at, read: read, recipients: recipients)
                  : m,
            );
          }
        }
        _relay?.ack(msgUuid);
        onUpdate?.call();
        return;
      }

      // Control zprávy (reakce/edit/del) mění existující zprávu, nevytvářejí
      // novou bublinu. Aplikujeme a ACKneme (retry z fronty nepomůže).
      if (type == 'rx' || type == 'edit' || type == 'del' || type == 'vote') {
        await _applyIncomingControl(convId, type!, content, opened);
        _relay?.ack(msgUuid);
        onUpdate?.call();
        return;
      }

      final messageId = (content['id'] as String?) ?? const Uuid().v4();
      // TTL mizící zprávy si diktuje odesílatel (jede E2E kanálem);
      // strop 30 dní proti nesmyslným hodnotám z drátu
      var ttl = content['ttl'] as int?;
      if (ttl != null && (ttl < 5 || ttl > 30 * 86400)) ttl = null;

      final replyTo = content['re'] as String?;
      final Message message;
      if (type == 'txt') {
        final raw = content['txt'];
        if (raw is! String) {
          // Trvale vadná obálka (chybí/netypové 'txt') — retry z fronty
          // nepomůže, ACKnout a zahodit stejně jako u vadných příloh.
          _relay?.ack(msgUuid);
          return;
        }
        // Strop délky z drátu: obálka unese 256 KiB a konverzace je jeden
        // JSON blob — čtvrtmegabajtová bublina by ji trvale zpomalila.
        const maxWireText = AppConstants.maxMessageLength * 4;
        final text =
            raw.length > maxWireText ? raw.substring(0, maxWireText) : raw;
        message = Message(
          id: messageId,
          senderId: contact.publicIdentity.fingerprint.display,
          recipientId: _identity!.id,
          type: MessageType.text,
          content: text,
          replyToId: replyTo,
          timestamp: wireSentAt(content['ts']),
          isDelivered: true,
          disappearAfterSeconds: ttl,
          // Vadná anketa = null → ukáže se záložní text, nic se nerozbije.
          poll: Poll.fromWire(content['poll']),
          // Zmínky dávají smysl jen ve skupině; v 1:1 by šly zneužít
          // k obejití ztlumení.
          mentions: gid == null ? const [] : mentionsFromWire(content['mn']),
        );
      } else {
        final AttachmentMeta meta;
        try {
          meta = AttachmentMeta.fromWire(
              content['att'] as Map<String, dynamic>);
          if (!AttachmentStore.isValidBlobId(meta.blobId)) {
            throw const FormatException('invalid blob_id');
          }
        } on Object {
          // Trvale vadná metadata — retry z fronty nepomůže, ACKnout
          _relay?.ack(msgUuid);
          return;
        }
        message = Message(
          id: messageId,
          senderId: contact.publicIdentity.fingerprint.display,
          recipientId: _identity!.id,
          type: meta.isImage ? MessageType.image : MessageType.file,
          content: content['txt'] as String?,
          fileName: meta.name,
          fileSize: meta.size,
          replyToId: replyTo,
          timestamp: wireSentAt(content['ts']),
          isDelivered: true,
          attachment: meta,
          disappearAfterSeconds: ttl,
        );
      }
      final isNew = await storage.addMessage(convId, message);
      // Zpráva dorazila → „píše…“ od autora skončilo.
      typing.clear(convId, senderFp);

      // Uloženo na disku → teprve teď smí relay obálku zahodit.
      // (Blob přílohy do fronty nepatří — stahuje se na pozadí a při
      // neúspěchu má UI retry, ACK na něj nečeká.)
      _relay?.ack(msgUuid);

      // Zprávu už známe (odesílatel ji poslal znovu po výpadku spojení).
      // Druhá bublina ani další stahování téhož blobu nemá vzniknout, ale
      // doručenku pošli — protistrana ji nejspíš právě proto nedostala.
      if (!isNew) {
        unawaited(_sendControl(contact, {
          't': 'dlv',
          'ref': message.id,
          'gid': ?gid,
        }));
        return;
      }

      onUpdate?.call();
      onMessageReceived?.call(contact, message, convId);

      // Pošli odesílateli doručenku (✓✓) — best-effort, nesmí blokovat
      // příjem ani ACK. Jen pro skutečné zprávy (txt/att), ne pro control.
      // Ve skupině nese gid, aby ji odesílatel spároval se skupinovou
      // konverzací.
      unawaited(_sendControl(contact, {
        't': 'dlv',
        'ref': message.id,
        'gid': ?gid,
      }));

      if (message.attachment != null) {
        unawaited(downloadAttachment(convId, message));
      }
    } on FormatException {
      // Malformovaný obsah (ne-UTF-8/ne-JSON plaintext, vadná base64
      // v profilu či rosteru) — trvale vadné, ACK a zahodit.
      _relay?.ack(msgUuid);
    } on TypeError {
      // Pole se špatným typem (txt/ttl/id/re/p jako číslo apod.) —
      // trvale vadné, ACK a zahodit.
      _relay?.ack(msgUuid);
    } catch (_) {
      // Přechodné selhání zpracování (storage apod.): NEACKovat — další
      // pokus po reconnectu za nic nedá, i když duplicitní decrypt
      // pravděpodobně selže. Trvalé chyby obsahu řeší větve výše.
    }
  }

  /// Zapíše doručenku/potvrzení přečtení od příjemce `from` do mé zprávy.
  ///
  /// Stav nikdy nesestupuje: doručenka poslaná znovu po výpadku spojení
  /// často dorazí až PO potvrzení přečtení a nesmí vrátit „přečteno" na
  /// „doručeno". Ve skupině platí ✓✓ / přečteno až za všechny ostatní
  /// členy (`recipients`); dílčí stav ukáže Info o zprávě. Opakované
  /// potvrzení čas nepřepíše — platí první.
  @visibleForTesting
  static Message applyReceipt(
    Message m, {
    required String from,
    required DateTime at,
    required bool read,
    int recipients = 1,
  }) {
    // Hodiny příjemce se můžou opožďovat — přečtení před odesláním
    // by v Info o zprávě vypadalo jako chyba.
    final when = at.isBefore(m.timestamp) ? m.timestamp : at;
    final deliveredTo = {...m.deliveredTo}..putIfAbsent(from, () => when);
    final readBy =
        read ? ({...m.readBy}..putIfAbsent(from, () => when)) : m.readBy;

    int rank(MessageStatus s) => switch (s) {
          MessageStatus.sending || MessageStatus.failed => 0,
          MessageStatus.sent => 1,
          MessageStatus.delivered => 2,
          MessageStatus.read => 3,
        };
    // Doručenka sama dokazuje, že zpráva odešla — i když ji odesílatel
    // stihl označit za neodeslanou (timeout před ACK relaye).
    final target = readBy.length >= recipients
        ? MessageStatus.read
        : deliveredTo.length >= recipients
            ? MessageStatus.delivered
            : MessageStatus.sent;
    final status = rank(target) > rank(m.status) ? target : m.status;

    return m.copyWith(
      status: status,
      isDelivered: true,
      deliveredTo: deliveredTo,
      readBy: readBy,
    );
  }

  /// Čas odeslání z drátu (ms). Bez něj by zpráva dostala čas doručení —
  /// po vyzvednutí offline fronty by celá konverzace uskočila na „teď"
  /// a každý člen skupiny by u téže zprávy viděl jiný čas.
  ///
  /// Klienti ≤1.1.1 `ts` neposílají → fallback na čas doručení (chová se
  /// jako dřív). Odesílatel si čas diktuje sám (jde E2E kanálem), proto
  /// strop: hodiny zařízení se běžně rozcházejí o minuty, ale zpráva
  /// nesmí uskočit mimo konverzaci.
  @visibleForTesting
  static DateTime wireSentAt(Object? raw) {
    final now = DateTime.now();
    if (raw is! int) return now;
    final sent = DateTime.fromMillisecondsSinceEpoch(raw);
    if (sent.isAfter(now.add(const Duration(minutes: 5)))) return now;
    if (sent.isBefore(DateTime(2020))) return now;
    return sent;
  }

  /// Aplikuje příchozí reakci/edit/delete na cílovou zprávu v dané
  /// konverzaci (1:1 = kontakt, skupina = gid). Klíč reakce = fingerprint
  /// odesílatele (kryptograficky ověřený sealed senderem, ne
  /// self-declared).
  Future<void> _applyIncomingControl(
    String convId,
    String type,
    Map<String, dynamic> content,
    SepotSealedMessage opened,
  ) async {
    final ref = content['ref'] as String?;
    if (ref == null) return;
    final senderFp =
        SepotFingerprint.ofPublicKey(opened.senderIdentityKey).display;

    await _mutateLocalMessage(convId, ref, (m) {
      switch (type) {
        case 'rx':
          final emoji = content['e'] as String?;
          final r = Map<String, String>.from(m.reactions);
          if (emoji == null || emoji.isEmpty) {
            r.remove(senderFp);
          } else {
            r[senderFp] = emoji;
          }
          return m.copyWith(reactions: r);
        case 'edit':
          // Upravit smí jen autor zprávy (odesílatel controlu = autor)
          if (m.senderId != senderFp) return m;
          return m.copyWith(
              content: content['txt'] as String? ?? m.content,
              editedAt: DateTime.now());
        case 'del':
          if (m.senderId != senderFp) return m;
          return m.copyWith(
              isDeleted: true, content: '', reactions: const {});
        case 'vote':
          final poll = m.poll;
          final choice = content['o'];
          if (poll == null || m.isDeleted || choice is! List) return m;
          return m.copyWith(
              poll: poll.withVote(senderFp, choice.whereType<int>().toList()));
        default:
          return m;
      }
    });
  }

  // ── Přílohy: download + čtení ───────────────────────────────────────

  /// Stáhne blob přílohy, ověří digest a uloží do lokálního store.
  /// Idempotentní; při selhání nastaví stav failed (UI nabídne retry).
  Future<void> downloadAttachment(String contactId, Message message) async {
    final meta = message.attachment;
    final relay = _relay;
    if (meta == null || relay == null) return;
    if (meta.state == AttachmentTransferState.downloading) return;
    if (await _attachments.exists(meta.blobId)) {
      await _setAttachmentState(
          contactId, message.id, AttachmentTransferState.ready);
      return;
    }

    await _setAttachmentState(
        contactId, message.id, AttachmentTransferState.downloading);
    try {
      final blob = await relay.downloadAttachment(meta.blobId);
      final digest = await AttachmentCipher.sha256(blob);
      if (!_listEquals(digest, meta.digest)) {
        throw const AttachmentIntegrityException('digest mismatch');
      }
      await _attachments.save(meta.blobId, blob);
      await _setAttachmentState(
          contactId, message.id, AttachmentTransferState.ready);
    } catch (_) {
      await _setAttachmentState(
          contactId, message.id, AttachmentTransferState.failed);
    }
  }

  /// Dešifruje přílohu do paměti (na disk plaintext nejde). Null = blob
  /// ještě není stažený.
  Future<Uint8List?> loadDecryptedAttachment(Message message) async {
    final meta = message.attachment;
    if (meta == null) return null;
    final blob = await _attachments.load(meta.blobId);
    if (blob == null) return null;
    return AttachmentCipher.decrypt(
      blob: blob,
      key: meta.key,
      nonce: meta.nonce,
      expectedDigest: meta.digest,
    );
  }

  /// Stav se přepisuje nad ČERSTVOU kopií zprávy z DB (mezitím mohla
  /// dostat doručenku apod.), ne nad snapshotem volajícího.
  Future<void> _setAttachmentState(
    String contactId,
    String messageId,
    AttachmentTransferState state,
  ) async {
    final conv = await storage.loadConversation(contactId);
    if (conv == null) return;
    final index = conv.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final current = conv.messages[index];
    final meta = current.attachment;
    if (meta == null || meta.state == state) return;
    await storage.updateMessage(
      contactId,
      current.copyWith(attachment: meta.copyWith(state: state)),
    );
    onUpdate?.call();
  }

  /// Odesílatel se hledá podle FINGERPRINTU jeho identity klíče
  /// (kryptograficky ověřen sealed senderem) — nikdy podle jména.
  Future<Contact> _findOrCreateContact(
    SepotSealedMessage opened,
    Map<String, dynamic> content,
  ) async {
    final senderFp =
        SepotFingerprint.ofPublicKey(opened.senderIdentityKey).display;
    final contacts = await storage.loadContacts();

    final profile = content['p'] as Map<String, dynamic>?;
    final profileDa = profile?['da'] as String?;
    // Fotka: jen zprávy s profilem ji mění; profil bez 'av' = odebraná.
    final avatar = AvatarRef.fromWire(profile?['av']);

    for (final c in contacts) {
      if (c.publicIdentity.fingerprint.display != senderFp) continue;
      // Doplnit/aktualizovat routing (accountId poprvé, rotace adresy…)
      final known = c.publicIdentity;
      final routingChanged = known.accountId != opened.senderName ||
          (profileDa != null &&
              (known.deliveryAddress == null ||
                  base64Encode(known.deliveryAddress!) != profileDa));
      final avatarChanged =
          profile != null && avatar?.blobId != c.avatar?.blobId;
      if (!routingChanged && !avatarChanged) return c;

      final updated = Contact(
        displayName: c.displayName,
        publicIdentity: routingChanged
            ? known.withRouting(
                accountId: opened.senderName,
                deliveryAddress: profileDa != null
                    ? base64Decode(profileDa)
                    : known.deliveryAddress ?? Uint8List(0),
              )
            : known,
        addedAt: c.addedAt,
        verified: c.verified,
        notes: c.notes,
        // Bez tohohle se zablokovaný kontakt při změně adresy odblokoval.
        blocked: c.blocked,
        avatar: avatarChanged ? avatar : c.avatar,
        accepted: c.accepted,
      );
      await storage.saveContact(updated);
      if (avatarChanged) {
        final old = c.avatar;
        if (old != null) await _forgetAvatar(old);
        if (avatar != null) unawaited(_downloadAvatar(avatar));
      }
      return updated;
    }

    // Neznámý klíč = nový kontakt, NIKDY splynutí s existujícím. Identita
    // je klíč: jméno ani fotka, které si odesílatel zvolil, neříkají nic
    // o tom, kdo to je. Proto žádost o zprávu, ne kontakt.
    // Prázdné jméno = UI si doplní lokalizovaný fallback
    final name = (profile?['n'] as String?)?.trim();
    final identity = PublicIdentity(
      displayName: (name == null || name.isEmpty) ? '' : clipName(name),
      identityKey: opened.senderIdentityKey,
      createdAt: DateTime.now(),
      accountId: opened.senderName,
      deliveryAddress: profileDa == null ? null : base64Decode(profileDa),
    );
    final contact = Contact.fromPublicIdentity(identity, accepted: false)
      ..avatar = avatar;
    await storage.saveContact(contact);
    if (avatar != null) unawaited(_downloadAvatar(avatar));

    // Účet na relayi patří jednomu klíči navždy (identities.identity_key je
    // unikátní). Stejný účet s jiným klíčem = relay lže nebo byl převzat:
    // dosavadní kontakt ztrácí ověření a dostane varování.
    final previous = contacts
        .where((c) => c.publicIdentity.accountId == opened.senderName)
        .firstOrNull;
    if (previous != null) await _noteIdentityChanged(previous);

    final lookalike =
        lookalikeContact(identity.displayName, contacts, exceptId: contact.id);
    if (lookalike != null && lookalike.id != previous?.id) {
      await _noteLookalike(lookalike, identity.displayName);
    }
    return contact;
  }

  /// Bezpečnostní kód kontaktu se změnil: zrušit ověření a dát to najevo
  /// v jeho konverzaci. Opakovaný výskyt za sebou nepřidává další řádky.
  Future<void> _noteIdentityChanged(Contact contact) async {
    if (contact.verified) {
      contact.verified = false;
      await storage.saveContact(contact);
    }
    await _addNotice(contact, MessageNotice.identityChanged);
  }

  /// Někdo cizí se jmenuje skoro stejně jako [contact]. Připomínka do jeho
  /// konverzace (jen když existuje — nezakládat chat kvůli útočníkovi).
  Future<void> _noteLookalike(Contact contact, String claimedName) async {
    if (await storage.loadConversation(contact.id) == null) return;
    await _addNotice(contact, MessageNotice.lookalikeRequest,
        content: claimedName);
  }

  Future<void> _addNotice(Contact contact, MessageNotice notice,
      {String? content}) async {
    final me = _identity;
    if (me == null) return;
    final last = (await storage.loadConversation(contact.id))?.lastMessage;
    if (last?.notice == notice && last?.content == content) return;
    await storage.addMessage(
      contact.id,
      Message.notice(
          contactId: contact.id,
          myId: me.id,
          notice: notice,
          content: content),
    );
    onUpdate?.call();
  }

  // ── Sdílení vlastního kontaktu ──────────────────────────────────────

  /// Veřejná identita včetně routingu — tohle patří do QR/odkazu.
  PublicIdentity? get shareableIdentity {
    final identity = _identity;
    final aid = accountId;
    final da = myDeliveryAddress;
    if (identity == null) return null;
    if (aid == null || da == null) return identity.publicIdentity;
    return identity.publicIdentity
        .withRouting(accountId: aid, deliveryAddress: da);
  }

  /// Zaregistruje push endpoint u relaye (volá push vrstva po registraci
  /// u UnifiedPush distributora). Bezpečné i před připojením — odešle se
  /// po AUTH. platform=NONE push vypne.
  void registerPush(pb.RegisterPush registration) {
    _lastPush = registration;
    _relay?.registerPush(registration);
  }

  /// Probuzení z push budíčku: ujisti se, že jsme připojení — fronta se
  /// vyleje po AUTH (relay pošle DELIVER stream). Idempotentní.
  void onPushWake() {
    _relay?.kick();
  }

  /// Deregistrace účtu na relayi (GDPR čl. 17 / store „smazání účtu").
  /// Best-effort: offline nebo bez běžícího spojení se smazání na serveru
  /// nepovede — lokální wipe má proběhnout i tak, proto vrací jen úspěch
  /// místo výjimky. Volat PŘED `SecureStorageService.deleteAll()` (podpis
  /// požadavku potřebuje identity klíč).
  Future<bool> deleteRelayAccount() async {
    final relay = _relay;
    if (relay == null) return false;
    try {
      await relay.deleteIdentity();
      return true;
    } catch (_) {
      // Offline / server nedostupný — lokální wipe proběhne i tak,
      // UI o neúspěchu na serveru informuje.
      return false;
    }
  }

  Future<void> stop() async {
    _registerRetryTimer?.cancel();
    typing.dispose();
    _avatarCache.clear();
    _purgeTimer?.cancel();
    _purgeTimer = null;
    await _deliverSub?.cancel();
    await _prekeysLowSub?.cancel();
    await _stateSub?.cancel();
    // Rozpracované dodávky doběhnou (dešifrováno → zapsáno → ACK), teprve
    // pak se úložiště smí zamknout. Strop, ať zaseklá dodávka nezablokuje
    // zámek navždy.
    if (_inFlight > 0) {
      final drained = _drained ??= Completer<void>();
      await drained.future
          .timeout(const Duration(seconds: 8), onTimeout: () {});
    }
    _drained = null;
    await _relay?.dispose();
    // DB vlastní SecureStorageService (lock/deleteAll) — tady jen pustit
    _db = null;
    _crypto = null;
    _relay = null;
    _identity = null;
    _senderCert = null;
    _trustRoot = null;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
