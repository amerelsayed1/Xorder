import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../money/money.dart';
import '../../../domain/models/reason_code.dart';
import '../theme.dart';
import '../tokens.dart';
import 'mono_amount.dart';
import 'pos_widgets.dart';
import 'reason_picker.dart';

/// An act that cannot be taken back: void, refund, restore, force-close.
///
/// Two jobs, and the second is the one that gets skipped. The first is to say
/// what will happen. The second is to make sure it **cannot be fired by
/// reflex** — a cashier clearing dialogs at speed during a rush must not be
/// able to void an order by pressing Enter twice.
///
/// So the safe button holds focus on open, Enter is deliberately inert, and the
/// destructive button is reachable only by pointer or by a Tab somebody chose
/// to press. None of that is styling; all of it is asserted in the tests,
/// because it is exactly the kind of behaviour a later refactor removes without
/// noticing.
class DestructiveConfirmDialog extends StatefulWidget {
  const DestructiveConfirmDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.keepLabel,
    this.amount,
    this.consequences = const [],
    this.reasons = const [],
    this.requirement = ReasonRequirement.required,
  });

  /// The act as a question, naming its subject — *"Void order INV-2481?"*.
  final String title;

  /// What the destructive button says. **It states the amount** where there is
  /// one, because a button reading *Confirm* tells nobody what they are about
  /// to lose. [show] composes it for you.
  final String confirmLabel;

  /// The way out, named after the thing being kept — *"Keep order"*, not
  /// *"Cancel"*. Cancel is ambiguous in a dialog about cancelling something.
  final String keepLabel;

  /// The money at stake. Null for acts that have none — a force-close, a
  /// restore.
  final Money? amount;

  /// At most three, in this order: what happens · what it does to work already
  /// done · what cannot be undone.
  ///
  /// Three is a limit, not a target. A person reading a fourth line has stopped
  /// reading, and the last line is the one that matters most.
  final List<String> consequences;

  final List<ReasonCode> reasons;
  final ReasonRequirement requirement;

  /// Returns the reason the person gave, or **null when they kept it**.
  ///
  /// Same contract as [ReasonSheet.show]: null is *no act*, and a non-null
  /// selection with a null reason is *the act, on a list the restaurant
  /// switched off*. A boolean plus an out-parameter would let a caller commit
  /// the act and forget the reason.
  static Future<ReasonSelection?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String keepLabel,
    Money? amount,
    List<String> consequences = const [],
    List<ReasonCode> reasons = const [],
    ReasonRequirement requirement = ReasonRequirement.required,
  }) => showDialog<ReasonSelection>(
    context: context,
    // Heavier than the ordinary scrim. What is behind this dialog is not
    // something anybody should be reading right now.
    barrierColor: context.pos.scrimHeavy,
    // A dialog about an irreversible act must not be dismissible by a stray
    // click outside it — not because dismissing is dangerous here (it keeps the
    // order), but because a person who did not notice the dialog also did not
    // read it, and the next thing they press is the one that matters.
    barrierDismissible: false,
    builder: (_) => DestructiveConfirmDialog(
      title: title,
      confirmLabel: confirmLabel,
      keepLabel: keepLabel,
      amount: amount,
      consequences: consequences,
      reasons: reasons,
      requirement: requirement,
    ),
  );

  @override
  State<DestructiveConfirmDialog> createState() =>
      _DestructiveConfirmDialogState();
}

class _DestructiveConfirmDialogState extends State<DestructiveConfirmDialog> {
  ReasonCode? _reason;
  String _note = '';

  /// Whether the destructive button may be pressed at all.
  ///
  /// "Armed" rather than "enabled" on purpose: this dialog starts *disarmed*
  /// whenever a reason is required, and arming it is a thing the person does.
  bool get _isArmed => ReasonPicker.isSatisfied(
    requirement: widget.requirement,
    reason: _reason,
    note: _note,
  );

  void _keep() => Navigator.of(context).pop();

