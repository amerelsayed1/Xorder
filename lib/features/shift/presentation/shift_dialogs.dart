import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/shift.dart';

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
        barrierColor: PosColors.scrimHeavy,
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
    if (_pin.length >= 4 || _busy) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length < 4) return;

    setState(() => _busy = true);
    final staff = await ref.read(sessionRepositoryProvider).signIn(_pin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _pin = '';
      _staff = staff;
      _error = staff == null ? 'That PIN was not recognised.' : null;
    });
  }

  Future<void> _open() async {
    final staff = _staff;
    if (staff == null) return;

    final float = Money.tryParse(_float.text.trim());
    if (float == null || float.minor < 0) {
      setState(() => _error = 'Enter the opening float, or 0.00 if the drawer is empty.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(shiftRepositoryProvider).open(by: staff, openingFloat: float);
      ref.read(signedInStaffProvider.notifier).signIn(staff);
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
  Widget build(BuildContext context) => _ShiftDialogShell(
        title: _staff == null ? 'Sign in' : 'Open the drawer',
        subtitle: _staff == null
            ? 'Enter your PIN. The shift is opened in your name.'
            : '${_staff!.name} · count what is in the drawer before you start.',
        error: _error,
        busy: _busy,
        onCancel: () => Navigator.of(context).pop(false),
        action: _staff == null
            ? null
            : PosButton(
                label: 'Open shift',
                height: 56,
                background: PosColors.accent,
                foreground: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                onPressed: _busy ? null : _open,
              ),
        child: _staff == null ? _pinPane() : _floatPane(),
      );

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

  Widget _floatPane() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MicroLabel('Opening float'),
          const SizedBox(height: PosSpace.sm),
          TextField(
            controller: _float,
            autofocus: true,
            style: PosText.mono(size: 26),
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
                  label: amount == 0 ? 'Empty' : '$amount',
                  background: PosColors.page,
                  border: const Border.fromBorderSide(PosBorders.resting),
                  padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                  onPressed: () => setState(
                    () => _float.text = Money(amount * 100).format(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: PosSpace.md),
          Text(
            'This is the cash already in the drawer. Every variance at cash-up '
            'is measured from it, so a guess here is a discrepancy later.',
            style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
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
  static Future<bool> show(BuildContext context, {required PosShift shift}) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: PosColors.scrimHeavy,
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
      final summary = await ref.read(shiftRepositoryProvider).summarise(widget.shift);
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
    if (counted == null || counted.minor < 0) {
      setState(() => _error = 'Count the drawer and enter the total.');
      return;
    }

    // The person closing signs for the count, and it need not be whoever opened
    // the shift — a manager cashing up at the end of the night is the normal
    // case, not an exception.
    final by = ref.read(signedInStaffProvider);
    if (by == null) {
      setState(() => _error = 'Sign in before closing a shift.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final closed = await ref.read(shiftRepositoryProvider).close(
            shift: widget.shift,
            by: by,
            countedCash: counted,
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
    if (closed != null) return _closedShell(closed);

    final summary = _summary;
    return _ShiftDialogShell(
      title: 'Close ${widget.shift.reference}',
      subtitle: 'Opened by ${widget.shift.openedByName}. Count the drawer, then confirm.',
      error: _error,
      busy: _busy,
      onCancel: () => Navigator.of(context).pop(false),
      action: summary == null
          ? null
          : PosButton(
              label: 'Close shift',
              height: 56,
              background: PosColors.accent,
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
                const MicroLabel('Counted in the drawer'),
                const SizedBox(height: PosSpace.sm),
                TextField(
                  controller: _counted,
                  autofocus: true,
                  style: PosText.mono(size: 26),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _close(),
                ),
                const SizedBox(height: PosSpace.md),
                _variance(summary),
              ],
            ),
    );
  }

  /// Shown live, before anything is committed, so a miscount is caught while
  /// the notes are still in someone's hand.
  Widget _variance(ShiftSummary summary) {
    final counted = _countedMoney;
    if (counted == null) {
      return Text(
        'Expected ${summary.expectedCash.format()} — float '
        '${summary.shift.openingFloat.format()} plus ${summary.cashTaken.format()} taken in cash.',
        style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
      );
    }

    final variance = summary.varianceAgainst(counted);
    final balances = variance.minor == 0;
    final over = variance.minor > 0;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: balances ? PosColors.okSoft : PosColors.warnSoft,
        border: Border.all(color: balances ? PosColors.ok : PosColors.warn, width: 2),
      ),
      child: Row(
        children: [
          Text(
            balances ? 'BALANCES' : (over ? 'OVER' : 'SHORT'),
            style: PosText.mono(
              size: 11,
              weight: FontWeight.w600,
              color: balances ? PosColors.ok : PosColors.warn,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            balances ? summary.expectedCash.format() : variance.format(),
            style: PosText.mono(size: 18, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _closedShell(ShiftClose closed) => _ShiftDialogShell(
        title: '${widget.shift.reference} closed',
        subtitle: closed.balances
            ? 'The drawer balances.'
            : 'Recorded with a variance of ${closed.variance.format()}. It is on the '
                'shift record, not lost.',
        busy: false,
        onCancel: null,
        action: PosButton(
          label: 'Done',
          height: 56,
          background: PosColors.ink,
          foreground: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          onPressed: _finish,
        ),
        child: _ZReport(summary: closed.summary, counted: closed.countedCash),
      );
}

/// The Z report, in the order somebody standing at a drawer reads it.
class _ZReport extends StatelessWidget {
  const _ZReport({required this.summary, this.counted});

  final ShiftSummary summary;
  final Money? counted;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: PosColors.surface,
          border: Border.fromBorderSide(PosBorders.resting),
        ),
        child: Column(
          children: [
            _row('Sales', '${summary.saleCount}'),
            _row('Gross taken', summary.gross.format()),
            for (final tender in summary.tenders)
              _row('  ${tender.label} × ${tender.count}', tender.amount.format()),
            _row('Opening float', summary.shift.openingFloat.format()),
            _row('Expected in drawer', summary.expectedCash.format(), emphasis: true),
            if (counted != null) _row('Counted', counted!.format(), emphasis: true),
          ],
        ),
      );

  Widget _row(String label, String value, {bool emphasis = false}) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.md,
        ),
        decoration: const BoxDecoration(border: Border(bottom: PosBorders.hairline)),
        child: Row(
          children: [
            Text(
              label,
              style: PosText.ui(
                size: 13,
                weight: emphasis ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: PosText.mono(
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
        backgroundColor: PosColors.page,
        insetPadding: const EdgeInsets.all(PosSpace.s24),
        shape: const RoundedRectangleBorder(
          side: PosBorders.emphasis,
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
                Text(title, style: PosText.panelTitle()),
                const SizedBox(height: PosSpace.sm),
                Text(
                  subtitle,
                  style: PosText.ui(size: 13, color: PosColors.muted, height: 1.5),
                ),
                const SizedBox(height: PosSpace.lg),
                child,
                if (error != null) ...[
                  const SizedBox(height: PosSpace.md),
                  Container(
                    padding: const EdgeInsets.all(PosSpace.md),
                    decoration: BoxDecoration(
                      color: PosColors.dangerSoft,
                      border: Border.all(color: PosColors.danger),
                    ),
                    child: Text(
                      error!,
                      style: PosText.ui(size: 12.5, color: PosColors.ink, height: 1.5),
                    ),
                  ),
                ],
                const SizedBox(height: PosSpace.lg),
                if (busy)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(PosSpace.sm),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PosColors.accent,
                        ),
                      ),
                    ),
                  ),
                ?action,
                if (onCancel != null) ...[
                  const SizedBox(height: PosSpace.sm),
                  PosButton(
                    label: 'Cancel',
                    height: 44,
                    border: const Border.fromBorderSide(PosBorders.resting),
                    onPressed: busy ? null : onCancel,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
