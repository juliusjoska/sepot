import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/providers/push_provider.dart';

/// Nastavení push notifikací — degooglovaný UnifiedPush.
/// Zapnutí = výběr distributora (ntfy) + registrace endpointu u relaye.
/// Budíček nenese obsah ani odesílatele; při probuzení se appka připojí
/// a vyzvedne frontu.
class PushSettingsTile extends ConsumerStatefulWidget {
  const PushSettingsTile({super.key});

  @override
  ConsumerState<PushSettingsTile> createState() => _PushSettingsTileState();
}

class _PushSettingsTileState extends ConsumerState<PushSettingsTile> {
  String _mode = 'off';
  String? _distributor;
  bool _busy = false;
  bool _registrationFailed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final push = ref.read(pushServiceProvider);
    final mode = await push.currentMode();
    final d = await push.currentDistributor();
    final failed = await push.registrationFailed();
    if (mounted) {
      setState(() {
        _mode = mode;
        _distributor = d;
        _registrationFailed = failed;
      });
    }
  }

  Future<void> _chooseMode() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.pushTitle),
        children: [
          _modeOption(ctx, 'off', ctx.l10n.commonOff, ctx.l10n.pushModeOffDesc),
          _modeOption(ctx, 'up', ctx.l10n.pushModeUp, ctx.l10n.pushModeUpDesc),
          _modeOption(
              ctx, 'fcm', ctx.l10n.pushModeFcm, ctx.l10n.pushModeFcmDesc),
        ],
      ),
    );
    if (picked == null || picked == _mode) return;

    final push = ref.read(pushServiceProvider);
    setState(() => _busy = true);
    try {
      switch (picked) {
        case 'off':
          await push.setModeOff();
        case 'up':
          final ok = await push.setModeUnifiedPush();
          if (!ok && mounted) await _pickDistributor();
        case 'fcm':
          await push.setModeFcm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .pushSetupFailed(describeError(context.l10n, e)))),
        );
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _modeOption(
      BuildContext ctx, String value, String title, String subtitle) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              value == _mode
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: value == _mode
                  ? SepotColors.ember
                  : SepotColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: SepotColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDistributor() async {
    final push = ref.read(pushServiceProvider);
    final list = await push.distributors();
    if (!mounted) return;

    if (list.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.pushNoDistributorTitle),
          content: Text(ctx.l10n.pushNoDistributorBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.commonOk),
            ),
          ],
        ),
      );
      return;
    }

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.pushPickDistributorTitle),
        children: [
          for (final d in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(d),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await push.useDistributor(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Selhaná registrace přebíjí popis režimu — „zapnuto" bez budíčků je
    // horší než vypnuto, protože uživatel čeká zprávy, které nepřijdou.
    final failed = _registrationFailed && _mode != 'off';
    final subtitle = failed
        ? context.l10n.pushRegistrationFailed
        : switch (_mode) {
            'up' => context.l10n.pushSubtitleUnifiedPush(
                _distributor ?? context.l10n.pushNoDistributorFallback),
            'fcm' => context.l10n.pushSubtitleFcm,
            _ => context.l10n.commonOff,
          };
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: SepotColors.surfaceVariant,
        ),
        child: const Icon(
          Icons.notifications_outlined,
          size: 20,
          color: SepotColors.textSecondary,
        ),
      ),
      title: Text(context.l10n.pushTitle,
          style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: failed ? SepotColors.ember : SepotColors.textMuted,
        ),
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
          : const Icon(Icons.chevron_right, color: SepotColors.textMuted),
      onTap: _busy ? null : _chooseMode,
    );
  }
}
