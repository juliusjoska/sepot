import 'package:flutter/material.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/models/poll.dart';

/// Vytvoření ankety: otázka, 2–12 možností, jedna nebo víc voleb.
/// Vrací hotovou [Poll], nebo null při zrušení.
Future<Poll?> showCreatePollSheet(BuildContext context) {
  return showModalBottomSheet<Poll>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SepotColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CreatePollSheet(),
  );
}

class _CreatePollSheet extends StatefulWidget {
  const _CreatePollSheet();

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final _question = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  var _multi = false;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _filled => [
        for (final c in _options)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];

  bool get _valid =>
      _question.text.trim().isNotEmpty && _filled.length >= Poll.minOptions;

  void _addOption() {
    if (_options.length >= Poll.maxOptions) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_options.length <= Poll.minOptions) return;
    setState(() => _options.removeAt(i).dispose());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.pollCreateTitle,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  FilledButton(
                    onPressed: _valid
                        ? () => Navigator.of(context).pop(Poll(
                              question: _question.text.trim(),
                              options: _filled,
                              multi: _multi,
                            ))
                        : null,
                    child: Text(l10n.chatSend),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _question,
                autofocus: true,
                maxLength: Poll.maxQuestionLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.pollQuestion,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _options[i],
                    maxLength: Poll.maxOptionLength,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.pollOptionHint(i + 1),
                      counterText: '',
                      suffixIcon: _options.length > Poll.minOptions
                          ? IconButton(
                              tooltip: l10n.pollRemoveOption,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => _removeOption(i),
                            )
                          : null,
                    ),
                  ),
                ),
              if (_options.length < Poll.maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.pollAddOption),
                  ),
                ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _multi,
                onChanged: (v) => setState(() => _multi = v),
                activeTrackColor: SepotColors.ember,
                title: Text(l10n.pollAllowMultiple),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
