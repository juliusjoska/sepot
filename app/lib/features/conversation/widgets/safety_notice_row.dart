/// Bezpečnostní upozornění uprostřed konverzace. Vypadá jinak než bublina
/// (nikdo ho neposlal), aby nešlo zaměnit se zprávou protistrany.
library;

import 'package:flutter/material.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/message.dart';

class SafetyNoticeRow extends StatelessWidget {
  const SafetyNoticeRow({
    super.key,
    required this.notice,
    required this.contactName,
    this.claimedName,
    this.onVerify,
  });

  final MessageNotice notice;
  final String contactName;

  /// Jméno, které si zvolil neznámý odesílatel ([MessageNotice.lookalikeRequest]).
  final String? claimedName;

  /// Odkaz na porovnání bezpečnostního kódu (null = bez tlačítka).
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = switch (notice) {
      MessageNotice.identityChanged => l10n.noticeIdentityChanged(contactName),
      MessageNotice.lookalikeRequest =>
        l10n.noticeLookalikeRequest(claimedName ?? '', contactName),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        decoration: BoxDecoration(
          color: SepotColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SepotColors.warning),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gpp_maybe_rounded,
                    size: 18, color: SepotColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                        fontSize: 13, color: SepotColors.textPrimary),
                  ),
                ),
              ],
            ),
            if (onVerify != null &&
                notice == MessageNotice.identityChanged)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onVerify,
                  child: Text(l10n.noticeVerifyAction),
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
