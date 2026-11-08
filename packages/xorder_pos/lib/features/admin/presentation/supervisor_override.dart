import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/reason_picker.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/services/authorization.dart';
import 'admin_messages.dart';
import '../../../core/security/attempt_limiter.dart';
import '../../../core/security/pin_hash.dart';

/// Ask whether the person at the till may do something, offering a supervisor
/// the chance to lend the permission when one is possible.
///
/// This is the single entry point every gated action goes through, so that the
/// three outcomes are handled the same way everywhere:
///
/// * **Allowed** — proceed, and if it was lent, the returned [Allowed] carries
///   the approver so the caller can put them on the audit row.
/// * **Needs override** — a PIN prompt, right here, because the supervisor is
///   standing at the till and walking away to a settings screen is not the
///   workflow anybody has.
/// * **Denied** — an explanation and nothing else. Offering an override for
///   something no override exists for would be a prompt that can only fail.
///
/// [action] is what the supervisor READS — the till's language. [auditAction]
/// is what is WRITTEN to the ledger, and stays in one language so a year of
/// override rows can be read as one list.
///
/// The override itself is recorded before this returns. A lent permission that
/// was used but not logged is worse than one that was refused: the business
/// finds out about the discount and has no way to learn who approved it.
Future<PermissionDecision> requestPermission(
  BuildContext context,
  WidgetRef ref,
  String capability, {
  required String action,
  required String auditAction,
  String? entityType,
  String? entityId,
  String? requestedBy,
  String? subjectLabel,
  String? subject,
  String? limitNote,
  String? approveLabel,
  List<ReasonCode> reasons = const [],
  ReasonRequirement reasonRequirement = ReasonRequirement.disabled,
}) async {
  // The person ACTING, not only the till's: the back office's Sales tab
  // reprints and refunds through here, and there the one asking is whoever
  // came through Admin Mode's door. Everywhere else the two are the same
  // person — see `actingStaffProvider`.
  final decision = Authorization.check(
    ref.read(actingStaffProvider),
    capability,
  );
  if (decision is Allowed) return decision;

  if (decision is Denied) {
    if (context.mounted) {
      await _RefusalDialog.show(context, capability: capability);
    }
    return decision;
  }

  if (!context.mounted) return decision;
  final outcome = await SupervisorOverrideDialog.show(
    context,
    capability: capability,
    action: action,
    requestedBy: requestedBy,
    subjectLabel: subjectLabel,
    subject: subject,
    limitNote: limitNote,
    approveLabel: approveLabel,
    reasons: reasons,
    reasonRequirement: reasonRequirement,
  );
  if (outcome == null) return decision;

  // [entityId] names what the approval is for, so the repository can tell an
  // approval for this order from one for the order before it.
  final approved = Authorization.approve(
    approver: outcome.approver,
    capability: capability,
    reason: outcome.reason,
    subject: entityId,
  );
  if (approved is! Allowed) return approved;

  await recordApproval(
    ref,
    approver: outcome.approver,
    capability: capability,
    auditAction: auditAction,
    entityType: entityType,
    entityId: entityId,
    reason: outcome.reason,
  );

  return approved;
}

/// Put an approval on the ledger: who asked, who said yes, and to what.
///
/// Public because not every approval arrives through [requestPermission]. A
/// discount above the cashier's limit, a refund above the threshold and
/// somebody else's drawer each bring a supervisor over in their own words —
/// and the first and the last of those used to approve with no row at all,
/// which is the one outcome this exists to make impossible.
Future<void> recordApproval(
  WidgetRef ref, {
  required PosStaff approver,
  required String capability,
  required String auditAction,
  String? entityType,
  String? entityId,
  ReasonSelection? reason,
}) => ref
    .read(auditRepositoryProvider)
    .record(
      // The person who asked, not the person who approved. Both are on the
      // row; which is which is the entire point of recording it.
      by: ref.read(actingStaffProvider) ?? approver,
      approvedBy: approver,
      action: AuditAction.permissionOverridden,
      entityType: entityType ?? AuditAction.entityOrder,
      entityId: entityId,
      // [auditAction], not the words the supervisor read: the row is read back
      // months later, often by somebody who does not run the till in the
      // language it was written in.
      reason: reason?.note,
      after: {
        'capability': capability,
        'for': auditAction,
        if (reason?.reasonId != null) 'reason_id': reason!.reasonId,
      },
    );

/// What the approval flow came back with.
class ApprovalOutcome {
  const ApprovalOutcome({required this.approver, this.reason});

