import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/ticket.dart';

/// What the kitchen is being told about one line.
///
/// Small on purpose. A note is an instruction — "no onions", "well done" — and
/// the whole interaction is one field and two buttons. Anything more elaborate
/// would put ceremony between a cashier and eight words they need to type while
/// somebody is talking to them.
class LineNoteDialog extends StatefulWidget {
  const LineNoteDialog({super.key, required this.line});

  final TicketLine line;

  /// Returns the note as typed, or null if nothing changed.
  ///
  /// An **empty string** is a real answer — it clears the note — so a caller
  /// must not treat it as "cancelled".
  static Future<String?> show(
    BuildContext context, {
    required TicketLine line,
    required AppStrings strings,
  }) => showDialog<String>(
    context: context,
    builder: (_) => LineNoteDialog(line: line),
  );

  @override
  State<LineNoteDialog> createState() => _LineNoteDialogState();
}

class _LineNoteDialogState extends State<LineNoteDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.line.note ?? '',
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_note.text.trim());

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogReason),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Padding(
            padding: const EdgeInsets.all(PosSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.lineNoteTitle(
                    widget.line.product.displayName(strings.languageCode),
                  ),
                  style: PosText.ui(
                    size: 18,
                    weight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: PosSpace.md),
                TextField(
                  controller: _note,
                  autofocus: true,
                  maxLines: 2,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  // Enter saves. This dialog has one field and nothing
                  // destructive on it, so the key that means "done" everywhere
                  // else means it here too.
                  onSubmitted: (_) => _save(),
                  style: PosText.ui(size: 14, color: palette.ink),
                  decoration: InputDecoration(
                    hintText: strings.lineNoteHint,
                    hintStyle: PosText.ui(size: 14, color: palette.muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: palette.resting,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: palette.resting,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: palette.accentBorder,
                    ),
                  ),
                ),
                const SizedBox(height: PosSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: PosButton(
                        label: strings.cancel,
                        border: Border.fromBorderSide(palette.resting),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: PosSpace.sm),
                    Expanded(
                      flex: 2,
                      child: PosButton(
                        label: strings.save,
                        background: palette.accent,
                        foreground: Colors.white,
                        fontWeight: FontWeight.w700,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
