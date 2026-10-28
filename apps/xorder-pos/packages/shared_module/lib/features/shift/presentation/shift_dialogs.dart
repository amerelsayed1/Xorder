import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../cash/presentation/cash_dialogs.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../admin_mode/supervisor_override.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import '../../../domain/services/ticket_engine.dart';
import '../../../core/security/attempt_limiter.dart';
import '../../../core/security/pin_hash.dart';
import '../../../core/ui/widgets/mono_amount.dart';

/// Opening a shift: who is on the till, and what is in the drawer.
///
/// Both questions are asked here rather than assumed, because the answers are
/// what make the cash-up mean anything. A shift with no named person is a
/// drawer nobody is answerable for, and a shift with no opening float makes
/// every variance wrong by the same unknown amount.
///
/// **Three ways in**, one dialog, so the PIN pad, the lockout and the wording of
/// a refusal are the same wherever somebody types a PIN:
///
/// * [show]: name and PIN, then the float (the original form).
/// * [show] with [by]: the person is already signed in, so the float only. This
///   is what Home asks for (pos-signin-first-home).
/// * [SignInDialog]: name and PIN and nothing else. Signing in does not open a
///   shift, which is what lets a manager close the day without ever opening a
///   drawer.
class OpenShiftDialog extends ConsumerStatefulWidget {
  const OpenShiftDialog({super.key, this.by, this.signInOnly = false});

  /// Already signed in: skip the PIN and ask for the float.
  final PosStaff? by;

  /// Name and PIN only. Does not need `shift.open` and writes no shift.
  final bool signInOnly;

  /// Returns true when a shift is open and the till may trade.
  static Future<bool> show(BuildContext context, {PosStaff? by}) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: context.pos.scrimHeavy,
        barrierDismissible: false,
        builder: (_) => OpenShiftDialog(by: by),
      ) ??
      false;

  @override
  ConsumerState<OpenShiftDialog> createState() => _OpenShiftDialogState();
}

/// Signing in at the till: a name and a PIN, no shift.
///
/// **Not the same act as opening a shift.** Opening one makes the person answer
/// for a drawer; signing in only says who is at the till. A manager who has come
/// to close the night has no use for a drawer, and an open shift is a blocker
/// for closing the day. Wrong PINs count against the same limiter as the lock
/// screen and the shift dialog.
abstract final class SignInDialog {
  /// Returns true when somebody is now signed in.
  static Future<bool> show(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: context.pos.scrimHeavy,
        barrierDismissible: false,
        builder: (_) => const OpenShiftDialog(signInOnly: true),
      ) ??
      false;
}

