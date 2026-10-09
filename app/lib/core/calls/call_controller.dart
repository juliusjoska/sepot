import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;
import 'package:sepot/core/calls/call_ringer.dart';
import 'package:sepot/models/call_log.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/push_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:uuid/uuid.dart';

/// Fáze hovoru.
enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

class CallState {
  const CallState({
    this.phase = CallPhase.idle,
    this.callId,
    this.contactId,
    this.contactName = '',
    this.video = false,
    this.outgoing = false,
    this.connectedAt,
    this.muted = false,
    this.speaker = false,
    this.cameraOff = false,
    this.outcome,
  });

  final CallPhase phase;
  final String? callId;
  final String? contactId;
  final String contactName;
  final bool video;
  final bool outgoing;
  final DateTime? connectedAt;
  final bool muted;
  final bool speaker;
  final bool cameraOff;

  /// Proč hovor skončil (jen ve fázi [CallPhase.ended]).
  final CallOutcome? outcome;

  bool get busy => phase != CallPhase.idle && phase != CallPhase.ended;

  CallState copyWith({
    CallPhase? phase,
    DateTime? connectedAt,
    bool? muted,
    bool? speaker,
    bool? cameraOff,
    CallOutcome? outcome,
  }) =>
      CallState(
        phase: phase ?? this.phase,
        callId: callId,
        contactId: contactId,
        contactName: contactName,
        video: video,
        outgoing: outgoing,
        connectedAt: connectedAt ?? this.connectedAt,
        muted: muted ?? this.muted,
        speaker: speaker ?? this.speaker,
        cameraOff: cameraOff ?? this.cameraOff,
        outcome: outcome ?? this.outcome,
      );
}

/// Řídí jeden hovor 1:1: WebRTC spojení, signalizaci přes E2E kanál
/// Šepotu a záznam výsledku do chatu. Druhý souběžný hovor se odmítne
/// jako `busy`.
class CallController extends Notifier<CallState> {
  /// Nabídka starší než tohle už nezvoní — jen se zapíše jako zmeškaná.
  /// Stejná mez jako expirace VoIP pushe na relayi.
  static const ringTimeout = Duration(seconds: 45);

  /// ICE bez trickle: nabídka jde až po sběru kandidátů, nejdéle po této
  /// době (jinak by pomalé rozhraní zdrželo zvonění).
  static const _iceGatherTimeout = Duration(seconds: 3);

  /// Jak dlouho je vidět obrazovka „Hovor skončil“, než se zavře.
  static const endedLinger = Duration(seconds: 2);

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  String? _pendingOfferSdp;
  Contact? _peer;
  Timer? _ringTimer;

  /// Id systémového zvonění (CallKit / Android) k běžícímu příchozímu
  /// hovoru; null = zvoní jen obrazovka appky.
  String? _ringId;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  @override
  CallState build() {
    CallRinger.listen(
      onAccept: _onRingAccept,
      onDecline: _onRingDecline,
      onEnded: _onRingEnded,
      onVoipToken: () => ref.read(pushServiceProvider).refreshVoipToken(),
    );
    ref.onDispose(() {
      unawaited(_cleanup());
      localRenderer.dispose();
      remoteRenderer.dispose();
    });
    return const CallState();
  }

  // ── Odchozí ────────────────────────────────────────────────────────

  Future<void> startCall(Contact contact, {required bool video}) async {
    if (state.busy) return;
    _peer = contact;
    state = CallState(
      phase: CallPhase.outgoing,
      callId: const Uuid().v4(),
      contactId: contact.id,
      contactName: contact.displayName,
      video: video,
      outgoing: true,
      speaker: video,
    );
    try {
      await _openMedia(video: video);
      final pc = await _createPeerConnection();
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final sdp = await _gatheredSdp(pc);
      await ref.read(messagingServiceProvider).sendCallSignal(
        contact,
        {'cid': state.callId, 'k': 'offer', 'sdp': sdp, 'vid': video},
        ring: true,
      );
      _ringTimer = Timer(ringTimeout, () {
        if (state.phase == CallPhase.outgoing) {
          unawaited(_hangup(CallOutcome.unanswered, notify: true));
        }
      });
    } catch (_) {
      await _finish(CallOutcome.failed);
    }
  }

