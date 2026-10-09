/// Klient hloupého relaye — REST (registrace, prekey bundle, sender
/// certificate) + WS (AUTH výzva, obálky, doručení, ACK).
///
/// Wire = protobuf rámce z `proto/sepot.proto` (jediný zdroj pravdy pro
/// Dart i Rust). Klient NIKDY neposílá nic nešifrovaného — payload obálky
/// je sealed-sender ciphertext, relay vidí jen dst_address + msg_uuid.
///
/// ACK sémantika: relay maže zprávu z fronty při ACK (hard delete).
/// ACK se proto posílá až PO uložení dešifrované zprávy na disk —
/// jinak pád mezi doručením a uložením = ztracená zpráva.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sepot/core/crypto/sepot_crypto.dart';
import 'package:sepot/core/network/relay_transport.dart';
import 'package:sepot/proto/sepot.pb.dart' as pb;
import 'package:web_socket_channel/web_socket_channel.dart';

enum RelayConnectionState { disconnected, connecting, connected }

/// Výsledek registrace účtu na relayi.
class RelayRegistration {
  RelayRegistration({required this.accountId, required this.deviceUuid});

  final String accountId; // hex
  final String deviceUuid; // hex
}

class RelayClient {
  RelayClient({
    required this.baseUrl,
    required SepotCrypto crypto,
    RelayTransport? transport,
  })  : _crypto = crypto,
        _transport = transport ?? DirectTransport();

  final String baseUrl;
  final SepotCrypto _crypto;

  /// Jak se otevírají spojení (přímé vs Tor). Vlastní ho tento klient —
  /// [dispose] ho zavře.
  final RelayTransport _transport;

  String get _wsUrl => baseUrl.replaceFirst('http', 'ws');

  String? _deviceUuid;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  var _reconnectDelayS = 1;
  var _shouldRun = false;

  /// Poslední požadovaná push registrace. Drží se, aby se dala znovu odeslat
  /// po každém (re)connectu — WS je jediná autentizovaná cesta a endpoint se
  /// u distributora může měnit.
  pb.RegisterPush? _pendingPush;

  final _stateController =
      StreamController<RelayConnectionState>.broadcast();
  final _deliverController = StreamController<pb.Envelope>.broadcast();
  final _receiptController = StreamController<pb.Receipt>.broadcast();
  final _turnController = StreamController<pb.TurnCredentials>.broadcast();
  final _prekeysLowController = StreamController<int>.broadcast();

  var _state = RelayConnectionState.disconnected;

  /// Kdy naposled přišel aplikační rámec od relaye.
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _staleAfter = Duration(seconds: 20);

  /// Relay hlásí docházející one-time prekeys (zbývající počet).
  Stream<int> get prekeysLow => _prekeysLowController.stream;

  RelayConnectionState get state => _state;
  Stream<RelayConnectionState> get stateStream => _stateController.stream;

  /// Příchozí obálky (offline fronta i online doručení). Konzument MUSÍ
  /// po uložení zavolat [ack].
  Stream<pb.Envelope> get deliveries => _deliverController.stream;

  void _setState(RelayConnectionState s) {
    _state = s;
    // Po dispose() je controller zavřený — pozdní přechod z doběhnutého
    // _connect (zombie) by jinak hodil StateError do listenerů.
    if (_stateController.isClosed) return;
    _stateController.add(s);
  }

