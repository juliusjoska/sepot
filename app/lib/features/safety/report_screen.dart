/// Nahlášení zneužití (Play UGC + CSAE, Apple Guideline 1.2).
///
/// Do verze 0.2.0 „nahlášení" jen zablokovalo kontakt a nikam nedošlo —
/// obchody ale vyžadují cestu, kterou se o problému dozví provozovatel.
/// Tahle obrazovka je ta cesta.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/errors.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/safety/report_service.dart';
import 'package:sepot/core/theme/app_theme.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    this.reportedFingerprint,
    this.reportedName,
  });

  /// Otisk nahlášeného kontaktu (SEP-…), když se sem přišlo z konverzace.
  final String? reportedFingerprint;
  final String? reportedName;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _popis = TextEditingController();
  final _kontakt = TextEditingController();

  ReportCategory _kategorie = ReportCategory.harassment;
  bool _prilozitOtisk = true;
  bool _odesila = false;
  bool _hotovo = false;

  @override
  void dispose() {
    _popis.dispose();
    _kontakt.dispose();
    super.dispose();
  }

  bool get _maKontakt =>
      widget.reportedFingerprint != null &&
      widget.reportedFingerprint!.isNotEmpty;

  Future<void> _odeslat() async {
    setState(() => _odesila = true);
    try {
      await const ReportService().submit(
        category: _kategorie,
        description: _popis.text,
        reportedFingerprint:
            _maKontakt && _prilozitOtisk ? widget.reportedFingerprint : null,
        replyTo: _kontakt.text,
      );
      if (mounted) setState(() => _hotovo = true);
    } on SepotUserError catch (e) {
      if (!mounted) return;
      setState(() => _odesila = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeError(context.l10n, e)),
          backgroundColor: SepotColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.reportTitle)),
      body: _hotovo ? _uspech() : _formular(),
    );
  }

  Widget _uspech() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 56, color: SepotColors.sage),
            const SizedBox(height: 20),
            Text(
              context.l10n.reportSubmitted,
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: SepotColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _kategorie.isChildSafety
                  ? context.l10n.reportSubmittedChildSafety
                  : context.l10n.reportSubmittedThanks,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 14,
                height: 1.5,
                color: SepotColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => context.pop(),
              child: Text(context.l10n.commonDone),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formular() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _panel(
          icon: Icons.lock_outline,
          barva: SepotColors.mist,
          text: context.l10n.reportPanelE2eNotice,
        ),
        const SizedBox(height: 10),
        if (_kategorie.isChildSafety) ...[
          _panel(
            icon: Icons.gpp_maybe_outlined,
            barva: SepotColors.error,
            text: context.l10n.reportPanelCsamWarning,
          ),
          const SizedBox(height: 10),
        ],
        _panel(
          icon: Icons.public,
          barva: SepotColors.warning,
          text: context.l10n.reportPanelIpNotice,
        ),
        const SizedBox(height: 24),
        _nadpis(context.l10n.reportCategoryHeading),
        ...ReportCategory.values.map(_volba),
        const SizedBox(height: 20),
        _nadpis(context.l10n.reportDescriptionHeading),
        const SizedBox(height: 8),
        TextField(
          controller: _popis,
          maxLines: 6,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            filled: false,
            hintText: _hintKategorie(context.l10n, _kategorie),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_maKontakt) ...[
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _prilozitOtisk,
            activeTrackColor: SepotColors.ember,
            onChanged: (v) => setState(() => _prilozitOtisk = v),
            title: Text(
              widget.reportedName == null
                  ? context.l10n.reportAttachContactId
                  : context.l10n
                      .reportAttachContactIdNamed(widget.reportedName!),
              style: const TextStyle(
                  fontFamily: kFontSans,
                  fontSize: 14,
                  color: SepotColors.textPrimary),
            ),
            subtitle: Text(
              widget.reportedFingerprint!,
              style: const TextStyle(
                  fontFamily: kFontMono,
                  fontSize: 12,
                  color: SepotColors.textMuted),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _nadpis(context.l10n.reportReplyToHeading),
        const SizedBox(height: 8),
        TextField(
          controller: _kontakt,
          keyboardType: TextInputType.emailAddress,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
          decoration: InputDecoration(
            filled: false,
            hintText: context.l10n.reportReplyToHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _odesila ? null : _odeslat,
          child: _odesila
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.reportSubmitButton),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: () => launchUrl(
              Uri.parse(AppConstants.childSafetyUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(context.l10n.settingsChildSafetyTitle),
          ),
        ),
      ],
    );
  }

  String _labelKategorie(AppLocalizations l10n, ReportCategory k) =>
      switch (k) {
        ReportCategory.childSafety => l10n.reportCategoryChildSafety,
        ReportCategory.harassment => l10n.reportCategoryHarassment,
        ReportCategory.spam => l10n.reportCategorySpam,
        ReportCategory.fraud => l10n.reportCategoryFraud,
        ReportCategory.other => l10n.reportCategoryOther,
      };

  String _hintKategorie(AppLocalizations l10n, ReportCategory k) =>
      switch (k) {
        ReportCategory.childSafety => l10n.reportCategoryChildSafetyHint,
        ReportCategory.harassment => l10n.reportCategoryHarassmentHint,
        ReportCategory.spam => l10n.reportCategorySpamHint,
        ReportCategory.fraud => l10n.reportCategoryFraudHint,
        ReportCategory.other => l10n.reportCategoryOtherHint,
      };

  Widget _nadpis(String t) => Text(
        t,
        style: const TextStyle(
          fontFamily: kFontSans,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: SepotColors.textMuted,
        ),
      );

  Widget _volba(ReportCategory k) {
    final vybrano = k == _kategorie;
    return InkWell(
      onTap: () => setState(() => _kategorie = k),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              vybrano ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: vybrano ? SepotColors.ember : SepotColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _labelKategorie(context.l10n, k),
                    style: TextStyle(
                      fontFamily: kFontSans,
                      fontSize: 15,
                      fontWeight: vybrano ? FontWeight.w600 : FontWeight.w400,
                      color: SepotColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _hintKategorie(context.l10n, k),
                    style: const TextStyle(
                      fontFamily: kFontSans,
                      fontSize: 12,
                      height: 1.4,
                      color: SepotColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({
    required IconData icon,
    required Color barva,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SepotColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SepotColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: barva),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: kFontSans,
                fontSize: 13,
                height: 1.5,
                color: SepotColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
