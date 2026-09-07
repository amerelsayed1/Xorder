import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../admin/presentation/supervisor_override.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import '../../../core/security/pin_hash.dart';

/// Opening a shift: who is on the till, and what is in the drawer.
///
/// Both questions are asked here rather than assumed, because the answers are
/// what make the cash-up mean anything. A shift with no named person is a
/// drawer nobody is answerable for, and a shift with no opening float makes
/// every variance wrong by the same unknown amount.
class OpenShiftDialog extends ConsumerStatefulWidget {
  const OpenShiftDialog({super.key});

  /// Returns true when a shift is open and the till may trade.
  static Future<bool> show(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: context.pos.scrimHeavy,
        barrierDismissible: false,
        builder: (_) => const OpenShiftDialog(),
      ) ??
      false;

  @override
  ConsumerState<OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends ConsumerState<OpenShiftDialog> {
  final _float = TextEditingController(text: '0.00');
  String _pin = '';
  PosStaff? _staff;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _submitPin(String digit) async {
    if (_pin.length >= PinRules.length || _busy) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length < PinRules.length) return;

    setState(() => _busy = true);
    final staff = await ref.read(sessionRepositoryProvider).signIn(_pin);
    if (!mounted) return;
    final strings = context.strings;

    // Recognising the PIN and being allowed to open a shift are two different
    // questions, and they are asked separately so the second can be answered
    // by name: "Rana cannot open a shift" is actionable, "PIN not recognised"
    // sends somebody to retype a PIN that was right.
    final permitted =
        staff != null &&
        Authorization.check(staff, PosCapability.shiftOpen).isAllowed;

    setState(() {
      _busy = false;
      _pin = '';
      _staff = permitted ? staff : null;
      _error = switch (staff) {
        null => strings.pinNotRecognised,
        _ when !permitted => strings.notPermittedToOpenShift(staff.name),
        _ => null,
      };
    });
  }

  Future<void> _open() async {
    final staff = _staff;
    if (staff == null) return;

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
          ? strings.signInHelp
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
      PinDots(length: _pin.length),
      const SizedBox(height: PosSpace.lg),
      PinPad(
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
  ShiftSummary? _summary;
  ShiftClose? _closed;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _counted.dispose();
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

    // The person closing signs for the count, and it need not be whoever opened
    // the shift — a manager cashing up at the end of the night is the normal
    // case, not an exception.
    final by = ref.read(signedInStaffProvider);
    if (by == null) {
      setState(() => _error = strings.signInBeforeClosing);
      return;
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
          .close(shift: widget.shift, by: by, countedCash: counted);
      // The variance is on the ledger as well as on the shift. It is the number
      // a manager argues about, and the argument is easier when the row also
      // says who counted and who approved them counting.
      await ref
          .read(auditRepositoryProvider)
          .record(
            by: by,
            approvedBy: decision.approvedBy,
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
                _ZReport(summary: summary),
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
                const SizedBox(height: PosSpace.md),
                _variance(strings, summary, pos: context.pos),
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
          summary.expectedCash.format(),
          summary.shift.openingFloat.format(),
          summary.cashTaken.format(),
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
            balances ? summary.expectedCash.format() : variance.format(),
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
          : strings.closedWithVariance(closed.variance.format()),
      busy: false,
      onCancel: null,
      action: PosButton(
        label: strings.done,
        height: 56,
        background: pos.ink,
        foreground: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        onPressed: _finish,
      ),
      child: _ZReport(summary: closed.summary, counted: closed.countedCash),
    );
  }
}

/// The Z report, in the order somebody standing at a drawer reads it.
class _ZReport extends StatelessWidget {
  const _ZReport({required this.summary, this.counted});

  final ShiftSummary summary;
  final Money? counted;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      decoration: BoxDecoration(
        color: context.pos.surface,
        border: Border.fromBorderSide(context.pos.resting),
      ),
      child: Column(
        children: [
          _row(strings.zSales, '${summary.saleCount}', pos: context.pos),
          _row(strings.zGrossTaken, summary.gross.format(), pos: context.pos),
          // The tender label is whatever was WRITTEN with the payment, and
          // it stays as written. It is the same text `cashTaken` matches on
          // to work out what the drawer should hold, and a report that
          // renamed it would no longer describe the sum beneath it.
          for (final tender in summary.tenders)
            _row(
              strings.zTenderRow(tender.label, tender.count),
              tender.amount.format(),
            pos: context.pos),
          _row(strings.zOpeningFloat, summary.shift.openingFloat.format(), pos: context.pos),
          _row(
            strings.zExpectedInDrawer,
            summary.expectedCash.format(),
            emphasis: true,
          pos: context.pos),
          if (counted != null)
            _row(strings.zCounted, counted!.format(), emphasis: true, pos: context.pos),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {required PosPalette pos, bool emphasis = false}) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.md,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: pos.hairline),
    ),
    child: Row(
      children: [
        Text(
          label,
          style: PosText.ui(color: pos.inkWarm, 
            size: 13,
            weight: emphasis ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: PosText.mono(color: pos.inkWarm, 
            size: emphasis ? 15 : 13,
            weight: emphasis ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Dialog(
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