  void _confirm() {
    if (!_isArmed) return;
    Navigator.of(context).pop(
      ReasonSelection(
        reason: _reason,
        note: _note.trim().isEmpty ? null : _note.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final isNarrow =
        MediaQuery.sizeOf(context).width < PosSize.wideShellMin;

    return Dialog(
      backgroundColor: palette.surface,
      insetPadding: const EdgeInsets.all(PosSpace.s28),
      // 2px danger. The border is the only elevation this design has, and this
      // is the one dialog that should be unmistakable from across a counter.
      shape: Border.all(color: palette.danger, width: 2),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _keep,
          // **Enter is bound to nothing, deliberately.** Not left unbound —
          // bound, so that it is consumed here and never reaches whichever
          // control holds focus. Enter is the reflex key: it is what a hand
          // presses to make a dialog go away, and no reflex may commit an
          // irreversible act. Space still activates the focused control, for
          // somebody who has deliberately tabbed to it.
          const SingleActivator(LogicalKeyboardKey.enter): _doNothing,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): _doNothing,
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: PosSize.dialogDestructive,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(strings, palette),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PosSpace.s18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.amount != null) ...[
                        _amountCell(strings, palette),
                        const SizedBox(height: PosSpace.lg),
                      ],
                      if (widget.consequences.isNotEmpty) ...[
                        _consequences(palette),
                        const SizedBox(height: PosSpace.lg),
                      ],
                      if (widget.requirement != ReasonRequirement.disabled)
                        ReasonPicker(
                          reasons: widget.reasons,
                          requirement: widget.requirement,
                          selected: _reason,
                          note: _note,
                          compact: true,
                          // The list must not steal the number keys from a
                          // person who has not looked at it yet — and, more
                          // importantly, must not take focus off the keep
                          // button, which is what holds it on open.
                          autofocus: false,
                          onChanged: (reason, note) => setState(() {
                            _reason = reason;
                            _note = note;
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              _footer(strings, palette, isNarrow: isNarrow),
            ],
          ),
        ),
      ),
    );
  }

  /// A named no-op, so the binding reads as a decision rather than a stub.
  static void _doNothing() {}

  Widget _header(AppStrings strings, PosPalette palette) => Container(
    padding: const EdgeInsets.symmetric(
      vertical: PosSpace.s14,
      horizontal: PosSpace.s18,
    ),
    decoration: BoxDecoration(
      color: palette.dangerSoft,
      border: Border(bottom: BorderSide(color: palette.danger)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MicroLabel(strings.cannotBeUndone, color: palette.danger),
        const SizedBox(height: PosSpace.sm),
        Text(
          widget.title,
          style: PosText.ui(
            size: 20,
            weight: FontWeight.w800,
            color: palette.inkWarm,
          ),
        ),
      ],
    ),
  );

  /// The money, as the loudest thing on screen.
  ///
  /// A person deciding whether to void something is deciding about an amount,
  /// and the amount should not be a detail they have to hunt for in a sentence.
  Widget _amountCell(AppStrings strings, PosPalette palette) => Container(
    padding: const EdgeInsets.symmetric(
      vertical: PosSpace.s14,
      horizontal: PosSpace.lg,
    ),
    decoration: BoxDecoration(
      color: palette.page,
      border: Border.fromBorderSide(palette.resting),
    ),
    child: Row(
      children: [
        MicroLabel(strings.amountMicroLabel),
        const Spacer(),
        MonoAmount(
          widget.amount!,
          size: 32,
          weight: FontWeight.w600,
          color: palette.inkWarm,
        ),
      ],
    ),
  );

  Widget _consequences(PosPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final line in widget.consequences.take(3))
        Padding(
          padding: const EdgeInsets.only(bottom: PosSpace.s10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A square, not an icon. Nothing in this product depends on an
              // icon set, and a bullet that is a border is a bullet that
              // cannot go missing.
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: 7,
                  end: PosSpace.s10,
                ),
                child: Container(width: 6, height: 6, color: palette.body),
              ),
              Expanded(
                child: Text(
                  line,
                  style: PosText.ui(
                    size: 14,
                    color: palette.body,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _footer(
    AppStrings strings,
    PosPalette palette, {
    required bool isNarrow,
  }) {
    // Both are 76. This is not a primary action beside a cancel link — it is a
    // genuine two-sided choice, and giving the safe side less weight is how a
    // dialog nudges somebody toward the irreversible one.
    final keep = PosButton(
      label: widget.keepLabel,
      onPressed: _keep,
      height: PosSize.primaryCta,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      background: palette.surface,
      foreground: palette.ink,
      border: Border.fromBorderSide(palette.emphasis),
      // Holds focus on open. The safe choice is the one already under the
      // person's hands.
      autofocus: true,
    );

    final confirm = PosButton(
      label: widget.confirmLabel,
      onPressed: _isArmed ? _confirm : null,
      height: PosSize.primaryCta,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      // Disarmed: it goes quiet and the accent belongs to the reason list,
      // which is what the person has to deal with first. Muted, never hidden —
      // they must be able to see that confirming exists.
      background: _isArmed ? palette.danger : palette.page,
      foreground: _isArmed ? Colors.white : palette.muted,
      border: Border.fromBorderSide(
        _isArmed ? BorderSide(color: palette.dangerPressed) : palette.resting,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: PosSpace.s14,
        horizontal: PosSpace.s18,
      ),
      decoration: BoxDecoration(
        color: palette.page,
        border: Border(top: BorderSide(color: palette.lineStrong)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNarrow)
            // Stacked, with the safe choice on top — the thumb's first stop.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                keep,
                const SizedBox(height: PosSpace.md),
                confirm,
              ],
            )
          else
            Row(
              children: [
                Expanded(child: keep),
                const SizedBox(width: PosSpace.md),
                Expanded(child: confirm),
              ],
            ),
          const SizedBox(height: PosSpace.s10),
          Text(
            strings.destructiveKeyHint,
            textAlign: TextAlign.center,
            style: PosText.mono(size: 11.5, color: palette.muted),
          ),
        ],
      ),
    );
  }
}