class _OpenShiftDialogState extends ConsumerState<OpenShiftDialog> {
  final _float = TextEditingController(text: '0.00');
  final _username = TextEditingController();
  String _pin = '';
  PosStaff? _staff;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _staff = widget.by;
    // Whoever signed in last is offered back, as the lock screen does: at Start
    // the only thing left to type is the PIN.
    if (widget.signInOnly) {
      _username.text = ref.read(lastUsernameProvider) ?? '';
    }
  }

  @override
  void dispose() {
    _float.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submitPin(String digit) async {
    if (_pin.length >= PinRules.length || _busy) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length < PinRules.length) return;

    // The lock screen's limiter, not one of this dialog's own: both doors take
    // the same names and PINs, and a count per door would be five more guesses
    // for every lockout window. Shut means the PIN is not even looked at.
    final limiter = ref.read(signInLimiterProvider);
    final username = _username.text;
    await limiter.ready;
    if (!mounted) return;
    if (limiter.lockedFor(username) case final wait?) {
      setState(() {
        _pin = '';
        _error = context.strings.signInLockedOut(
          AttemptLimiter.secondsToWait(wait),
        );
      });
      return;
    }

    await limiter.reserve(username);
    if (!mounted) return;
    setState(() => _busy = true);
    // Name and PIN, exactly as switching user asks for them. Opening a shift is
    // the same act by another name: the person becomes the operator, and the
    // drawer becomes theirs to answer for. A PIN alone hands that to whichever
    // active member of staff happens to hold those four digits — which, in a
    // business where two people were set up on the same PIN, is not
    // necessarily the person standing at the till.
    final staff = await ref
        .read(sessionRepositoryProvider)
        .signInAs(username: username, pin: _pin);
    if (!mounted) return;
    final strings = context.strings;

    // A right name and PIN clears the count even when the person may not open
    // a shift: the PIN was not what was wrong, and the refusal below says so
    // by name. A wrong one counts, named or not, in the same words.
    final AttemptFailure? failure;
    if (staff != null) {
      limiter.succeed(username);
      failure = null;
    } else {
      failure = limiter.fail(username);
    }

    // Recognising the PIN and being allowed to open a shift are two different
    // questions, and they are asked separately so the second can be answered
    // by name: "Rana cannot open a shift" is actionable, "PIN not recognised"
    // sends somebody to retype a PIN that was right.
    final permitted =
        staff != null &&
        (widget.signInOnly ||
            Authorization.check(staff, PosCapability.shiftOpen).isAllowed);

    // Signing in is the whole job here. Same as the lock screen: the day is
    // made sure of when a shift is already open (a till upgraded mid-shift, or
    // restarted), not awaited, and never throwing: signing in must not wait.
    if (widget.signInOnly && staff != null) {
      ref.read(signedInStaffProvider.notifier).signIn(staff);
      if (ref.read(shiftProvider).valueOrNull != null) {
        unawaited(ref.read(ensureBusinessDayProvider)(staff));
      }
      Navigator.of(context).pop(true);
      return;
    }

    // A wrong PIN is the moment a just-changed one would be wrong: ask the
    // platform again, so the second try can be against the new one (as the
    // lock screen does).
    if (staff == null) ref.read(cloudSyncProvider)?.nudge();

    setState(() {
      _busy = false;
      _pin = '';
      _staff = permitted ? staff : null;
      _error = switch (staff) {
        // One message for both halves, so this cannot be used to find out
        // which usernames exist.
        null => switch (failure) {
          AttemptLockedOut(:final wait) => strings.signInLockedOut(
            AttemptLimiter.secondsToWait(wait),
          ),
          AttemptRefused() || null => strings.wrongUsernameOrPin,
        },
        _ when !permitted => strings.notPermittedToOpenShift(staff.name),
        _ => null,
      };
    });
  }

  Future<void> _open() async {
    final staff = _staff;
    if (staff == null) return;

    // Asked here as well as hidden by the caller: with `by` the PIN step, which
    // used to be where `shift.open` was checked, is skipped, and the repository
    // does not check it. Hiding Home's button is courtesy; this is the guard.
    if (!Authorization.check(staff, PosCapability.shiftOpen).isAllowed) {
      setState(() => _error = context.strings.notPermittedToOpenShift(staff.name));
      return;
    }

    final float = Money.tryParse(_float.text.trim());
    if (float == null || float.minor < 0) {
      setState(() => _error = context.strings.enterOpeningFloat);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // The trading day first: a trigger files the shift under the day whose
      // window contains its `opened_at` when the row is inserted (migration 36),
      // so a day opened afterwards would leave this shift unfiled. Returns
      // rather than throws — the shift opens whatever the day does (the till
      // never stops selling because of it).
      await ref.read(ensureBusinessDayProvider)(staff);
      final shift = await ref
          .read(shiftRepositoryProvider)
          .open(by: staff, openingFloat: float);
      ref.read(signedInStaffProvider.notifier).signIn(staff);
      await ref
          .read(auditRepositoryProvider)
          .record(
            by: staff,
            action: AuditAction.shiftOpened,
            entityType: AuditAction.entityShift,
            entityId: '${shift.id}',
            after: {'opening_float': float.minor, 'currency': float.currency},
          );
      // Anything asking "is a shift open" must see this one immediately —
      // including the orders repository, which stamps it on every sale.
      ref.invalidate(shiftProvider);
      await ref.read(shiftProvider.future);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return _ShiftDialogShell(
      title: _staff == null ? strings.signIn : strings.openTheDrawer,
      subtitle: _staff == null
          ? (widget.signInOnly ? strings.signInOnlyHelp : strings.signInHelp)
          : strings.countTheDrawerHelp(_staff!.name),
      error: _error,
      busy: _busy,
      onCancel: () => Navigator.of(context).pop(false),
      action: _staff == null
          ? null
          : PosButton(
              label: strings.openShift,
              height: 56,
              background: context.pos.accent,
              foreground: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              onPressed: _busy ? null : _open,
            ),
      child: _staff == null ? _pinPane() : _floatPane(strings, pos: context.pos),
    );
  }

  Widget _pinPane() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      UsernameField(
        controller: _username,
        onSubmitted: () => FocusScope.of(context).nextFocus(),
        pinHint: true,
      ),
      const SizedBox(height: PosSpace.lg),
      PinDots(length: _pin.length),
      const SizedBox(height: PosSpace.lg),
      PinPad(
        autofocus: false,
        onDigit: _submitPin,
        onBackspace: () => setState(() {
          if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        }),
      ),
    ],
  );

  Widget _floatPane(AppStrings strings, {required PosPalette pos}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      MicroLabel(strings.openingFloat),
      const SizedBox(height: PosSpace.sm),
      TextField(
        controller: _float,
        autofocus: true,
        style: PosText.mono(color: pos.inkWarm, size: 26),
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _open(),
      ),
      const SizedBox(height: PosSpace.md),
      Wrap(
        spacing: PosSpace.sm,
        runSpacing: PosSpace.sm,
        children: [
          for (final amount in [0, 200, 500, 1000])
            PosButton(
              label: amount == 0 ? strings.emptyDrawer : '$amount',
              background: pos.page,
              border: Border.fromBorderSide(pos.resting),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              onPressed: () =>
                  setState(() => _float.text = Money(amount * 100).format()),
            ),
        ],
      ),
      const SizedBox(height: PosSpace.md),
      Text(
        strings.openingFloatHelp,
        style: PosText.ui(size: 12.5, color: pos.muted, height: 1.5),
      ),
    ],
  );
}