  final PosStaff approver;

  /// Null when the business switched reasons off for this act.
  final ReasonSelection? reason;
}

/// The manager-approval dialog (patterns 5.1).
///
/// A cashier attempted something above their permission or above their limit,
/// and a manager authorises it **at the till, without ending the sale**. That
/// last part is the whole workflow: walking a customer's order over to a
/// settings screen is not a thing anybody does during service.
///
/// Two rules shape the copy. The act is stated in **plain words** — "Discount
/// this line by 30%", never `discount.apply` — because a supervisor approving a
/// permission key is approving a string, not an act. And when a limit was
/// exceeded, both numbers are shown: the limit and what was asked for.
class SupervisorOverrideDialog extends ConsumerStatefulWidget {
  const SupervisorOverrideDialog({
    required this.capability,
    required this.action,
    this.requestedBy,
    this.subjectLabel,
    this.subject,
    this.limitNote,
    this.approveLabel,
    this.reasons = const [],
    this.reasonRequirement = ReasonRequirement.disabled,
    super.key,
  });

  final String capability;

  /// What is about to happen, in the words the cashier would use — *"Discount
  /// this line by 30%"*. A supervisor approving "discount.apply" is approving a
  /// string; a supervisor approving "Discount this line" is approving an act.
  final String action;

  /// Who is asking — "Nour Adel · Cashier · Till 2". Composed by the caller,
  /// which is the only place that knows the person, their role and the machine.
  final String? requestedBy;

  /// What the act is being done to, and what to call it: "THE LINE" and
  /// "2 × Grilled Chicken · 268.00". Both or neither.
  final String? subjectLabel;
  final String? subject;

  /// The ceiling that was exceeded, stated with the number that exceeded it —
  /// *"Your manual discount limit is 10%. This discount is 30%."* Composed by
  /// the caller because only it holds both figures.
  final String? limitNote;

  /// What the approve button says. Names the act, for the same reason the
  /// destructive dialog's confirm button does.
  final String? approveLabel;

  final List<ReasonCode> reasons;
  final ReasonRequirement reasonRequirement;

  /// Null when nobody approved.
  static Future<ApprovalOutcome?> show(
    BuildContext context, {
    required String capability,
    required String action,
    String? requestedBy,
    String? subjectLabel,
    String? subject,
    String? limitNote,
    String? approveLabel,
    List<ReasonCode> reasons = const [],
    ReasonRequirement reasonRequirement = ReasonRequirement.disabled,
  }) => showDialog<ApprovalOutcome>(
    context: context,
    barrierColor: context.pos.scrimHeavy,
    barrierDismissible: false,
    builder: (_) => SupervisorOverrideDialog(
      capability: capability,
      action: action,
      requestedBy: requestedBy,
      subjectLabel: subjectLabel,
      subject: subject,
      limitNote: limitNote,
      approveLabel: approveLabel,
      reasons: reasons,
      reasonRequirement: reasonRequirement,
    ),
  );

  @override
  ConsumerState<SupervisorOverrideDialog> createState() =>
      _SupervisorOverrideDialogState();
}

