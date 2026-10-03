import 'package:flutter/material.dart';
import 'package:sepot/features/calls/call_screen.dart';
import 'package:sepot/l10n/generated/app_localizations.dart';
import 'package:sepot/models/call_log.dart';

/// Ikona a text záznamu hovoru — sdílí chat i seznam chatů, ať se
/// formulace nerozejdou.
({IconData icon, String text, bool alert}) callLogLabel(
    AppLocalizations l10n, CallLog log) {
  final icon = log.video ? Icons.videocam_rounded : Icons.call_rounded;
  return switch (log.outcome) {
    CallOutcome.completed => (
        icon: icon,
        text: log.video
            ? l10n.callLogVideo(formatCallDuration(log.durationSeconds))
            : l10n.callLogVoice(formatCallDuration(log.durationSeconds)),
        alert: false,
      ),
    CallOutcome.missed => (
        icon: Icons.phone_missed_rounded,
        text: l10n.callLogMissed,
        alert: true,
      ),
    CallOutcome.unanswered => (
        icon: icon,
        text: l10n.callLogUnanswered,
        alert: false,
      ),
    CallOutcome.rejected => (
        icon: Icons.call_end_rounded,
        text: l10n.callLogRejected,
        alert: false,
      ),
    CallOutcome.busy => (icon: icon, text: l10n.callLogBusy, alert: false),
    CallOutcome.failed => (
        icon: Icons.error_outline_rounded,
        text: l10n.callLogFailed,
        alert: true,
      ),
  };
}
