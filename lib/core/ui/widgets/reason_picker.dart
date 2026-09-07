import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/reason_code.dart';
import '../../l10n/app_strings.dart';
import '../theme.dart';
import '../tokens.dart';
import 'pos_widgets.dart';

/// One configured reason list, in the shape every act shares.
///
/// Void, refund, pay-out, price override, force-close and inventory adjustment
/// all ask the same question, and asking it six slightly different ways is how
/// a restaurant ends up unable to report across them. The list itself lives in
/// `pos_reason_codes` and is the restaurant's own — this only renders it.
///
/// Embedded rather than shown as a sheet when it sits inside a bigger dialog:
/// the manager-approval dialog (patterns 5.1) puts this in its right-hand
/// column at [compact] density. [ReasonSheet] is the standalone case.
class ReasonPicker extends StatelessWidget {
  const ReasonPicker({
    super.key,
    required this.reasons,
    required this.requirement,
    required this.onChanged,
    this.selected,
    this.note,
    this.compact = false,
    this.autofocus = true,
  });

  /// In picker order. Position decides the number key, so this is the order the
  /// restaurant chose in `sort_order`, never a re-sort by name.
  final List<ReasonCode> reasons;

  final ReasonRequirement requirement;
  final ReasonCode? selected;
  final String? note;

  /// Fires on every pick and every keystroke in the note, so the caller can
  /// decide whether its confirm button is armed. See [isSatisfied].
  final void Function(ReasonCode? reason, String note) onChanged;

  /// Denser rows, for the right-hand column of a larger dialog.
  final bool compact;

  /// Whether the number keys are live on open. False when this sits inside a
  /// dialog whose PIN pad should have them instead.
  final bool autofocus;

  /// The key that selects the row at [index]: `1`–`9`, then `0`.
  ///
  /// Ten is where a hand runs out of a keypad row, and *Other* is the tenth by
  /// convention — so it lands on `0`, which is where a thumb already is.
  static String keyFor(int index) => index < 9 ? '${index + 1}' : '0';

  /// Whether a caller may proceed on this state.
  ///
  /// Three rules, and the third is the one that is easy to miss: a reason that
  /// declares `requiresNote` — *Other* — carries no information without one, so
  /// picking it and typing nothing is the same as not answering.
  static bool isSatisfied({
    required ReasonRequirement requirement,
    required ReasonCode? reason,
    required String note,
  }) {
    if (requirement == ReasonRequirement.disabled) return true;
    if (requirement == ReasonRequirement.required && reason == null) {
      return false;
    }
    if (reason?.requiresNote ?? false) return note.trim().isNotEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Switched off for this act. Rendering an empty list would tell the person
    // their restaurant has no reasons configured, which is a different and
    // untrue thing.
    if (requirement == ReasonRequirement.disabled) {
      return const SizedBox.shrink();
    }

    final strings = context.strings;
    final palette = context.pos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Rows(
          reasons: reasons,
          selected: selected,
          compact: compact,
          autofocus: autofocus,
          onPick: (reason) => onChanged(reason, note ?? ''),
        ),
        const SizedBox(height: PosSpace.s14),
        MicroLabel(strings.reasonNote),
        const SizedBox(height: PosSpace.sm),
        _NoteField(
          value: note ?? '',
          hint: strings.reasonNoteHint,
          compact: compact,
          onChanged: (text) => onChanged(selected, text),
        ),
        const SizedBox(height: PosSpace.s10),
        Text(
          _help(strings),
          style: PosText.ui(
            size: 12.5,
            color: _helpIsAWarning ? palette.warn : palette.muted,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  /// True when the help line is telling the person what is stopping them,
  /// rather than describing how the list behaves.
  bool get _helpIsAWarning => selected?.requiresNote ?? false;

  String _help(AppStrings strings) {
    if (_helpIsAWarning) return strings.reasonNeedsNoteHelp;
    return requirement == ReasonRequirement.required
        ? strings.reasonRequiredHelp
        : strings.reasonOptionalHelp;
  }
}

/// The rows, and the number keys that pick them.
class _Rows extends StatelessWidget {
  const _Rows({
    required this.reasons,
    required this.selected,
    required this.compact,
    required this.autofocus,
    required this.onPick,
  });

  final List<ReasonCode> reasons;
  final ReasonCode? selected;
  final bool compact;
  final bool autofocus;
  final ValueChanged<ReasonCode> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;

    return FocusableActionDetector(
      autofocus: autofocus,
      // Bound at the list, not on each row: a row would only see the key while
      // it held focus, and the whole point is that `4` picks the fourth reason
      // from wherever the person is.
      shortcuts: {
        for (var i = 0; i < reasons.length && i < 10; i++)
          _digitFor(ReasonPicker.keyFor(i)): _PickIntent(i),
      },
      actions: {
        _PickIntent: CallbackAction<_PickIntent>(
          onInvoke: (intent) {
            onPick(reasons[intent.index]);
            return null;
          },
        ),
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(palette.resting),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < reasons.length; i++)
              _Row(
                reason: reasons[i],
                keyLabel: i < 10 ? ReasonPicker.keyFor(i) : null,
                isSelected: reasons[i].id == selected?.id,
                isLast: i == reasons.length - 1,
                compact: compact,
                onTap: () => onPick(reasons[i]),
              ),
          ],
        ),
      ),
    );
  }

  static SingleActivator _digitFor(String digit) => SingleActivator(
    switch (digit) {
      '0' => LogicalKeyboardKey.digit0,
      '1' => LogicalKeyboardKey.digit1,
      '2' => LogicalKeyboardKey.digit2,
      '3' => LogicalKeyboardKey.digit3,
      '4' => LogicalKeyboardKey.digit4,
      '5' => LogicalKeyboardKey.digit5,
      '6' => LogicalKeyboardKey.digit6,
      '7' => LogicalKeyboardKey.digit7,
      '8' => LogicalKeyboardKey.digit8,
      _ => LogicalKeyboardKey.digit9,
    },
  );
}

