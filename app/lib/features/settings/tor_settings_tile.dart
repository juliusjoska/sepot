import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/network/relay_client.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/settings_provider.dart';

/// Přepínač routování přes Tor (SOCKS5/Orbot na `.onion`).
///
/// Zapnutí skryje IP klienta před relayem — provoz jde přes lokální
/// Orbot. Bez běžícího Orbotu se spojení nenaváže (indikátor zůstane
/// „připojuji"), na což uživatele upozorníme předem. Přepnutí přestaví
/// spojení za běhu, restart appky netřeba.
class TorSettingsTile extends ConsumerStatefulWidget {
  const TorSettingsTile({super.key});

  @override
  ConsumerState<TorSettingsTile> createState() => _TorSettingsTileState();
}

class _TorSettingsTileState extends ConsumerState<TorSettingsTile> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    if (value && !await _confirmOrbot()) return;
    setState(() => _busy = true);
    try {
      await ref.read(torProvider.notifier).set(value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.torToggleFailed(describeError(context.l10n, e)),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tor přes Orbot potřebuje běžící Orbot s aktivním SOCKS proxy.
  Future<bool> _confirmOrbot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.torConnectionTitle),
        content: Text(ctx.l10n.torDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.commonTurnOn),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(torProvider).valueOrNull ?? false;

    // Stav připojení má smysl ukazovat jen když je Tor zapnutý — pomůže
    // odhalit chybějící/vypnutý Orbot (uvázne na „připojuji").
    String subtitle;
    if (!enabled) {
      subtitle = context.l10n.torSubtitleOff;
    } else {
      final conn = ref.watch(relayConnectionProvider).valueOrNull;
      subtitle = switch (conn) {
        RelayConnectionState.connected => context.l10n.torStatusConnected,
        RelayConnectionState.connecting => context.l10n.torStatusConnecting,
        _ => context.l10n.torStatusWaiting,
      };
    }

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: SepotColors.surfaceVariant,
        ),
        child: Icon(
          enabled ? Icons.vpn_lock : Icons.public,
          size: 20,
          color: enabled ? SepotColors.ember : SepotColors.textSecondary,
        ),
      ),
      title: Text(
        context.l10n.torConnectionTitle,
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: SepotColors.textMuted),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SepotColors.ember,
              ),
            )
          : Switch(
              value: enabled,
              onChanged: _toggle,
              activeTrackColor: SepotColors.ember,
            ),
    );
  }
}
