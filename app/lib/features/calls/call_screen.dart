import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:sepot/core/calls/call_controller.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/call_log.dart';
import 'package:sepot/widgets/avatar.dart';
import 'package:sepot/widgets/glass.dart';

/// Obrazovka hovoru: vytáčení, zvonění, spojování i hovor samotný.
/// Zavře se sama, když hovor skončí.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  // Počítadlo délky hovoru — překreslení jednou za sekundu stačí.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _status(CallState call) {
    final l10n = context.l10n;
    switch (call.phase) {
      case CallPhase.outgoing:
        return l10n.callStatusRinging;
      case CallPhase.incoming:
        return call.video ? l10n.callIncomingVideo : l10n.callIncomingVoice;
      case CallPhase.connecting:
        return l10n.callStatusConnecting;
      case CallPhase.active:
        final d = DateTime.now().difference(call.connectedAt!);
        return formatCallDuration(d.inSeconds);
      case CallPhase.ended:
        return switch (call.outcome) {
          CallOutcome.busy => l10n.callEndedBusy,
          CallOutcome.rejected => l10n.callEndedRejected,
          CallOutcome.unanswered => l10n.callEndedUnanswered,
          CallOutcome.failed => l10n.callEndedFailed,
          _ => l10n.callEnded,
        };
      case CallPhase.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);
    final controller = ref.read(callProvider.notifier);
    ref.listen(callProvider.select((s) => s.phase), (_, phase) {
      if (phase == CallPhase.idle && context.canPop()) context.pop();
    });

    final showVideo = call.video &&
        (call.phase == CallPhase.active || call.phase == CallPhase.connecting);

    return PopScope(
      // Zpět hovor neukončí ani neschová — jinak by běžel bez ovládání.
      canPop: !call.busy,
      child: Scaffold(
        backgroundColor: SepotColors.hero,
        body: Stack(
          children: [
            if (showVideo)
              Positioned.fill(
                child: RTCVideoView(
                  controller.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  if (!showVideo) ...[
                    SepotAvatar(
                        name: call.contactName,
                        seed: call.contactId,
                        size: 112),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    call.contactName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: SepotColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status(call),
                    style: const TextStyle(
                        fontSize: 16, color: SepotColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded,
                          size: 13, color: SepotColors.mist),
                      const SizedBox(width: 4),
                      Text(context.l10n.callEncrypted,
                          style: const TextStyle(
                              fontSize: 12, color: SepotColors.mist)),
                    ],
                  ),
                  const Spacer(),
                  if (call.phase == CallPhase.incoming)
                    _IncomingActions(
                      onAccept: controller.accept,
                      onReject: controller.reject,
                    )
                  else if (call.busy)
                    _InCallControls(call: call, controller: controller),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            if (showVideo && !call.cameraOff)
              Positioned(
                right: 16,
                top: MediaQuery.paddingOf(context).top + 16,
                width: 108,
                height: 152,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    controller.localRenderer,
                    mirror: true,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IncomingActions extends StatelessWidget {
  const _IncomingActions({required this.onAccept, required this.onReject});

  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundAction(
          icon: Icons.call_end_rounded,
          label: l10n.callReject,
          color: SepotColors.error,
          onTap: onReject,
        ),
        _RoundAction(
          icon: Icons.call_rounded,
          label: l10n.callAccept,
          color: SepotColors.sage,
          onTap: onAccept,
        ),
      ],
    );
  }
}

class _InCallControls extends StatelessWidget {
  const _InCallControls({required this.call, required this.controller});

  final CallState call;
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(32),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ToggleAction(
              icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: l10n.callMute,
              active: call.muted,
              onTap: controller.toggleMute,
            ),
            _ToggleAction(
              icon: Icons.volume_up_rounded,
              label: l10n.callSpeaker,
              active: call.speaker,
              onTap: controller.toggleSpeaker,
            ),
            if (call.video) ...[
              _ToggleAction(
                icon: call.cameraOff
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                label: l10n.callCamera,
                active: call.cameraOff,
                onTap: controller.toggleCamera,
              ),
              _ToggleAction(
                icon: Icons.cameraswitch_rounded,
                label: l10n.callSwitchCamera,
                active: false,
                onTap: controller.switchCamera,
              ),
            ],
            _RoundAction(
              icon: Icons.call_end_rounded,
              label: l10n.callHangUp,
              color: SepotColors.error,
              onTap: controller.hangUp,
              size: 56,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleAction extends StatelessWidget {
  const _ToggleAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? SepotColors.textPrimary
                : SepotColors.textPrimary.withValues(alpha: 0.1),
          ),
          child: Icon(icon,
              color: active ? SepotColors.background : SepotColors.textPrimary),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.size = 72,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2 + 8,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: SepotColors.background, size: size * 0.42),
        ),
      ),
    );
  }
}

/// „3:12“, u dlouhého hovoru „1:03:12“.
String formatCallDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