class _PickIntent extends Intent {
  const _PickIntent(this.index);

  final int index;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.reason,
    required this.keyLabel,
    required this.isSelected,
    required this.isLast,
    required this.compact,
    required this.onTap,
  });

  final ReasonCode reason;
  final String? keyLabel;
  final bool isSelected;
  final bool isLast;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final strings = context.strings;

    return Material(
      color: isSelected ? palette.accentSoft : palette.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            // Never below the touch target, however compact the density gets.
            // This is a control somebody hits with a thumb during a rush.
            minHeight: compact
                ? PosSize.minTouchTarget
                : PosSize.minTouchTarget + PosSpace.sm,
          ),
          padding: EdgeInsetsDirectional.fromSTEB(
            PosSpace.lg,
            compact ? PosSpace.s10 : 11,
            PosSpace.lg,
            compact ? PosSpace.s10 : 11,
          ),
          decoration: BoxDecoration(
            // Directional, not `Border`: the selection mark has to sit on the
            // leading edge, which is the left in English and the right in
            // Arabic. A hard-coded `left` would put it on the wrong side of
            // every Arabic till.
            border: BorderDirectional(
              bottom: isLast
                  ? BorderSide.none
                  : BorderSide(color: palette.line),
              // 2px accent — the same mark a selected category rail item
              // carries, so "this one" reads the same everywhere.
              start: BorderSide(
                color: isSelected ? palette.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              if (keyLabel != null) ...[
                _NumberChip(keyLabel!),
                const SizedBox(width: PosSpace.s10),
              ],
              Expanded(
                child: Text(
                  reason.displayName(strings.languageCode),
                  style: PosText.ui(
                    size: 14,
                    weight: FontWeight.w500,
                    color: palette.inkWarm,
                  ),
                ),
              ),
              // Kept in the layout when unselected rather than removed, so
              // picking a row does not shift the text of every other row.
              Visibility.maintain(
                visible: isSelected,
                child: Text(
                  '✓',
                  style: PosText.ui(
                    size: 14,
                    weight: FontWeight.w800,
                    color: palette.accentPressed,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 22×22 mono square carrying the key that picks this row.
class _NumberChip extends StatelessWidget {
  const _NumberChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.fromBorderSide(context.pos.resting),
    ),
    // A digit, so it is LTR in both locales for the same reason every other
    // number in this product is.
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        label,
        style: PosText.mono(size: 11.5, color: context.pos.muted),
      ),
    ),
  );
}

class _NoteField extends StatefulWidget {
  const _NoteField({
    required this.value,
    required this.hint,
    required this.compact,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final bool compact;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;

    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      maxLines: 2,
      minLines: 2,
      // Reached by Tab, never focused on open. The number keys have to stay
      // live for the list — a note field holding focus would swallow `4` into
      // the text instead of picking the fourth reason.
      autofocus: false,
      style: PosText.ui(size: 13.5, color: palette.inkWarm),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: PosText.ui(size: 13.5, color: palette.muted),
        filled: true,
        fillColor: palette.page,
        contentPadding: const EdgeInsets.all(PosSpace.md),
      ),
    );
  }
}

/// The standalone sheet: a reason asked as its own question.
///
/// [show] is the whole API. It handles the case that trips callers up — a
/// restaurant that switched reasons off for this act — by returning an empty
/// selection **without rendering anything**, so the caller's code path is the
/// same either way and no dialog flashes on screen.
class ReasonSheet extends StatefulWidget {
  const ReasonSheet({
    super.key,
    required this.reasons,
    required this.requirement,
    required this.title,
    required this.confirmLabel,
  });

  final List<ReasonCode> reasons;
  final ReasonRequirement requirement;

  /// The act, in the words the person would use — *"Void this item"*. Never a
  /// permission key and never the scope's wire name.
  final String title;

  /// What the confirm button says. It names the act too, because a button
  /// reading *Confirm* tells somebody nothing about what they are confirming.
  final String confirmLabel;

  /// Returns null when the person cancelled.
  static Future<ReasonSelection?> show(
    BuildContext context, {
    required List<ReasonCode> reasons,
    required ReasonRequirement requirement,
    required String title,
    required String confirmLabel,
  }) {
    if (requirement == ReasonRequirement.disabled) {
      return Future.value(const ReasonSelection());
    }
    return showDialog<ReasonSelection>(
      context: context,
      barrierColor: context.pos.scrim,
      builder: (_) => ReasonSheet(
        reasons: reasons,
        requirement: requirement,
        title: title,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<ReasonSheet> {
  ReasonCode? _selected;
  String _note = '';

  bool get _canConfirm => ReasonPicker.isSatisfied(
    requirement: widget.requirement,
    reason: _selected,
    note: _note,
  );

  void _confirm() {
    if (!_canConfirm) return;
    Navigator.of(context).pop(
      ReasonSelection(
        reason: _selected,
        note: _note.trim().isEmpty ? null : _note.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    // Below the medium breakpoint the sheet stops being a centred card and
    // takes the width it is given — a handheld has no room for a 520 island.
    final isNarrow =
        MediaQuery.sizeOf(context).width < PosSize.mediumShellMin;

    return Dialog(
      backgroundColor: palette.surface,
      insetPadding: const EdgeInsets.all(PosSpace.s28),
      shape: Border.fromBorderSide(palette.emphasis.copyWith(
        color: palette.lineStrong,
      )),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _confirm,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isNarrow ? double.infinity : PosSize.dialogReason,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(strings, palette),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PosSpace.s18),
                  child: ReasonPicker(
                    reasons: widget.reasons,
                    requirement: widget.requirement,
                    selected: _selected,
                    note: _note,
                    onChanged: (reason, note) => setState(() {
                      _selected = reason;
                      _note = note;
                    }),
                  ),
                ),
              ),
              _footer(strings, palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppStrings strings, PosPalette palette) => Container(
    padding: const EdgeInsets.symmetric(
      vertical: PosSpace.s14,
      horizontal: PosSpace.s18,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: palette.lineStrong)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            widget.title,
            style: PosText.panelTitle(color: palette.inkWarm),
          ),
        ),
        const SizedBox(width: PosSpace.md),
        // The configuration, stated. Somebody who cannot proceed should be able
        // to see why without pressing the button to find out.
        MicroLabel(
          widget.requirement == ReasonRequirement.required
              ? strings.reasonRequiredBadge
              : strings.reasonOptionalBadge,
          color: widget.requirement == ReasonRequirement.required
              ? palette.warn
              : palette.muted,
        ),
      ],
    ),
  );

  Widget _footer(AppStrings strings, PosPalette palette) => Container(
    padding: const EdgeInsets.symmetric(
      vertical: PosSpace.s14,
      horizontal: PosSpace.s18,
    ),
    decoration: BoxDecoration(
      color: palette.page,
      border: Border(top: BorderSide(color: palette.lineStrong)),
    ),
    child: Row(
      children: [
        PosButton(
          label: strings.cancel,
          onPressed: () => Navigator.of(context).pop(),
          height: PosSize.secondaryAction,
          border: Border.fromBorderSide(palette.resting),
        ),
        const SizedBox(width: PosSpace.md),
        Expanded(
          child: PosButton(
            label: widget.confirmLabel,
            // Muted, never hidden: the person has to be able to see that
            // confirming exists and that a reason is what unlocks it.
            onPressed: _canConfirm ? _confirm : null,
            height: PosSize.primaryCta,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            background: _canConfirm ? palette.accent : palette.page,
            foreground: _canConfirm ? palette.ink : palette.muted,
            border: Border.fromBorderSide(
              _canConfirm
                  ? BorderSide(color: palette.accentPressed)
                  : palette.resting,
            ),
          ),
        ),
      ],
    ),
  );
}