class _SupervisorOverrideDialogState
    extends ConsumerState<SupervisorOverrideDialog> {
  /// Five, then the keypad stops — counted by [signInLimiterProvider], not by
  /// this dialog.
  ///
  /// **It used not to stop.** The dialog kept its own count, and after the
  /// fifth wrong PIN it changed its message and went on checking every PIN it
  /// was given; and since the count lived in the dialog, Cancel and asking
  /// again was five fresh tries. Now the count belongs to the terminal and is
  /// shared with the lock screen, and a shut keypad does not look at the PIN.
  /// Keyed as [AttemptLimiter.anyone]: the pad asks for a PIN alone, so there
  /// is no name to count against.
  static const _limiterKey = AttemptLimiter.anyone;

  String _pin = '';
  bool _busy = false;
  String? _error;

  ReasonCode? _reason;
  String _note = '';

  /// The approval, once it has happened. Non-null switches the dialog to its
  /// confirmation state.
  ApprovalOutcome? _approved;

  bool get _reasonSatisfied => ReasonPicker.isSatisfied(
    requirement: widget.reasonRequirement,
    reason: _reason,
    note: _note,
  );

  bool get _canApprove =>
      _pin.length >= PinRules.length && _reasonSatisfied && !_busy;

  void _digit(String digit) {
    if (_pin.length >= PinRules.length || _busy || _approved != null) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  /// Verify and approve.
  ///
  /// **Not fired by the fourth digit.** The old dialog checked the PIN the
  /// moment four digits were in, which cannot work once a reason is also
  /// required — it would approve before the manager had said why. Approving is
  /// now its own act.
  Future<void> _approve() async {
    if (!_canApprove) {
      if (!_reasonSatisfied) {
        setState(() => _error = context.strings.reasonRequiredHelp);
      }
      return;
    }

    // Shut: answered before the PIN is looked at, so the right PIN typed
    // during the wait approves nothing.
    final limiter = ref.read(signInLimiterProvider);
    if (limiter.lockedFor(_limiterKey) case final wait?) {
      setState(() {
        _pin = '';
        _error = context.strings.signInLockedOut(
          AttemptLimiter.secondsToWait(wait),
        );
      });
      return;
    }

    setState(() => _busy = true);
    final staff = await ref.read(staffDirectoryRepositoryProvider).byPin(_pin);
    if (!mounted) return;

    final decision = Authorization.approve(
      approver: staff,
      capability: widget.capability,
    );
    if (decision is Allowed && decision.approvedBy != null) {
      limiter.succeed(_limiterKey);
      setState(() {
        _busy = false;
        _approved = ApprovalOutcome(
          approver: decision.approvedBy!,
          reason: widget.reasonRequirement == ReasonRequirement.disabled
              ? null
              : ReasonSelection(
                  reason: _reason,
                  note: _note.trim().isEmpty ? null : _note.trim(),
                ),
        );
      });
      return;
    }

    // Deliberately one count and one message for both "no such PIN" and "that
    // person may not approve this". Distinguishing them would turn the keypad
    // into a way of discovering who holds which permission.
    final failure = limiter.fail(_limiterKey);
    final strings = context.strings;
    setState(() {
      _busy = false;
      _pin = '';
      _error = switch (failure) {
        AttemptRefused(:final attemptsLeft) => strings.wrongPinAttemptsLeft(
          attemptsLeft,
        ),
        AttemptLockedOut(:final wait) => strings.signInLockedOut(
          AttemptLimiter.secondsToWait(wait),
        ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final isNarrow = MediaQuery.sizeOf(context).width < PosSize.wideShellMin;

    return Dialog(
      backgroundColor: palette.surface,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: Border.all(color: palette.lineStrong, width: 2),
      child: CallbackShortcuts(
        bindings: {
          // Enter approves **only when the PIN and the reason are both in**.
          // Unlike the destructive dialog, where Enter is inert, a PIN already
          // typed is itself the deliberate act — pressing Enter after it is a
          // manager finishing what they started, not a reflex.
          const SingleActivator(LogicalKeyboardKey.enter): _approved != null
              ? () => Navigator.of(context).pop(_approved)
              : _approve,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
          const SingleActivator(LogicalKeyboardKey.backspace): _backspace,
          for (final digit in const [
            (LogicalKeyboardKey.digit0, '0'),
            (LogicalKeyboardKey.digit1, '1'),
            (LogicalKeyboardKey.digit2, '2'),
            (LogicalKeyboardKey.digit3, '3'),
            (LogicalKeyboardKey.digit4, '4'),
            (LogicalKeyboardKey.digit5, '5'),
            (LogicalKeyboardKey.digit6, '6'),
            (LogicalKeyboardKey.digit7, '7'),
            (LogicalKeyboardKey.digit8, '8'),
            (LogicalKeyboardKey.digit9, '9'),
          ])
            SingleActivator(digit.$1): () => _digit(digit.$2),
        },
        // Something in the subtree has to hold focus or the shortcuts above are
        // never consulted. The reason list deliberately does not take it — the
        // number keys belong to the PIN pad here — so the dialog itself does.
        child: Focus(
          autofocus: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PosSize.dialogApproval),
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
                        _act(strings, palette),
                        if (widget.requestedBy != null ||
                            widget.subject != null) ...[
                          const SizedBox(height: PosSpace.lg),
                          _facts(strings, palette, isNarrow: isNarrow),
                        ],
                        if (widget.limitNote != null) ...[
                          const SizedBox(height: PosSpace.lg),
                          _limitStrip(strings, palette),
                        ],
                        const SizedBox(height: PosSpace.lg),
                        if (_approved != null)
                          _approvedStrip(strings, palette)
                        else
                          _entry(strings, palette, isNarrow: isNarrow),
                        if (_error != null && _approved == null) ...[
                          const SizedBox(height: PosSpace.md),
                          Text(
                            _error!,
                            style: PosText.ui(
                              size: 12.5,
                              weight: FontWeight.w600,
                              color: palette.danger,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _footer(strings, palette),
              ],
            ),
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
      color: palette.warnSoft,
      border: Border(bottom: BorderSide(color: palette.lineStrong)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MicroLabel(strings.approvalRequired, color: palette.warn),
        const SizedBox(height: PosSpace.sm),
        Text(
          strings.supervisorApproval,
          style: PosText.panelTitle(color: palette.inkWarm),
        ),
      ],
    ),
  );

  /// The most important element in the dialog: what is actually being approved.
  Widget _act(AppStrings strings, PosPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      MicroLabel(strings.approvalAction),
      const SizedBox(height: PosSpace.sm),
      Text(
        widget.action,
        style: PosText.ui(
          size: 20,
          weight: FontWeight.w800,
          color: palette.inkWarm,
        ),
      ),
    ],
  );

  Widget _facts(
    AppStrings strings,
    PosPalette palette, {
    required bool isNarrow,
  }) {
    final cells = <Widget>[
      if (widget.requestedBy != null)
        _factCell(palette, strings.approvalRequestedBy, widget.requestedBy!),
      if (widget.subject != null)
        _factCell(
          palette,
          widget.subjectLabel ?? strings.approvalAction,
          widget.subject!,
          mono: true,
        ),
    ];

    if (isNarrow || cells.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(height: 1),
            cells[i],
          ],
        ],
      );
    }

    // IntrinsicHeight so the two cells match, which is what makes them read as
    // one grid rather than two boxes. `CrossAxisAlignment.stretch` alone cannot
    // do it here — the Row sits in a scrollable column, where stretching means
    // stretching to infinity.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cells.first),
          const SizedBox(width: 1),
          Expanded(child: cells.last),
        ],
      ),
    );
  }

  Widget _factCell(
    PosPalette palette,
    String label,
    String value, {
    bool mono = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(
      vertical: PosSpace.md,
      horizontal: PosSpace.s14,
    ),
    decoration: BoxDecoration(
      color: palette.surface,
      border: Border.fromBorderSide(BorderSide(color: palette.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MicroLabel(label),
        const SizedBox(height: PosSpace.xs),
        if (mono)
          MonoCode(value, size: 13, color: palette.inkWarm)
        else
          Text(value, style: PosText.ui(size: 13.5, color: palette.inkWarm)),
      ],
    ),
  );

  /// The limit and the number that exceeded it, both stated.
  ///
  /// A supervisor told only "above the limit" has to ask two questions before
  /// they can decide anything.
  Widget _limitStrip(AppStrings strings, PosPalette palette) => Container(
    padding: const EdgeInsets.all(PosSpace.md),
    decoration: BoxDecoration(
      color: palette.warnSoft,
      border: Border.all(color: palette.warn),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 5, end: PosSpace.s10),
          child: Container(width: 8, height: 8, color: palette.warn),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.approvalAboveLimit,
                style: PosText.ui(
                  size: 13,
                  weight: FontWeight.w800,
                  color: palette.warn,
                ),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                widget.limitNote!,
                style: PosText.ui(
                  size: 13.5,
                  color: palette.body,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _entry(
    AppStrings strings,
    PosPalette palette, {
    required bool isNarrow,
  }) {
    final pin = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MicroLabel(strings.approvalPin),
        const SizedBox(height: PosSpace.sm),
        _PinField(length: _pin.length),
        const SizedBox(height: PosSpace.md),
        PinPad(onDigit: _digit, onBackspace: _backspace),
      ],
    );

    if (widget.reasonRequirement == ReasonRequirement.disabled) {
      // At the pad's own width, not the dialog's. With no reason column
      // beside it the pad was handed all 584px, and since its keys keep their
      // aspect ratio that made four rows of 110px — the 0 key sat below the
      // fold on a 900px screen, half visible, under a footer that scrolled
      // over it. At [PosSize.pinPad] the keys are the design's 62px and the
      // whole dialog fits without scrolling.
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(width: PosSize.pinPad, child: pin),
      );
    }

    final reason = ReasonPicker(
      reasons: widget.reasons,
      requirement: widget.reasonRequirement,
      selected: _reason,
      note: _note,
      compact: true,
      // The PIN pad owns the number keys here. A reason list that also claimed
      // them would swallow a manager's PIN into a reason.
      autofocus: false,
      onChanged: (picked, note) => setState(() {
        _reason = picked;
        _note = note;
        _error = null;
      }),
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          pin,
          const SizedBox(height: PosSpace.s18),
          reason,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 218, child: pin),
        const SizedBox(width: PosSpace.s18),
        Expanded(child: reason),
      ],
    );
  }

  /// Both names, on screen, before anybody walks away.
  Widget _approvedStrip(AppStrings strings, PosPalette palette) {
    final requester =
        widget.requestedBy ?? ref.read(actingStaffProvider)?.name ?? '—';

    return Container(
      padding: const EdgeInsets.all(PosSpace.s14),
      decoration: BoxDecoration(
        color: palette.okSoft,
        border: Border.all(color: palette.ok),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.approvalRequired,
            style: PosText.ui(
              size: 14,
              weight: FontWeight.w800,
              color: palette.ok,
            ),
          ),
          const SizedBox(height: PosSpace.xs),
          Text(
            strings.approvalRecorded(_approved!.approver.name, requester),
            style: PosText.ui(size: 13.5, color: palette.body, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _footer(AppStrings strings, PosPalette palette) {
    final approved = _approved;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: PosSpace.s14,
        horizontal: PosSpace.s18,
      ),
      decoration: BoxDecoration(
        color: palette.page,
        border: Border(top: BorderSide(color: palette.lineStrong)),
      ),
      child: approved != null
          ? PosButton(
              label: strings.approvalDone,
              height: PosSize.primaryCta,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              background: palette.accent,
              foreground: palette.ink,
              border: Border.fromBorderSide(
                BorderSide(color: palette.accentPressed),
              ),
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(approved),
            )
          : Row(
              children: [
                PosButton(
                  label: strings.cancel,
                  height: PosSize.secondaryAction,
                  border: Border.fromBorderSide(palette.resting),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: PosSpace.md),
                Expanded(
                  child: PosButton(
                    label: widget.approveLabel ?? strings.supervisorApproval,
                    height: PosSize.primaryCta,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    // Muted until the PIN and the reason are both in. Never
                    // hidden: a manager has to be able to see what completing
                    // the form will let them do.
                    background: _canApprove ? palette.accent : palette.page,
                    foreground: _canApprove ? palette.ink : palette.muted,
                    border: Border.fromBorderSide(
                      _canApprove
                          ? BorderSide(color: palette.accentPressed)
                          : palette.resting,
                    ),
                    onPressed: _canApprove ? _approve : null,
                  ),
                ),
              ],
            ),
    );
  }
}

/// The masked PIN, as one field rather than four boxes.
///
/// Deliberately **not** `PinDots`. That widget is four 52px boxes built for the
/// full-width lock screen, and it does not fit the 218px column this dialog
/// gives the keypad — the design specifies a single masked field here, and a
/// shared widget squeezed to fit would have changed the lock screen too.
class _PinField extends StatelessWidget {
  const _PinField({required this.length});

  final int length;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;

    return Container(
      height: PosSize.searchRow,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.page,
        border: Border.fromBorderSide(palette.resting),
      ),
      // Digits, and therefore left to right in both locales — a PIN typed on an
      // Arabic till is entered in the order the keys were pressed.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          '•' * length,
          style: PosText.mono(size: 22, color: palette.ink, letterSpacing: 11),
        ),
      ),
    );
  }
}

/// Shown when nobody at this till can authorise the action, with or without a
/// supervisor.
class _RefusalDialog extends StatelessWidget {
  const _RefusalDialog({required this.capability});

  final String capability;

  static Future<void> show(
    BuildContext context, {
    required String capability,
  }) => showDialog<void>(
    context: context,
    barrierColor: context.pos.scrim,
    builder: (_) => _RefusalDialog(capability: capability),
  );

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Dialog(
      backgroundColor: context.pos.page,
      shape: RoundedRectangleBorder(
        side: context.pos.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.notPermittedTitle,
                style: PosText.panelTitle(color: context.pos.ink),
              ),
              const SizedBox(height: PosSpace.sm),
              Text(
                // Named in words, not as `receipt.reprint`: the person
                // reading this is being told what to go and ask for.
                strings.notPermittedBody(
                  AdminText.capability(strings, capability),
                ),
                style: PosText.ui(
                  size: 13,
                  color: context.pos.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: PosSpace.lg),
              PosButton(
                label: strings.close,
                height: 44,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