  // ── Příchozí ───────────────────────────────────────────────────────

  /// Obsluha příchozí signalizace z [MessagingService.onCallSignal].
  Future<void> onSignal(Contact contact, Map<String, dynamic> signal) async {
    final cid = signal['cid'];
    final kind = signal['k'];
    if (cid is! String || kind is! String) return;

    if (kind == 'offer') {
      await _onOffer(contact, cid, signal);
      return;
    }
    // Ostatní patří jen k právě běžícímu hovoru s tímtéž člověkem.
    if (cid != state.callId || contact.id != state.contactId) return;
    switch (kind) {
      case 'answer':
        final sdp = signal['sdp'];
        if (sdp is! String || state.phase != CallPhase.outgoing) return;
        _ringTimer?.cancel();
        state = state.copyWith(phase: CallPhase.connecting);
        await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      case 'hangup':
        final answered = state.connectedAt != null;
        await _finish(answered
            ? CallOutcome.completed
            : state.outgoing
                ? CallOutcome.rejected
                : CallOutcome.missed);
      case 'reject':
        await _finish(CallOutcome.rejected);
      case 'busy':
        await _finish(CallOutcome.busy);
    }
  }

  Future<void> _onOffer(
      Contact contact, String cid, Map<String, dynamic> signal) async {
    final sdp = signal['sdp'];
    if (sdp is! String) return;
    final video = signal['vid'] == true;
    final sentAt = DateTime.fromMillisecondsSinceEpoch(
        (signal['ts'] as num?)?.toInt() ?? 0);
    // Pozdě doručená nabídka (telefon byl mimo signál) — nezvonit.
    if (DateTime.now().difference(sentAt) > ringTimeout) {
      await _log(contact.id,
          CallLog(outcome: CallOutcome.missed, outgoing: false, video: video),
          at: sentAt);
      return;
    }
    if (state.busy) {
      if (cid != state.callId) {
        await ref
            .read(messagingServiceProvider)
            .sendCallSignal(contact, {'cid': cid, 'k': 'busy'});
      }
      return;
    }
    _peer = contact;
    _pendingOfferSdp = sdp;
    state = CallState(
      phase: CallPhase.incoming,
      callId: cid,
      contactId: contact.id,
      contactName: contact.displayName,
      video: video,
      speaker: video,
    );
    _ringTimer = Timer(ringTimeout, () {
      if (state.phase == CallPhase.incoming) {
        unawaited(_finish(CallOutcome.missed));
      }
    });
    await _attachSystemRing(cid, contact.displayName, video);
  }