/// Closing a shift: the Z report, and the count that has to agree with it.
class CloseShiftDialog extends ConsumerStatefulWidget {
  const CloseShiftDialog({super.key, required this.shift});

  final PosShift shift;

  /// Returns true once the shift is closed and the till should return to the
  /// start screen.
  static Future<bool> show(
    BuildContext context, {
    required PosShift shift,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: context.pos.scrimHeavy,
        barrierDismissible: false,
        builder: (_) => CloseShiftDialog(shift: shift),
      ) ??
      false;

  @override
  ConsumerState<CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends ConsumerState<CloseShiftDialog> {
  final _counted = TextEditingController();

  /// Optional, and there for everybody — including a cashier counting blind,
  /// who cannot see a variance and may still know why the drawer is short.
  /// What the platform accepts as a close's reason, and no more.
  final _note = TextEditingController();
  static const _noteMax = 255;
  ShiftSummary? _summary;
  ShiftClose? _closed;
  bool _busy = true;
  String? _error;

  /// Whether the expected figure is hidden while this person counts.
  ///
  /// Two conditions, and both have to hold: the business asked for blind
  /// counting, **and** this person does not hold `shift.view_expected_cash`.
  /// A manager counting their own drawer under a blind policy still sees the
  /// figure, because withholding it from the person who set the policy
  /// protects nobody.
  bool get _blind =>
      ref.watch(cashPolicyProvider).blindClose &&
      !ref.watch(canProvider(PosCapability.shiftViewExpectedCash)).isAllowed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final summary = await ref
          .read(shiftRepositoryProvider)
          .summarise(widget.shift);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Money? get _countedMoney => Money.tryParse(_counted.text.trim());

  Future<void> _close() async {
    final summary = _summary;
    final counted = _countedMoney;
    if (summary == null) return;
    final strings = context.strings;
    if (counted == null || counted.minor < 0) {
      setState(() => _error = strings.countTheDrawer);
      return;
    }

    final by = ref.read(signedInStaffProvider);
    if (by == null) {
      setState(() => _error = strings.signInBeforeClosing);
      return;
    }

    // **The drawer belongs to whoever opened it.**
    //
    // This used to read the other way round — a manager cashing up at the end
    // of the night was treated as the normal case — and that made the count
    // signable by anybody holding the capability, with only a name on the audit
    // row to say who. The float was counted in by one person and out by
    // another, and the variance had two people to argue about it.
    //
    // Not a dead end, though: somebody goes home sick, and a till that can
    // never be cashed up is worse than one cashed up under supervision. Anybody
    // else needs a manager to put their PIN in HERE, in front of the drawer,
    // and both names go on the audit row.
    Approval? handover;
    if (!widget.shift.openedBy(by.id)) {
      final outcome = await SupervisorOverrideDialog.show(
        context,
        capability: PosCapability.shiftClose,
        action: strings.closeShiftNotYours(widget.shift.openedByName),
        requestedBy: by.name,
      );
      if (outcome == null) return;
      if (!mounted) return;
      final lent = Authorization.approve(
        approver: outcome.approver,
        capability: PosCapability.shiftClose,
        subject: '${widget.shift.id}',
      );
      if (lent is! Allowed) return;
      handover = lent.approval;
      // On the ledger in its own right. It used to have no row of its own:
      // the close's row named the manager, and nothing said they had released
      // somebody else's drawer rather than simply approved a count.
      await recordApproval(
        ref,
        approver: outcome.approver,
        capability: PosCapability.shiftClose,
        auditAction: 'shift.close.handover',
        entityType: AuditAction.entityShift,
        entityId: '${widget.shift.id}',
      );
      if (!mounted) return;
    }

    // Overridable, unlike opening: a cashier who may not cash up is standing at
    // a drawer that has to be counted before anybody goes home, and a
    // supervisor putting their PIN in is the workflow that actually happens.
    // Both names then go on the audit row.
    final decision = await requestPermission(
      context,
      ref,
      PosCapability.shiftClose,
      action: strings.closeShiftApproval(widget.shift.reference),
      auditAction: 'Close ${widget.shift.reference} and count the drawer',
      entityType: AuditAction.entityShift,
      entityId: '${widget.shift.id}',
    );
    if (decision is! Allowed) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final closed = await ref
          .read(shiftRepositoryProvider)
          .close(
            shift: widget.shift,
            by: by,
            countedCash: counted,
            // Spaces are no note. Null reaches the platform as a generated line
            // of the till's own figures; a note reaches it as the reason.
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            // The handover, when there was one: it is what lets somebody who
            // did not open this drawer close it, and it covers the permission
            // too.
            approval: handover ?? decision.approval,
          );
      // The variance is on the ledger as well as on the shift. It is the number
      // a manager argues about, and the argument is easier when the row also
      // says who counted and who approved them counting.
      await ref
          .read(auditRepositoryProvider)
          .record(
            by: by,
            // The manager who released somebody else's drawer, when that is
            // what happened — otherwise whoever approved the capability.
            approvedBy: handover?.approver ?? decision.approvedBy,
            action: AuditAction.shiftClosed,
            entityType: AuditAction.entityShift,
            entityId: '${widget.shift.id}',
            after: {
              'counted_minor': closed.countedCash.minor,
              'expected_minor': summary.expectedCash.minor,
              'variance_minor': closed.variance.minor,
            },
          );
      if (!mounted) return;
      setState(() {
        _closed = closed;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  void _finish() {
    ref.read(signedInStaffProvider.notifier).signOut();
    ref.invalidate(shiftProvider);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final closed = _closed;
    if (closed != null) return _closedShell(closed, pos: context.pos);

    final strings = context.strings;
    final summary = _summary;
    return _ShiftDialogShell(
      title: strings.closeShiftTitle(widget.shift.reference),
      subtitle: strings.closeShiftHelp(widget.shift.openedByName),
      error: _error,
      busy: _busy,
      onCancel: () => Navigator.of(context).pop(false),
      action: summary == null
          ? null
          : PosButton(
              label: strings.closeShift,
              height: 56,
              background: context.pos.accent,
              foreground: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              onPressed: _busy ? null : _close,
            ),
      child: summary == null
          ? const SizedBox(height: 80)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // What is still open goes FIRST, above the figures: a
                // warning under a Z report is a warning read after the
                // decision it was meant to inform.
                _OpenTicketsWarning(ref.watch(openTicketsProvider)),
                // Blind while counting (§25): the expected figure and the
                // live difference are hidden from anybody who may not see
                // them, so the count is a count rather than a reconciliation
                // to a number already on screen.
                ZReportView(summary: summary, blind: _blind),
                const SizedBox(height: PosSpace.lg),
                MicroLabel(strings.countedInDrawer),
                const SizedBox(height: PosSpace.sm),
                TextField(
                  controller: _counted,
                  autofocus: true,
                  style: PosText.mono(color: context.pos.inkWarm, size: 26),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _close(),
                ),
                if (!_blind) const SizedBox(height: PosSpace.md),
                // Not while blind. Every line of this panel is the expected
                // cash one subtraction away: the difference as it is typed,
                // the expected figure itself once the count matches, and, with
                // nothing typed yet, "Expected X". The count is revealed after
                // closing, to whoever holds `cash.variance.view` (see
                // [_closedShell]).
                if (!_blind) _variance(strings, summary, pos: context.pos),
                const SizedBox(height: PosSpace.lg),
                MicroLabel(strings.closeShiftNoteLabel),
                const SizedBox(height: PosSpace.sm),
                TextField(
                  key: const Key('close-shift-note'),
                  controller: _note,
                  maxLines: 2,
                  minLines: 1,
                  inputFormatters: [LengthLimitingTextInputFormatter(_noteMax)],
                  style: PosText.ui(color: context.pos.inkWarm, size: 14),
                  decoration: InputDecoration(hintText: strings.closeShiftNoteHint),
                ),
              ],
            ),
    );
  }

  /// Shown live, before anything is committed, so a miscount is caught while
  /// the notes are still in someone's hand.
  Widget _variance(AppStrings strings, ShiftSummary summary, {required PosPalette pos}) {
    final counted = _countedMoney;
    if (counted == null) {
      return Text(
        strings.expectedInDrawerHelp(
          summary.expectedCash.format(withCurrency: true),
          summary.shift.openingFloat.format(withCurrency: true),
          summary.cashTaken.format(withCurrency: true),
        ),
        style: PosText.ui(size: 12.5, color: pos.muted, height: 1.5),
      );
    }

    final variance = summary.varianceAgainst(counted);
    final balances = variance.minor == 0;
    final over = variance.minor > 0;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: balances ? pos.okSoft : pos.warnSoft,
        border: Border.all(
          color: balances ? pos.ok : pos.warn,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Text(
            balances
                ? strings.varianceBalances
                : (over ? strings.varianceOver : strings.varianceShort),
            style: PosText.mono(
              size: 11,
              weight: FontWeight.w600,
              color: balances ? pos.ok : pos.warn,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            balances ? summary.expectedCash.format(withCurrency: true) : variance.format(withCurrency: true),
            style: PosText.mono(color: pos.inkWarm, size: 18, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _closedShell(ShiftClose closed, {required PosPalette pos}) {
    final strings = context.strings;

    return _ShiftDialogShell(
      title: strings.shiftClosedTitle(widget.shift.reference),
      subtitle: closed.balances
          ? strings.drawerBalances
          : strings.closedWithVariance(closed.variance.format(withCurrency: true)),
      busy: false,
      onCancel: null,
      action: PosButton(
        label: strings.done,
        height: 56,
        background: pos.ink,
        foreground: pos.onInk,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        onPressed: _finish,
      ),
      // Revealed after committing, to anybody holding `cash.variance.view`.
      // A cashier who counted blind still learns whether they were right —
      // from a supervisor, not from the screen — which is the whole reason
      // these are two capabilities rather than one.
      child: ZReportView(
        summary: closed.summary,
        counted: closed.countedCash,
        blind: !ref.read(canProvider(PosCapability.cashVarianceView)).isAllowed,
      ),
    );
  }
}

/// What is still parked when somebody goes to close the shift (S3-5).
///
/// The audit watched a shift closed with an 80.00 ticket parked and a close
/// dialog that said nothing about it. Now every open ticket is listed — its
/// table, or *Held* for one with no table, and what it comes to — under one
/// line that counts them and adds them up. **A warning, not a refusal.**
/// Closing over them is still the owner's call (the day close is where a
/// parked ticket is a blocker); what this removes is closing over them
/// without knowing.
///
/// Nothing when nothing is open: a warning box with "0 tickets" in it would
/// teach everybody to stop reading it.
class _OpenTicketsWarning extends StatelessWidget {
  const _OpenTicketsWarning(this.open);

  final OpenTickets open;

  @override
  Widget build(BuildContext context) {
    if (open.isEmpty) return const SizedBox.shrink();

    final strings = context.strings;
    final pos = context.pos;
    // Tables first, in table order, then the held ones oldest first — the
    // order a manager walks the floor and then the counter.
    final tickets = [
      ...open.onTables.values,
      ...open.held,
    ];
    // Added up by the engine, not here: money is added up in one place.
    final total = TicketEngine.totalOf(tickets);

    return Padding(
      padding: const EdgeInsets.only(bottom: PosSpace.lg),
      child: Container(
        key: const Key('close-shift-open-tickets'),
        padding: const EdgeInsets.all(PosSpace.md),
        decoration: BoxDecoration(
          color: pos.warnSoft,
          border: Border.all(color: pos.warn, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.closeShiftOpenTickets(
                tickets.length,
                total.format(withCurrency: true),
              ),
              style: PosText.ui(
                size: 13,
                weight: FontWeight.w700,
                color: pos.ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: PosSpace.sm),
            for (final ticket in tickets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.tableLabel ?? strings.closeShiftHeldTicket,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PosText.ui(size: 12.5, color: pos.body),
                      ),
                    ),
                    MonoAmount(ticket.totals.total, size: 12.5, color: pos.ink),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The Z report, in the order somebody standing at a drawer reads it.
///
/// Public since People › Shifts reads a shift's report back in the back
/// office: one widget, so the report a manager opens there is laid out as the
/// cashier saw it at the drawer rather than as a second copy that drifts.
class ZReportView extends StatelessWidget {
  const ZReportView({
    super.key,
    required this.summary,
    this.counted,
    this.expected,
    this.blind = false,
  });

  final ShiftSummary summary;
  final Money? counted;

  /// The expected figure the cash-up **stored**, for a shift already counted.
  ///
  /// Null at the drawer, where [summary] was read in the close's own
  /// transaction and is that figure. Read back later, the rows under
  /// [summary] may have moved; the count was judged against what was stored,
  /// and a difference recomputed from today's rows would be a different
  /// difference from the one on the list beside it.
  final Money? expected;

  /// Hide the expected figure and the live difference (§25), and what the
  /// expected figure is made of.
  ///
  /// The count itself is never hidden — a cashier has to see what they typed.
  /// What blind withholds is the *answer*, so that counting is counting rather
  /// than reconciling to a number already on screen. The expected cash is the
  /// float plus the cash tenders plus pay-ins less pay-outs, so the tender rows
  /// and the pay-in and pay-out rows go too: shown beside the float they are the
  /// sum with the answer masked (audit, 17 Oct 2026).
  ///
  /// The sales totals stay. The cashier rang those sales, and a Z report
  /// without them is no report. What that leaves is a limit worth knowing: on a
  /// shift paid only in cash, *gross taken* is the cash taken.
  final bool blind;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final expected = this.expected ?? summary.expectedCash;
    final variance = counted == null ? null : counted! - expected;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.fromBorderSide(palette.resting),
      ),
      child: Column(
        children: [
          // ── What was sold ──────────────────────────────────────────────
          _count(context, strings.zSales, summary.saleCount),
          CashUpRow(label: strings.zSubtotal, value: summary.subtotal),
          if (!summary.discounts.isZero)
            CashUpRow(
              label: strings.zDiscounts,
              value: -summary.discounts,
              tone: palette.warn,
            ),
          if (!summary.service.isZero)
            CashUpRow(label: strings.zService, value: summary.service),
          CashUpRow(label: strings.zVat, value: summary.vat),
          CashUpRow(
            label: strings.zGrossTaken,
            value: summary.gross,
            emphasis: true,
          ),

          // ── What went back, and what was thrown away ───────────────────
          //
          // Refunds are NOT netted off the gross above. A shift that sold
          // 1,000 and refunded 200 did both things, and a report showing only
          // 800 hides the 200 — which is the number a manager is looking for.
          if (!summary.refunds.isZero)
            CashUpRow(
              label: strings.zRefunds,
              value: -summary.refunds,
              tone: palette.warn,
            ),
          if (!summary.voids.isZero)
            CashUpRow(
              label: strings.zVoids,
              value: summary.voids,
              tone: palette.danger,
            ),
          if (!summary.refunds.isZero)
            CashUpRow(
              label: strings.zNet,
              value: summary.net,
              emphasis: true,
            ),

          // ── How it was paid ────────────────────────────────────────────
          //
          // The tender label is whatever was WRITTEN with the payment, and it
          // stays as written. What the drawer's cash is worked out from is the
          // tender *type* beside it — see `TenderMethod.countsAsCash`.
          //
          // Not while blind: these are the cash the drawer should hold, in
          // pieces (see [blind]).
          if (!blind)
            for (final tender in summary.tenders)
              CashUpRow(
                label: strings.zTenderRow(tender.label, tender.count),
                value: tender.amount,
              ),

          // ── The drawer ─────────────────────────────────────────────────
          CashUpRow(
            label: strings.zOpeningFloat,
            value: summary.shift.openingFloat,
          ),
          // Pay-ins and pay-outs change what the drawer should hold, so they
          // are withheld while blind like the tenders above.
          if (!blind && !summary.cashIn.isZero)
            CashUpRow(label: strings.zCashIn, value: summary.cashIn),
          if (!blind && !summary.cashOut.isZero)
            CashUpRow(
              label: strings.zCashOut,
              value: -summary.cashOut,
              tone: palette.warn,
            ),
          if (summary.drawerOpens > 0)
            _count(context, strings.zDrawerOpens, summary.drawerOpens),
          CashUpRow(
            label: blind
                ? strings.zHiddenUntilCounted
                : strings.zExpectedInDrawer,
            value: expected,
            emphasis: true,
            masked: blind,
          ),
          if (counted != null)
            CashUpRow(
              label: strings.zCounted,
              value: counted!,
              emphasis: true,
            ),
          if (variance != null && !blind)
            CashUpRow(
              label: strings.zVariance,
              value: variance,
              emphasis: true,
              tone: variance.isZero ? null : palette.danger,
            ),
        ],
      ),
    );
  }

  /// A count, not money. Rendered through the same row so the column of
  /// figures still lines up.
  Widget _count(BuildContext context, String label, int value) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.sm,
    ),
    decoration: BoxDecoration(border: Border(bottom: context.pos.hairline)),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: PosText.ui(size: 13, color: context.pos.body),
          ),
        ),
        Text(
          '$value',
          style: PosText.mono(size: 13, color: context.pos.ink),
        ),
      ],
    ),
  );
}

/// One shift's Z report, read back from the back office (People › Shifts).
///
/// The close dialog's report inside the close dialog's chrome, and nothing
/// else: no count box and no button but Close, because nothing in the back
/// office writes a shift. A drawer is counted at the drawer.
class ShiftReportDialog extends StatelessWidget {
  const ShiftReportDialog({super.key, required this.record, this.blind = false});

  final ShiftRecord record;

  /// Hide the expected figure and the difference — see [ZReportView.blind].
  final bool blind;

  static Future<void> show(
    BuildContext context, {
    required ShiftRecord record,
    bool blind = false,
  }) => showDialog<void>(
    context: context,
    barrierColor: context.pos.scrimHeavy,
    builder: (_) => ShiftReportDialog(
      key: const Key('shift-report'),
      record: record,
      blind: blind,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final shift = record.shift;
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(top: PosSpace.sm),
      child: Text(
        text,
        style: PosText.ui(size: 12.5, color: pos.body, height: 1.5),
      ),
    );

    return _ShiftDialogShell(
      title: shift.isOpen
          ? strings.shiftStillOpenTitle(shift.reference)
          : strings.shiftClosedTitle(shift.reference),
      subtitle: strings.shiftReportSubtitle(
        record.terminalName ?? record.terminalId,
        shift.openedByName,
      ),
      busy: false,
      onCancel: null,
      action: PosButton(
        label: strings.close,
        height: 48,
        border: Border.fromBorderSide(pos.resting),
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ZReportView(
            summary: record.summary,
            counted: record.countedCash,
            expected: record.recordedExpected,
            blind: blind,
          ),
          if (record.closedByName case final name?)
            line(strings.shiftReportCountedBy(name)),
          if (record.approvedByName case final name?)
            line(strings.settlementsApprovedBy(name)),
          if (record.note case final note? when note.trim().isNotEmpty)
            line(strings.shiftReportNote(note)),
        ],
      ),
    );
  }
}

/// Shared chrome, so opening and closing a shift look like two halves of one
/// thing rather than two dialogs that happen to be near each other.
class _ShiftDialogShell extends StatelessWidget {
  const _ShiftDialogShell({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.busy,
    required this.onCancel,
    this.action,
    this.error,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool busy;
  final VoidCallback? onCancel;
  final Widget? action;
  final String? error;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    // Esc is the same as pressing Cancel, and is ignored while a save is in
    // flight or when the dialog has no cancel (a closed shift is final).
    // `autofocus` so Esc works before anybody has clicked into a field.
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (!busy) onCancel?.call();
      },
    },
    child: Focus(autofocus: true, child: _dialog(context)),
  );

  Widget _dialog(BuildContext context) => Dialog(
    backgroundColor: context.pos.page,
    insetPadding: const EdgeInsets.all(PosSpace.s24),
    shape: RoundedRectangleBorder(
      side: context.pos.emphasis,
      borderRadius: PosBorders.radius,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: PosText.panelTitle(color: context.pos.ink)),
            const SizedBox(height: PosSpace.sm),
            Text(
              subtitle,
              style: PosText.ui(size: 13, color: context.pos.muted, height: 1.5),
            ),
            const SizedBox(height: PosSpace.lg),
            child,
            if (error != null) ...[
              const SizedBox(height: PosSpace.md),
              Container(
                padding: const EdgeInsets.all(PosSpace.md),
                decoration: BoxDecoration(
                  color: context.pos.dangerSoft,
                  border: Border.all(color: context.pos.danger),
                ),
                child: Text(
                  error!,
                  style: PosText.ui(
                    size: 12.5,
                    color: context.pos.ink,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: PosSpace.lg),
            if (busy)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(PosSpace.sm),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.pos.accent,
                    ),
                  ),
                ),
              ),
            ?action,
            if (onCancel != null) ...[
              const SizedBox(height: PosSpace.sm),
              PosButton(
                label: context.strings.cancel,
                height: 44,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: busy ? null : onCancel,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