  static Uint8List randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  }

  static Uint8List hexToBytes(String hexStr) => Uint8List.fromList([
        for (var i = 0; i < hexStr.length; i += 2)
          int.parse(hexStr.substring(i, i + 2), radix: 16),
      ]);

  // ── REST ────────────────────────────────────────────────────────────

  /// POST /v1/register — nahraje identitu + prekey bundle + dávku OTP.
  Future<RelayRegistration> register({
    required SepotPreKeyBundle bundle,
    required List<SepotOneTimePreKey> oneTimePreKeys,
    required Uint8List deliveryAddress,
  }) async {
    // Důkaz držení identity klíče: obnova ze 24 slov na novém telefonu
    // narazí na relayi na už existující identitu (409) a bez tohohle
    // podpisu by ji nikdy nepřevzala. Starší relay hlavičku
    // ignoruje.
    final proofTs = DateTime.now().millisecondsSinceEpoch;
    final proof = _crypto.sign(utf8.encode('POST /v1/register\n$proofTs'));
    final resp = await _transport.httpClient().post(
      Uri.parse('$baseUrl/v1/register'),
      headers: {
        'content-type': 'application/json',
        'x-sepot-identity-proof': '$proofTs.${base64Encode(proof)}',
      },
      body: jsonEncode({
        'identity_key': base64Encode(_crypto.identityPublicKey),
        'device_id': 1,
        'registration_id': _crypto.registrationId,
        'delivery_address': base64Encode(deliveryAddress),
        'signed_prekey': {
          'key_id': bundle.signedPreKeyId,
          'public_key': base64Encode(bundle.signedPreKeyPublic),
          'signature': base64Encode(bundle.signedPreKeySignature),
        },
        'kyber_prekey': {
          'key_id': bundle.kyberPreKeyId,
          'public_key': base64Encode(bundle.kyberPreKeyPublic),
          'signature': base64Encode(bundle.kyberPreKeySignature),
          'is_last_resort': true,
        },
        'one_time_prekeys': [
          for (final otp in oneTimePreKeys)
            {'key_id': otp.id, 'public_key': base64Encode(otp.publicKey)},
        ],
      }),
    );
    if (resp.statusCode != 201) {
      throw RelayException('registration failed', resp.statusCode, resp.body);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final reg = RelayRegistration(
      accountId: body['account_id'] as String,
      deviceUuid: body['device_uuid'] as String,
    );
    _deviceUuid = reg.deviceUuid;
    _crypto.bindAccount(reg.accountId);
    return reg;
  }

  /// Obnoví vazbu po startu aplikace (registrace už proběhla dřív).
  void restoreSession({required String accountId, required String deviceUuid}) {
    _deviceUuid = deviceUuid;
    _crypto.bindAccount(accountId);
  }

  /// POST /v1/keys — doplnění one-time prekeys a rotace signed / Kyber
  /// prekey. Vrací počet OTP na relayi po nahrání.
  Future<int> uploadKeys({
    SepotSignedPreKey? signedPreKey,
    SepotKyberPreKey? kyberPreKey,
    List<SepotOneTimePreKey> oneTimePreKeys = const [],
  }) async {
    final deviceUuid = _requireDevice();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final signature = _crypto.sign(utf8.encode('POST /v1/keys\n$ts'));
    final resp = await _transport.httpClient().post(
      Uri.parse('$baseUrl/v1/keys'),
      headers: {
        'content-type': 'application/json',
        'x-sepot-auth': '$deviceUuid.$ts.${base64Encode(signature)}',
      },
      body: jsonEncode({
        if (signedPreKey != null)
          'signed_prekey': {
            'key_id': signedPreKey.id,
            'public_key': base64Encode(signedPreKey.publicKey),
            'signature': base64Encode(signedPreKey.signature),
          },
        if (kyberPreKey != null)
          'kyber_prekey': {
            'key_id': kyberPreKey.id,
            'public_key': base64Encode(kyberPreKey.publicKey),
            'signature': base64Encode(kyberPreKey.signature),
            'is_last_resort': true,
          },
        'one_time_prekeys': [
          for (final otp in oneTimePreKeys)
            {'key_id': otp.id, 'public_key': base64Encode(otp.publicKey)},
        ],
      }),
    );
    if (resp.statusCode != 200) {
      throw RelayException('prekey upload failed', resp.statusCode, resp.body);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['one_time_prekeys'] as num?)?.toInt() ?? 0;
  }

  /// GET /v1/keys/{addr} — bundle protistrany (spotřebuje 1 OTP).
  Future<SepotPreKeyBundle> fetchBundle(Uint8List deliveryAddress) async {
    final hexAddr = deliveryAddress
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final resp =
        await _transport.httpClient().get(Uri.parse('$baseUrl/v1/keys/$hexAddr'));
    if (resp.statusCode != 200) {
      throw RelayException('prekey bundle fetch failed', resp.statusCode, resp.body);
    }
    final device = (jsonDecode(resp.body)['devices'] as List).first
        as Map<String, dynamic>;
    final spk = device['signed_prekey'] as Map<String, dynamic>;
    final kyber = device['kyber_prekey'] as Map<String, dynamic>;
    final otp = device['one_time_prekey'] as Map<String, dynamic>?;
    return SepotPreKeyBundle(
      registrationId: device['registration_id'] as int,
      deviceId: device['device_id'] as int,
      preKeyId: otp?['key_id'] as int?,
      preKeyPublic: otp == null
          ? null
          : Uint8List.fromList(base64Decode(otp['public_key'] as String)),
      signedPreKeyId: spk['key_id'] as int,
      signedPreKeyPublic:
          Uint8List.fromList(base64Decode(spk['public_key'] as String)),
      signedPreKeySignature:
          Uint8List.fromList(base64Decode(spk['signature'] as String)),
      identityKey:
          Uint8List.fromList(base64Decode(device['identity_key'] as String)),
      kyberPreKeyId: kyber['key_id'] as int,
      kyberPreKeyPublic:
          Uint8List.fromList(base64Decode(kyber['public_key'] as String)),
      kyberPreKeySignature:
          Uint8List.fromList(base64Decode(kyber['signature'] as String)),
    );
  }

  /// POST /v1/attachments — nahraje šifrovaný blob přílohy. Tělo = raw
  /// bajty (ciphertext || tag); relay z nich nic nevyčte a vazbu na
  /// zařízení si neukládá. Auth stejným podpisem jako sender certificate.
  Future<String> uploadAttachment(Uint8List blob) async {
    final deviceUuid = _requireDevice();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final signature = _crypto.sign(utf8.encode('POST /v1/attachments\n$ts'));
    final resp = await _transport
        .httpClient()
        .post(
          Uri.parse('$baseUrl/v1/attachments'),
          headers: {
            'x-sepot-auth': '$deviceUuid.$ts.${base64Encode(signature)}',
            'content-type': 'application/octet-stream',
          },
          body: blob,
        )
        .timeout(const Duration(minutes: 3));
    if (resp.statusCode != 201) {
      throw RelayException('attachment upload failed', resp.statusCode, resp.body);
    }
    return (jsonDecode(resp.body) as Map<String, dynamic>)['blob_id'] as String;
  }

  /// GET /v1/attachments/{blob_id} — stáhne šifrovaný blob. Bez auth
  /// (blob_id = bearer capability z E2E zprávy). Integrita se ověřuje
  /// až v AttachmentCipher.decrypt proti digestu ze zprávy.
  Future<Uint8List> downloadAttachment(String blobId) async {
    final resp = await _transport
        .httpClient()
        .get(Uri.parse('$baseUrl/v1/attachments/$blobId'))
        .timeout(const Duration(minutes: 3));
    if (resp.statusCode != 200) {
      throw RelayException(
          'attachment download failed', resp.statusCode, resp.body);
    }
    return resp.bodyBytes;
  }

  /// DELETE /v1/identity — deregistrace účtu na relayi (identita,
  /// zařízení, prekeys, push token i nedoručená fronta). Auth stejným
  /// podpisem jako sender certificate — smazat účet smí jen držitel
  /// identity klíče. Volá se PŘED lokálním wipe (podpis potřebuje klíč).
  Future<void> deleteIdentity() async {
    final deviceUuid = _requireDevice();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final signature = _crypto.sign(utf8.encode('DELETE /v1/identity\n$ts'));
    final resp = await _transport
        .httpClient()
        .delete(
          Uri.parse('$baseUrl/v1/identity'),
          headers: {
            'x-sepot-auth': '$deviceUuid.$ts.${base64Encode(signature)}',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 204) {
      throw RelayException(
          'identity deletion failed', resp.statusCode, resp.body);
    }
  }

  /// GET /v1/certificate/delivery — krátkodobý SenderCertificate
  /// + pinovaný trust root relaye.
  Future<(Uint8List cert, Uint8List trustRoot)>
      fetchSenderCertificate() async {
    final deviceUuid = _requireDevice();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final signature =
        _crypto.sign(utf8.encode('GET /v1/certificate/delivery\n$ts'));
    final resp = await _transport.httpClient().get(
      Uri.parse('$baseUrl/v1/certificate/delivery'),
      headers: {'x-sepot-auth': '$deviceUuid.$ts.${base64Encode(signature)}'},
    );
    if (resp.statusCode != 200) {
      throw RelayException('sender certificate fetch failed', resp.statusCode, resp.body);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      Uint8List.fromList(base64Decode(body['sender_certificate'] as String)),
      Uint8List.fromList(base64Decode(body['trust_root'] as String)),
    );
  }

  // ── WS ──────────────────────────────────────────────────────────────

  /// Spustí spojení s automatickým reconnectem (exponenciální backoff).
  void start() {
    _shouldRun = true;
    _connect();
  }

  Future<void> stop() async {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    await _teardownChannel();
    _setState(RelayConnectionState.disconnected);
  }

  /// Budíček od relaye znamená, že nás nevidí jako živé. Spojení, které
  /// hlásí „připojeno", ale [_staleAfter] nic nepřijalo, je po změně sítě
  /// nejspíš zombie — zavřít a navázat hned, ne až po ping timeoutu
  /// (pojistka proti zombie spojení na straně appky). Jinak jen [start].
  void kick() {
    if (_state == RelayConnectionState.connected &&
        DateTime.now().difference(_lastFrameAt) > _staleAfter) {
      _reconnectDelayS = 1;
      _onDisconnected();
      return;
    }
    start();
  }

  Future<void> _teardownChannel() async {
    await _wsSub?.cancel();
    _wsSub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> _connect() async {
    if (!_shouldRun || _state != RelayConnectionState.disconnected) return;
    final deviceUuid = _deviceUuid;
    if (deviceUuid == null) return;

    _setState(RelayConnectionState.connecting);
    try {
      final channel = _transport.connectWs(Uri.parse('$_wsUrl/v1/ws'));
      await channel.ready;
      // Během `ready` (přes Tor může viset dlouho) mohl přijít stop()/dispose()
      // — Tor toggle nebo auto-lock. Bez téhle kontroly by vzniklo zombie
      // autentizované spojení (relay má 2× jedno zařízení, DELIVERy padají do
      // zavřených controllerů). Nezakládat ho, jen zavřít.
      if (!_shouldRun) {
        await channel.sink.close();
        return;
      }
      _channel = channel;

      // AUTH: výzva-odpověď podepsaná identity klíčem (XEdDSA)
      final nonceClient = randomBytes(16);
      var authenticated = false;

      _wsSub = channel.stream.listen(
        (data) {
          final frame = pb.ServerFrame.fromBuffer(data as List<int>);
          _lastFrameAt = DateTime.now();
          if (!authenticated) {
            if (frame.hasChallenge()) {
              final signature = _crypto.sign([
                ...nonceClient,
                ...frame.challenge.nonceServer,
                ...utf8.encode('sepot-auth-v1'),
              ]);
              _send(pb.ClientFrame(
                authProof: pb.AuthProof(signature: signature),
              ));
            } else if (frame.hasAuthOk()) {
              // Server podpis OVĚŘIL — teprve teď jsme reálně připojeni
              authenticated = true;
              _reconnectDelayS = 1;
              _setState(RelayConnectionState.connected);
              // Push endpoint se re-registruje po každém (re)connectu.
              _sendPush();
            }
            return;
          }
          if (frame.hasDeliver()) {
            if (!_deliverController.isClosed) {
              _deliverController.add(frame.deliver);
            }
          } else if (frame.hasReceipt()) {
            if (!_receiptController.isClosed) {
              _receiptController.add(frame.receipt);
            }
          } else if (frame.hasTurnCredentials()) {
            if (!_turnController.isClosed) {
              _turnController.add(frame.turnCredentials);
            }
          } else if (frame.hasPrekeysLow()) {
            if (!_prekeysLowController.isClosed) {
              _prekeysLowController.add(frame.prekeysLow.remaining);
            }
          }
        },
        onDone: _onDisconnected,
        onError: (Object _) => _onDisconnected(),
      );

      _send(pb.ClientFrame(
        auth: pb.Auth(
          deviceUuid: hexToBytes(deviceUuid),
          nonceClient: nonceClient,
        ),
      ));
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    unawaited(_teardownChannel());
    _setState(RelayConnectionState.disconnected);
    if (!_shouldRun) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelayS), _connect);
    _reconnectDelayS = min(_reconnectDelayS * 2, 60);
  }

  void _send(pb.ClientFrame frame) {
    final channel = _channel;
    if (channel == null) throw StateError('WebSocket not connected');
    channel.sink.add(frame.writeToBuffer());
  }

  /// Odešle sealed-sender obálku. Vrací Receipt (STORED_OFFLINE /
  /// DELIVERED_ONLINE, u EPHEMERAL i DROPPED) spárovaný přes msg_uuid.
  Future<pb.Receipt> sendEnvelope({
    required Uint8List dstAddress,
    required Uint8List payload,
    pb.ContentHint hint = pb.ContentHint.CONTENT_HINT_DEFAULT,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final msgUuid = randomBytes(16);
    final receiptFuture = _receiptController.stream
        .firstWhere((r) => _bytesEqual(r.msgUuid, msgUuid))
        .timeout(timeout);
    try {
      _send(pb.ClientFrame(
        envelope: pb.Envelope(
          dstAddress: dstAddress,
          msgUuid: msgUuid,
          contentHint: hint,
          payload: payload,
        ),
      ));
    } catch (_) {
      // Odeslání selhalo (kanál zavřený) — čekající future by za 10 s
      // hodil neodchycený TimeoutException do zvonku chyb.
      receiptFuture.ignore();
      rethrow;
    }
    return receiptFuture;
  }

  /// Dočasné údaje k TURN serveru pro hovor. Relay je vydá jen přihlášenému
  /// zařízení; bez TURN na relayi (503) doběhne timeout a hovor zkusí jen
  /// přímé spojení přes STUN.
  Future<pb.TurnCredentials> requestTurn({
    Duration timeout = const Duration(seconds: 5),
  }) {
    final future = _turnController.stream.first.timeout(timeout);
    _send(pb.ClientFrame(turnRequest: pb.TurnRequest()));
    return future;
  }

  /// Potvrdí zpracování obálky — relay ji smaže z fronty. Volat až PO
  /// uložení zprávy na disk.
  void ack(List<int> msgUuid) {
    _send(pb.ClientFrame(ack: pb.Ack(msgUuid: msgUuid)));
  }

  /// Nastaví/aktualizuje push registraci u relaye. Bezpečné volat kdykoliv:
  /// požadavek se zapamatuje a odešle po autentizaci (a znovu po každém
  /// reconnectu — endpoint distributora se může měnit). platform=NONE push
  /// vypne (relay token smaže → anonymní režim).
  void registerPush(pb.RegisterPush registration) {
    _pendingPush = registration;
    if (_state == RelayConnectionState.connected) {
      _sendPush();
    }
  }

  void _sendPush() {
    final reg = _pendingPush;
    if (reg == null || _channel == null) return;
    _send(pb.ClientFrame(registerPush: reg));
  }

  String _requireDevice() {
    final d = _deviceUuid;
    if (d == null) {
      throw StateError('Call register() or restoreSession() first');
    }
    return d;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> dispose() async {
    await stop();
    _transport.close();
    await _stateController.close();
    await _turnController.close();
    await _prekeysLowController.close();
    await _deliverController.close();
    await _receiptController.close();
  }
}

class RelayException implements Exception {
  RelayException(this.message, this.statusCode, this.body);

  final String message;
  final int statusCode;
  final String body;

  @override
  String toString() => 'RelayException($statusCode): $message — $body';
}