  /// Spáruje hovor se systémovým zvoněním. Zvonění z budíčku relaye už
  /// běží (možná ho uživatel mezitím přijal na zamčené obrazovce); jinak
  /// se zvonění spustí, jen když appka není v popředí — v popředí stačí
  /// vlastní obrazovka hovoru.
  Future<void> _attachSystemRing(String cid, String name, bool video) async {
    final pushRing = await CallRinger.pendingPushRing();
    if (pushRing != null) {
      _ringId = pushRing.id;
      if (pushRing.accepted) {
        await accept();
        return;
      }
      if (CallRinger.declinedEarly.remove(pushRing.id)) {
        await reject();
        return;
      }
      // Spárováno s nabídkou: aby grace z `ringFromPush` zvonění neukončila,
      // nahradí se jménem volajícího (bez značky push).
      await _claimPushRing(pushRing.id, name, video);
      return;
    }
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!foreground) {
      _ringId = cid;
      await CallRinger.ringFor(callId: cid, name: name, video: video);
    }
  }

  /// Převezme zvonění z budíčku: jméno volajícího místo „Šepot" a bez
  /// značky push (grace v [CallRinger.ringFromPush] ho pak nechá být).
  Future<void> _claimPushRing(String pushId, String name, bool video) async {
    if (await CallRinger.isAccepted(pushId)) return; // uživatel už zvedl
    await CallRinger.end(pushId);
    _ringId = state.callId;
    await CallRinger.ringFor(callId: state.callId!, name: name, video: video);
  }

  void _onRingAccept(String id) {
    if (id == _ringId && state.phase == CallPhase.incoming) {
      unawaited(accept());
    }
  }

  void _onRingDecline(String id) {
    if (id == _ringId && state.phase == CallPhase.incoming) {
      unawaited(reject());
    } else if (!state.busy) {
      CallRinger.declinedEarly.add(id);
    }
  }

  /// Zavěšení ze systémového rozhraní (zamčená obrazovka, sluchátka).
  void _onRingEnded(String id) {
    if (id == _ringId && state.busy) unawaited(hangUp());
  }

  Future<void> accept() async {
    final peer = _peer;
    final offer = _pendingOfferSdp;
    if (state.phase != CallPhase.incoming || peer == null || offer == null) {
      return;
    }
    _ringTimer?.cancel();
    state = state.copyWith(phase: CallPhase.connecting);
    try {
      await _openMedia(video: state.video);
      final pc = await _createPeerConnection();
      await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final sdp = await _gatheredSdp(pc);
      await ref.read(messagingServiceProvider).sendCallSignal(
          peer, {'cid': state.callId, 'k': 'answer', 'sdp': sdp});
    } catch (_) {
      await _hangup(CallOutcome.failed, notify: true);
    }
  }

  Future<void> reject() async {
    if (state.phase != CallPhase.incoming) return;
    await _hangup(CallOutcome.rejected, notify: true, kind: 'reject');
  }

  /// Zavěšení v jakékoli fázi (vytáčení, spojování, hovor).
  Future<void> hangUp() async {
    if (!state.busy) return;
    final outcome = state.connectedAt != null
        ? CallOutcome.completed
        : state.outgoing
            ? CallOutcome.unanswered
            : CallOutcome.rejected;
    await _hangup(outcome, notify: true);
  }

  // ── Ovládání během hovoru ──────────────────────────────────────────

  void toggleMute() {
    final muted = !state.muted;
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      t.enabled = !muted;
    }
    state = state.copyWith(muted: muted);
  }

  Future<void> toggleSpeaker() async {
    final speaker = !state.speaker;
    await Helper.setSpeakerphoneOn(speaker);
    state = state.copyWith(speaker: speaker);
  }

  void toggleCamera() {
    final off = !state.cameraOff;
    for (final t in _localStream?.getVideoTracks() ?? const []) {
      t.enabled = !off;
    }
    state = state.copyWith(cameraOff: off);
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  // ── WebRTC ─────────────────────────────────────────────────────────

  Future<void> _openMedia({required bool video}) async {
    if (!_renderersReady) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersReady = true;
    }
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    _localStream = stream;
    localRenderer.srcObject = video ? stream : null;
    await Helper.setSpeakerphoneOn(video);
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection({
      'iceServers': await _iceServers(),
      'sdpSemantics': 'unified-plan',
    });
    final local = _localStream;
    for (final track in local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await pc.addTrack(track, local!);
    }
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
      }
    };
    pc.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          if (state.connectedAt == null) {
            state = state.copyWith(
                phase: CallPhase.active, connectedAt: DateTime.now());
            final ring = _ringId;
            if (ring != null) unawaited(CallRinger.connected(ring));
          }
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          unawaited(_hangup(
              state.connectedAt != null
                  ? CallOutcome.completed
                  : CallOutcome.failed,
              notify: true));
        default:
          break;
      }
    };
    _pc = pc;
    return pc;
  }

  /// STUN bez údajů: coturn na témž hostiteli odpovídá na STUN bez
  /// přihlášení, takže i když relay TURN údaje nevydá (503, timeout),
  /// jde aspoň přímé spojení přes NAT. Dřív byl seznam prázdný = jen host
  /// kandidáti = hovor jen v jedné LAN.
  static const _stunFallback = {
    'urls': ['stun:turn.sepot.cz:3478'],
  };

  /// STUN i TURN běží na stejném serveru; bez údajů z relaye aspoň STUN
  /// (přímé spojení, když obě strany nejsou za symetrickým NATem).
  Future<List<Map<String, dynamic>>> _iceServers() async {
    final turn = await ref.read(messagingServiceProvider).turnCredentials();
    if (turn == null || turn.urls.isEmpty) return const [_stunFallback];
    return [
      {
        'urls': turn.urls,
        'username': turn.username,
        'credential': turn.credential,
      },
    ];
  }

  /// SDP po sběru ICE kandidátů (non-trickle).
  Future<String> _gatheredSdp(RTCPeerConnection pc) async {
    final done = Completer<void>();
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    };
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      done.complete();
    }
    await done.future.timeout(_iceGatherTimeout, onTimeout: () {});
    final local = await pc.getLocalDescription();
    final sdp = local?.sdp;
    if (sdp == null) throw StateError('no local description');
    return sdp;
  }

  // ── Konec hovoru ───────────────────────────────────────────────────

  Future<void> _hangup(CallOutcome outcome,
      {required bool notify, String kind = 'hangup'}) async {
    final peer = _peer;
    final cid = state.callId;
    if (notify && peer != null && cid != null) {
      try {
        await ref
            .read(messagingServiceProvider)
            .sendCallSignal(peer, {'cid': cid, 'k': kind});
      } catch (_) {
        // Protistrana zavěšení nedostala — její hovor skončí sám, až
        // spojení vypadne (ICE failed) nebo vyprší zvonění.
      }
    }
    await _finish(outcome);
  }

  Future<void> _finish(CallOutcome outcome) async {
    if (state.phase == CallPhase.idle || state.phase == CallPhase.ended) {
      return;
    }
    final connectedAt = state.connectedAt;
    final contactId = state.contactId;
    final log = CallLog(
      outcome: outcome,
      outgoing: state.outgoing,
      video: state.video,
      durationSeconds: connectedAt == null
          ? 0
          : DateTime.now().difference(connectedAt).inSeconds,
    );
    state = state.copyWith(phase: CallPhase.ended, outcome: outcome);
    await _cleanup();
    if (contactId != null) await _log(contactId, log);
    Timer(endedLinger, () {
      if (state.phase == CallPhase.ended) state = const CallState();
    });
  }

  Future<void> _cleanup() async {
    _ringTimer?.cancel();
    _ringTimer = null;
    final ring = _ringId;
    _ringId = null;
    // Konec zvonění vyvolá událost „ukončeno“ — to už je stav mimo hovor,
    // takže ji _onRingEnded ignoruje.
    if (ring != null) unawaited(CallRinger.end(ring));
    _pendingOfferSdp = null;
    _peer = null;
    for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _pc?.close();
    _pc = null;
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
  }

  /// Řádek „Hovor · 3:12“ do chatu. Jen lokálně — nic se neposílá.
  Future<void> _log(String contactId, CallLog log, {DateTime? at}) async {
    final myId = ref.read(identityProvider).valueOrNull?.id;
    if (myId == null) return;
    final message = Message(
      id: const Uuid().v4(),
      senderId: log.outgoing ? myId : contactId,
      recipientId: log.outgoing ? contactId : myId,
      type: MessageType.text,
      timestamp: at ?? DateTime.now(),
      // Záznam hovoru není nepřečtená zpráva — kromě zmeškaného.
      isRead: log.outcome != CallOutcome.missed,
      isDelivered: true,
      callLog: log,
    );
    await ref.read(storageProvider).addMessage(contactId, message);
    ref.invalidate(conversationsProvider);
    ref.invalidate(conversationProvider(contactId));
  }
}

final callProvider =
    NotifierProvider<CallController, CallState>(CallController.new);
