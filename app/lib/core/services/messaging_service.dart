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
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:libsignal/libsignal.dart' show IdentityKeyPair, ProtocolAddress;
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/crypto/attachment_cipher.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/network/relay_client.dart';
import 'package:sepot/core/network/relay_transport.dart';
import 'package:sepot/core/services/image_processor.dart';
import 'package:sepot/core/storage/attachment_store.dart';
import 'package:sepot/core/storage/crypto_db.dart';
import 'package:sepot/core/storage/persistent_stores.dart';
import 'package:sepot/core/storage/secure_storage.dart';
import 'package:sepot/models/attachment.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/models/message.dart';
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
  void Function(Contact contact, Message message)? onMessageReceived;

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
  Timer? _registerRetryTimer;
  Timer? _purgeTimer;

  /// Transport relaye: false = přímé WSS, true = přes Tor (SOCKS5/Orbot na
  /// `.onion`). Čte se z nastavení při startu, přepíná se za běhu
  /// ([setTorEnabled]) přestavením [RelayClient].
  bool _useTor = false;
  int _socksPort = 9050;

  /// Poslední push registrace — přežije přestavení relaye (nový RelayClient
  /// začíná bez ní), aby po přepnutí Tor/přímo push dál fungoval.
  pb.RegisterPush? _lastPush;

  bool get isStarted => _crypto != null;
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
    await _relay?.dispose();
    _senderCert = null;
    _certFetchedAt = null;

    final relay = _buildRelay();
    _relay = relay;
    _deliverSub = relay.deliveries.listen(_onDeliver);

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
    } catch (_) {
      _registerRetryTimer?.cancel();
      _registerRetryTimer =
          Timer(const Duration(seconds: 30), _registerWithRetry);
      return;
    }
    _relay!.start();
    await _refreshSenderCert();
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

    db.transaction(() {
      db.kvPut('account_id', utf8.encode(reg.accountId));
      db.kvPut('device_uuid', utf8.encode(reg.deviceUuid));
      db.kvPut('delivery_address', deliveryAddress);
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

  Future<Message> sendText(Contact contact, String text,
      {String? replyToId}) async {
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
    );
    await storage.addMessage(contact.id, message);
    onUpdate?.call();

    try {
      final delivered = await _sendContent(contact, {
        'v': 1,
        't': 'txt',
        'id': message.id,
        'txt': text,
        're': ?replyToId,
        'ttl': ?ttl,
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

    final delivered = await _sendContent(contact, {
      'v': 1,
      't': 'att',
      'id': message.id,
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
  }) async {
    final relay = _relay!;
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
    final blobId = await relay.uploadAttachment(encrypted.blob);
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

  /// TTL mizících zpráv nastavené na konverzaci (null = vypnuto).
  Future<int?> _conversationTtl(String contactId) async {
    final conv = await storage.loadConversation(contactId);
    return conv?.disappearAfterSeconds;
  }

  Map<String, dynamic> _profile() {
    final identity = _identity!;
    return {
      'n': identity.displayName,
      'aid': accountId,
      'da': base64Encode(myDeliveryAddress!),
    };
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
  /// read receipts ZAPNUTÉ (default vypnuto). Best-effort.
  Future<void> sendReadReceipts(
      Contact contact, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final enabled =
        (await storage.getSetting<bool>('read_receipts_enabled')) ?? false;
    if (!enabled) return;
    await _sendControl(contact, {'t': 'rr', 'ids': messageIds});
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
        ...extra,
        'p': _profile(),
      });
    } catch (_) {
      // síť selhala — lokální stav zůstává, protistrana se dozví později
      // jen když znovu odešleme (v1: bez retry fronty pro control zprávy)
    }
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
  //
  // Skupina nemá vlastní krypto vrstvu — každá zpráva jede existujícím
  // párovým Double Ratchet kanálem každému členovi zvlášť (`gid` v E2E
  // obsahu ji směruje do skupinové konverzace). Autor = sealed-sender
  // fingerprint, nikdy self-declared pole.

  /// Založí skupinu a rozešle pozvánku (`ginv` s úplným rosterem).
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

    await _fanoutInvite(group);
    return group;
  }

  /// Přidá členy: rozšíří roster a rozešle nový úplný stav VŠEM členům
  /// (noví z něj poprvé uvidí skupinu).
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
    group.memberIds = ids.toList();
    await storage.saveGroup(group);
    onUpdate?.call();
    await _fanoutInvite(group);
  }

  /// Přejmenuje skupinu (lokálně hned, členům `gmeta` best-effort).
  Future<void> renameGroup(Group group, String newName) async {
    group.name = newName.trim();
    await storage.saveGroup(group);
    onUpdate?.call();
    await _fanoutToGroup(group, {
      'v': 1,
      't': 'gmeta',
      'id': const Uuid().v4(),
      'gid': group.id,
      'gname': group.name,
      'p': _profile(),
    });
  }

  /// Opustí skupinu: oznámí členům `gleave`, lokálně označí `left`
  /// (historie zůstává, vstup i příjem jsou mrtvé).
  Future<void> leaveGroup(Group group) async {
    await _fanoutToGroup(group, {
      'v': 1,
      't': 'gleave',
      'id': const Uuid().v4(),
      'gid': group.id,
      'p': _profile(),
    });
    group.left = true;
    group.memberIds =
        group.memberIds.where((f) => f != _myFingerprint).toList();
    await storage.saveGroup(group);
    onUpdate?.call();
  }

  /// Odešle text do skupiny. Sémantika stavu: aspoň jeden
  /// člen přijal → `sent`; všichni selhali → `failed`; `delivered` až po
  /// první doručence.
  Future<Message> sendGroupText(Group group, String text,
      {String? replyToId}) async {
    final identity = _identity ?? (throw StateError('Service not started'));
    final ttl = await _conversationTtl(group.id);

    final message = Message.text(
      senderId: identity.id,
      recipientId: group.id,
      content: text,
      replyToId: replyToId,
      disappearAfterSeconds: ttl,
      status: MessageStatus.sending,
    );
    await storage.addMessage(group.id, message);
    onUpdate?.call();

    final anyOk = await _fanoutToGroup(group, {
      'v': 1,
      't': 'txt',
      'id': message.id,
      'gid': group.id,
      'txt': text,
      're': ?replyToId,
      'ttl': ?ttl,
      'p': _profile(),
    });
    final sent = message.copyWith(
        status: anyOk ? MessageStatus.sent : MessageStatus.failed);
    await storage.updateMessage(group.id, sent);
    onUpdate?.call();
    return sent;
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

    final anyOk = await _fanoutToGroup(group, {
      'v': 1,
      't': 'att',
      'id': message.id,
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

  /// Rozešle `ginv` s úplným rosterem všem členům kromě mě.
  Future<void> _fanoutInvite(Group group) async {
    final roster = await _buildRoster(group);
    await _fanoutToGroup(group, {
      'v': 1,
      't': 'ginv',
      'id': const Uuid().v4(),
      'gid': group.id,
      'gname': group.name,
      'roster': roster,
      'p': _profile(),
    });
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

  @visibleForTesting
  Future<Group?> debugGroupForIncoming(String gid, String senderFp) =>
      _groupForIncoming(gid, senderFp);

  /// Roster = [{f, n, ik, aid, da}] pro všechny členy včetně mě.
  /// Člen bez routingu se vynechá (příjemci mu psát nemohou, ale
  /// zprávy od něj membership guardem projdou).
  Future<List<Map<String, dynamic>>> _buildRoster(Group group) async {
    final contacts = await storage.loadContacts();
    final byFp = {for (final c in contacts) c.id: c};
    final roster = <Map<String, dynamic>>[];

    final me = shareableIdentity!;
    roster.add({
      'f': _myFingerprint,
      'n': me.displayName,
      'ik': base64Encode(me.identityKey),
      'aid': me.accountId,
      'da': base64Encode(me.deliveryAddress!),
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
      });
    }
    return roster;
  }

  /// Fanout obsahu všem členům kromě mě. Vrací true, když aspoň jedno
  /// odeslání prošlo (per-member retry v1 není — stejná hranice jako
  /// u 1:1 control zpráv).
  Future<bool> _fanoutToGroup(
      Group group, Map<String, dynamic> content) async {
    final contacts = await storage.loadContacts();
    final byFp = {for (final c in contacts) c.id: c};
    var anyOk = false;
    for (final fp in group.memberIds) {
      if (fp == _myFingerprint) continue;
      final c = byFp[fp];
      if (c == null || c.blocked) continue;
      try {
        await _sendContent(c, content);
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

  /// Zpracuje `ginv` (pozvánka / úplná aktualizace rosteru).
  /// Bezpečnostní pravidla: fingerprint každého záznamu
  /// musí sedět s jeho identity klíčem, odesílatel i já musíme být
  /// v rosteru, identity klíč existujícího kontaktu se NIKDY nepřepisuje.
  Future<void> _handleGroupInvite(
      String senderFp, Map<String, dynamic> content) async {
    final gid = content['gid'] as String?;
    final gname = (content['gname'] as String?)?.trim();
    final rosterRaw = content['roster'] as List?;
    if (gid == null || gid.isEmpty || gid.length > 64) return;
    if (gname == null || gname.isEmpty || rosterRaw == null) return;
    if (rosterRaw.length > Group.maxMembers) return;

    // Ověř roster: f musí být fingerprint ik (anti-spoof).
    final members = <String, Map<String, dynamic>>{};
    for (final raw in rosterRaw) {
      if (raw is! Map) continue;
      final e = raw.cast<String, dynamic>();
      final f = e['f'] as String?;
      final ikB64 = e['ik'] as String?;
      if (f == null || ikB64 == null) continue;
      final Uint8List ik;
      try {
        ik = base64Decode(ikB64);
      } on FormatException {
        continue;
      }
      if (SepotFingerprint.ofPublicKey(ik).display != f) continue;
      members[f] = e;
    }
    if (!members.containsKey(senderFp)) return;
    if (!members.containsKey(_myFingerprint)) return;

    final existing = await storage.loadGroup(gid);
    if (existing != null) {
      if (existing.left) return;
      // Aktualizaci rosteru smí poslat jen stávající člen.
      if (!existing.isMember(senderFp)) return;
    }

    // Neznámé členy založ jako běžné (neověřené) kontakty; existujícím
    // nanejvýš doplň chybějící routing (jen při shodě identity klíče).
    final contacts = await storage.loadContacts();
    final byFp = {for (final c in contacts) c.id: c};
    for (final e in members.values) {
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
          ));
        }
        continue;
      }
      final name = (e['n'] as String?)?.trim();
      await storage.saveContact(Contact.fromPublicIdentity(PublicIdentity(
        // Prázdné jméno = UI si doplní lokalizovaný fallback
        displayName: (name == null || name.isEmpty) ? '' : name,
        identityKey: base64Decode(e['ik'] as String),
        createdAt: DateTime.now(),
        accountId: aid,
        deliveryAddress: daB64 == null ? null : base64Decode(daB64),
      )));
    }

    final group = Group(
      id: gid,
      name: gname,
      memberIds: members.keys.toList(),
      createdBy: existing?.createdBy ?? senderFp,
      createdAt: existing?.createdAt,
    );
    await storage.saveGroup(group);
    await storage.ensureConversation(gid);
    onUpdate?.call();
  }

  /// Společná odesílací cesta: session bootstrap (X3DH s anti-MITM
  /// kontrolou identity klíče), sealed encrypt, obálka na relay.
  /// Vrací true = doručeno online, false = uloženo do offline fronty.
  Future<bool> _sendContent(
    Contact contact,
    Map<String, dynamic> content,
  ) async {
    final crypto = _crypto ?? (throw StateError('Service not started'));
    final relay = _relay!;

    final peer = contact.publicIdentity;
    final peerAid = peer.accountId;
    final peerDa = peer.deliveryAddress;
    if (peerAid == null || peerDa == null) {
      throw const ContactNoDeliveryAddressError();
    }
    final peerAddr = ProtocolAddress(name: peerAid, deviceId: 1);

    // První zpráva: X3DH z bundle. Identity klíč v bundle MUSÍ sedět
    // s klíčem z kontaktu (jinak by relay mohl podstrčit vlastní).
    if (!await crypto.hasSession(peerAddr)) {
      final bundle = await relay.fetchBundle(peerDa);
      if (!_listEquals(bundle.identityKey, peer.identityKey)) {
        throw const IdentityKeyMismatchError();
      }
      await crypto.processRemoteBundle(peerAddr, bundle);
    }

    final sealed = await crypto.sealedEncrypt(
      recipient: peerAddr,
      plaintext: utf8.encode(jsonEncode(content)),
      senderCertificate: await _senderCertificate(),
    );

    final receipt =
        await relay.sendEnvelope(dstAddress: peerDa, payload: sealed);
    return receipt.status == pb.Receipt_Status.STATUS_DELIVERED_ONLINE;
  }

  // ── Příjem ──────────────────────────────────────────────────────────

  Future<void> _onDeliver(pb.Envelope envelope) async {
    final crypto = _crypto;
    final trustRoot = _trustRoot;
    if (crypto == null || trustRoot == null) return;

    try {
      final opened = await crypto.sealedDecrypt(
        ciphertext: Uint8List.fromList(envelope.payload),
        trustRoot: trustRoot,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

      final content =
          jsonDecode(utf8.decode(opened.plaintext)) as Map<String, dynamic>;
      final type = content['t'] as String?;
      const known = {
        'txt', 'att', 'rx', 'edit', 'del', 'dlv', 'rr', // 1:1 + skupiny
        'ginv', 'gleave', 'gmeta', // správa skupin
      };
      if (content['v'] != 1 || !known.contains(type)) return;

      final contact = await _findOrCreateContact(opened, content);
      final senderFp = contact.id;

      // Blokovaný kontakt: zahoď cokoliv od něj (ACK, ať se nefrontuje),
      // nic neukládej ani nezobrazuj a neposílej doručenku.
      if (contact.blocked) {
        _relay!.ack(envelope.msgUuid);
        return;
      }

      // Správa skupin: pozvánka/roster, odchod, přejmenování. Autorita
      // = sealed-sender fingerprint; guardy uvnitř handlerů. ACK vždy
      // (retry z fronty nepomůže).
      if (type == 'ginv') {
        await _handleGroupInvite(senderFp, content);
        _relay!.ack(envelope.msgUuid);
        return;
      }
      if (type == 'gleave' || type == 'gmeta') {
        final gid = content['gid'] as String?;
        final group =
            gid == null ? null : await _groupForIncoming(gid, senderFp);
        if (group != null) {
          if (type == 'gleave') {
            group.memberIds =
                group.memberIds.where((f) => f != senderFp).toList();
          } else {
            final gname = (content['gname'] as String?)?.trim();
            if (gname != null && gname.isNotEmpty) group.name = gname;
          }
          await storage.saveGroup(group);
          onUpdate?.call();
        }
        _relay!.ack(envelope.msgUuid);
        return;
      }

      // Skupinový obsah: membership guard (skupinu znám, neopustil jsem
      // ji, odesílatel je člen) — jinak tichý drop s ACK.
      final gid = content['gid'] as String?;
      if (gid != null && await _groupForIncoming(gid, senderFp) == null) {
        _relay!.ack(envelope.msgUuid);
        return;
      }
      // Konverzace, do které obsah patří: skupina (gid), jinak 1:1.
      final convId = gid ?? contact.id;

      // Doručenka: příjemce potvrdil, že moje zpráva dorazila na jeho
      // zařízení → povýšíme ✓ (odesláno) na ✓✓ (doručeno). Off-line zprávy
      // se tak dočkají ✓✓ ve chvíli, kdy si je protistrana vyzvedne.
      // Ve skupině povyšuje první doručenka (per-member matice v2).
      if (type == 'dlv') {
        final ref = content['ref'] as String?;
        if (ref != null) {
          await _mutateLocalMessage(
            convId,
            ref,
            (m) => m.isMine(_identity!.id) &&
                    m.status != MessageStatus.delivered
                ? m.copyWith(
                    isDelivered: true, status: MessageStatus.delivered)
                : m,
          );
        }
        _relay!.ack(envelope.msgUuid);
        onUpdate?.call();
        return;
      }

      // Potvrzení přečtení: povýší moje doručené zprávy na „přečteno".
      // Respektujeme jen když mám read receipts ZAPNUTÉ (reciproční).
      if (type == 'rr') {
        final enabled =
            (await storage.getSetting<bool>('read_receipts_enabled')) ?? false;
        if (enabled) {
          // whereType přeskočí netypové prvky — podvržené 'ids' nesmí
          // shodit příjem (jinak by se obálka bez ACK doručovala donekonečna).
          final ids =
              (content['ids'] as List?)?.whereType<String>() ?? const <String>[];
          for (final id in ids) {
            await _mutateLocalMessage(
              convId,
              id,
              (m) => m.isMine(_identity!.id) &&
                      m.status != MessageStatus.read
                  ? m.copyWith(status: MessageStatus.read, isDelivered: true)
                  : m,
            );
          }
        }
        _relay!.ack(envelope.msgUuid);
        onUpdate?.call();
        return;
      }

      // Control zprávy (reakce/edit/del) mění existující zprávu, nevytvářejí
      // novou bublinu. Aplikujeme a ACKneme (retry z fronty nepomůže).
      if (type == 'rx' || type == 'edit' || type == 'del') {
        await _applyIncomingControl(convId, type!, content, opened);
        _relay!.ack(envelope.msgUuid);
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
        final text = content['txt'];
        if (text is! String) {
          // Trvale vadná obálka (chybí/netypové 'txt') — retry z fronty
          // nepomůže, ACKnout a zahodit stejně jako u vadných příloh.
          _relay!.ack(envelope.msgUuid);
          return;
        }
        message = Message(
          id: messageId,
          senderId: contact.publicIdentity.fingerprint.display,
          recipientId: _identity!.id,
          type: MessageType.text,
          content: text,
          replyToId: replyTo,
          timestamp: DateTime.now(),
          isDelivered: true,
          disappearAfterSeconds: ttl,
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
          _relay!.ack(envelope.msgUuid);
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
          timestamp: DateTime.now(),
          isDelivered: true,
          attachment: meta,
          disappearAfterSeconds: ttl,
        );
      }
      await storage.addMessage(convId, message);

      // Uloženo na disku → teprve teď smí relay obálku zahodit.
      // (Blob přílohy do fronty nepatří — stahuje se na pozadí a při
      // neúspěchu má UI retry, ACK na něj nečeká.)
      _relay!.ack(envelope.msgUuid);
      onUpdate?.call();
      onMessageReceived?.call(contact, message);

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
    } catch (_) {
      // Nedešifrovatelná/cizí obálka: NEACKovat, ať ji fronta podrží
      // (může jít o dočasný stav — např. cert refresh)
    }
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

    for (final c in contacts) {
      if (c.publicIdentity.fingerprint.display != senderFp) continue;
      // Doplnit/aktualizovat routing (accountId poprvé, rotace adresy…)
      final known = c.publicIdentity;
      if (known.accountId != opened.senderName ||
          (profileDa != null &&
              (known.deliveryAddress == null ||
                  base64Encode(known.deliveryAddress!) != profileDa))) {
        final updated = Contact(
          displayName: c.displayName,
          publicIdentity: known.withRouting(
            accountId: opened.senderName,
            deliveryAddress: profileDa != null
                ? base64Decode(profileDa)
                : known.deliveryAddress ?? Uint8List(0),
          ),
          addedAt: c.addedAt,
          verified: c.verified,
          notes: c.notes,
        );
        await storage.saveContact(updated);
        return updated;
      }
      return c;
    }

    // Neznámý odesílatel → nový (neověřený) kontakt
    // Prázdné jméno = UI si doplní lokalizovaný fallback
    final name = (profile?['n'] as String?)?.trim();
    final identity = PublicIdentity(
      displayName: (name == null || name.isEmpty) ? '' : name,
      identityKey: opened.senderIdentityKey,
      createdAt: DateTime.now(),
      accountId: opened.senderName,
      deliveryAddress: profileDa == null ? null : base64Decode(profileDa),
    );
    final contact = Contact.fromPublicIdentity(identity);
    await storage.saveContact(contact);
    return contact;
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
    _relay?.start();
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
    _purgeTimer?.cancel();
    _purgeTimer = null;
    await _deliverSub?.cancel();
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
