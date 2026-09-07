import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../core/ui/widgets/reason_picker.dart';
import '../../../domain/models/business_day.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/services/authorization.dart';
import '../../admin/presentation/supervisor_override.dart';

/// Money into or out of the drawer that is not a sale (§22).
///
/// **Two variants of one dialog, and they must never be confusable.** Money
/// arriving and money leaving are opposite acts with identical arithmetic, and
/// a cashier who reaches for the wrong one has recorded the drawer as 100 up
/// when it is 100 down — a 200 discrepancy from one mis-tap. So the two differ
/// in colour, in title, in the word on the button and in the direction of the
/// sign beside the amount, rather than in a small toggle somewhere.
class CashMovementDialog extends ConsumerStatefulWidget {
  const CashMovementDialog({super.key, required this.kind});

  final CashMovementKind kind;

  /// Returns the amount recorded, or null if nothing was.
  static Future<Money?> show(
    BuildContext context, {
    required CashMovementKind kind,
  }) => showDialog<Money>(
    context: context,
    builder: (_) => CashMovementDialog(kind: kind),
  );

  @override
  ConsumerState<CashMovementDialog> createState() =>
      _CashMovementDialogState();
}

class _CashMovementDialogState extends ConsumerState<CashMovementDialog> {
  final _amount = TextEditingController();
  ReasonCode? _reason;
  String _note = '';
  bool _busy = false;
  String? _message;

  bool get _isOut => widget.kind == CashMovementKind.payOut;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Money? get _entered => Money.tryParse(_amount.text);

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    // Watched, not read at press time. `ref.read` on a provider nothing else
    // is watching starts the future and hands back `AsyncLoading` — so the
    // first press would tell a cashier to open a shift they already have.
    // Watching here means it is resolved by the time the button exists.
    ref.watch(shiftProvider);
    ref.watch(businessDayProvider);

    final scope = _isOut ? ReasonScope.payOut : ReasonScope.payIn;
    final reasons =
        ref.watch(reasonCodesProvider(scope)).valueOrNull ??
        const <ReasonCode>[];

    // Money leaving is the one that costs. It carries the danger colour;
    // money arriving carries the accent. Nothing else in this dialog differs
    // by a shade — the whole point is that the two cannot be told apart at a
    // glance by anything *except* this.
    final accent = _isOut ? palette.danger : palette.accent;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(PosSpace.lg),
                color: _isOut ? palette.dangerSoft : palette.accentSoft,
                child: Row(
                  children: [
                    // The direction, in the one glyph nobody misreads.
                    Text(
                      _isOut ? '−' : '+',
                      style: PosText.mono(
                        size: 28,
                        weight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: PosSpace.md),
                    Expanded(
                      child: Text(
                        _isOut ? strings.payOutTitle : strings.payInTitle,
                        style: PosText.ui(
                          size: 20,
                          weight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PosSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MicroLabel(strings.cashAmountLabel),
                      const SizedBox(height: PosSpace.xs),
                      SizedBox(
                        height: PosSize.formControl,
                        child: TextField(
                          controller: _amount,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          textDirection: TextDirection.ltr,
                          onChanged: (_) => setState(() => _message = null),
                          style: PosText.mono(
                            size: 22,
                            weight: FontWeight.w700,
                            color: palette.ink,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixText: 'EGP ',
                            prefixStyle: PosText.mono(
                              size: 13,
                              color: palette.muted,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: PosSpace.sm,
                            ),
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
                              borderSide: BorderSide(color: accent, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: PosSpace.lg),
                      ReasonPicker(
                        reasons: reasons,
                        // §22 does not make a reason optional for money
                        // leaving a drawer, and neither does anybody who has
                        // ever had to explain one.
                        requirement: ReasonRequirement.required,
                        selected: _reason,
                        note: _note,
                        compact: true,
                        autofocus: false,
                        onChanged: (reason, note) => setState(() {
                          _reason = reason;
                          _note = note;
                          _message = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              _footer(strings, palette, accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(AppStrings strings, PosPalette palette, Color accent) =>
      Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(
          border: BorderDirectional(top: palette.resting),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_message != null) ...[
              Container(
                padding: const EdgeInsets.all(PosSpace.sm),
                color: palette.dangerSoft,
                child: Text(
                  _message!,
                  style: PosText.ui(size: 12.5, color: palette.danger),
                ),
              ),
              const SizedBox(height: PosSpace.md),
            ],
            Row(
              children: [
                Expanded(
                  child: PosButton(
                    label: strings.cancel,
                    border: Border.fromBorderSide(palette.resting),
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: PosSpace.sm),
                Expanded(
                  flex: 2,
                  child: PosButton(
                    label: _isOut
                        ? strings.payOutAction
                        : strings.payInAction,
                    background: _busy ? palette.ctaDisabled : accent,
                    foreground: Colors.white,
                    fontWeight: FontWeight.w700,
                    onPressed: _busy ? null : _record,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _record() async {
    final strings = context.strings;
    final amount = _entered;

    if (amount == null || amount.minor <= 0) {
      setState(() => _message = strings.cashNothingEntered);
      return;
    }
    if (!ReasonPicker.isSatisfied(
      requirement: ReasonRequirement.required,
      reason: _reason,
      note: _note,
    )) {
      setState(() => _message = strings.refundReasonNeeded);
      return;
    }

    final policy = ref.read(cashPolicyProvider);
    if (_isOut && !policy.permitsPayOut(amount)) {
      // A ceiling, not an approval prompt: §22 makes this a configured limit
      // rather than something a supervisor waves through at the counter.
      setState(
        () => _message = strings.cashAboveCeiling(
          policy.payOutCeiling!.format(withCurrency: true),
        ),
      );
      return;
    }

    final shift = ref.read(shiftProvider).valueOrNull;
    if (shift == null) {
      setState(() => _message = strings.cashNoOpenShift);
      return;
    }

    final by = ref.read(signedInStaffProvider);
    if (by == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await ref
          .read(cashMovementsRepositoryProvider)
          .record(
            kind: widget.kind,
            amount: amount,
            by: by,
            shiftId: shift.id,
            reasonId: _reason?.id,
            note: _note.trim().isEmpty ? null : _note.trim(),
            businessDayId: ref.read(businessDayProvider).valueOrNull?.id,
          );
      if (!mounted) return;
      // The shift summary's expected drawer has changed underneath whatever is
      // showing it.
      ref.invalidate(shiftProvider);
      ref.invalidate(cashMovementsProvider(shift.id));
      Navigator.of(context).pop(amount);
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = strings.cashCouldNotBeRecorded;
      });
    }
  }
}

/// Opening the drawer with no sale behind it (§23).
///
/// The one drawer act that moves no money, and therefore the one a dishonest
/// cashier wants most — which is why it has its own capability, its own audit
/// row, and a confirmation that says out loud it is being recorded.
abstract final class DrawerOpenFlow {
  /// Returns true when the drawer was opened.
  static Future<bool> run(BuildContext context, WidgetRef ref) async {
    final strings = context.strings;

    // Resolved before it is needed, for the same reason the dialog above
    // watches: a bare `read` of a provider nothing is watching yields loading.
    final shiftFuture = ref.read(shiftProvider.future);
    await shiftFuture;
    if (!context.mounted) return false;

    final decision = await requestPermission(
      context,
      ref,
      PosCapability.cashOpenWithoutSale,
      action: strings.drawerOpenTitle,
      auditAction: 'drawer.opened',
      entityType: 'drawer',
      approveLabel: strings.drawerOpenAction,
    );
    if (!context.mounted || decision is! Allowed) return false;

    final shift = ref.read(shiftProvider).valueOrNull;
    if (shift == null) {
      posToast(context, strings.cashNoOpenShift);
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DrawerOpenDialog(
        approvedBy: decision.approvedBy?.name,
      ),
    );
    if (confirmed != true || !context.mounted) return false;

    final by = ref.read(signedInStaffProvider);
    if (by == null) return false;

    try {
      await ref
          .read(cashMovementsRepositoryProvider)
          .record(
            kind: CashMovementKind.drawerOpen,
            amount: Money.zero,
            by: by,
            approvedBy: decision.approvedBy,
            shiftId: shift.id,
            businessDayId: ref.read(businessDayProvider).valueOrNull?.id,
          );
    } on Object {
      if (!context.mounted) return false;
      // Not opened. An unrecorded drawer opening is precisely the one somebody
      // wanted, and the till refusing is a smaller problem than a drawer that
      // opens without a trace.
      posToast(context, strings.cashCouldNotBeRecorded);
      return false;
    }

    if (context.mounted) ref.invalidate(cashMovementsProvider(shift.id));
    return true;
  }
}

class _DrawerOpenDialog extends StatelessWidget {
  const _DrawerOpenDialog({this.approvedBy});

  final String? approvedBy;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogDestructive),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.drawerOpenTitle,
                style: PosText.ui(
                  size: 20,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.sm),
              Text(
                strings.drawerOpenExplain,
                style: PosText.ui(size: 13.5, color: palette.body, height: 1.5),
              ),
              if (approvedBy != null) ...[
                const SizedBox(height: PosSpace.xs),
                Text(
                  strings.orderDetailApprovedBy(approvedBy!),
                  style: PosText.ui(size: 12.5, color: palette.muted),
                ),
              ],
              const SizedBox(height: PosSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      label: strings.drawerOpenAction,
                      background: palette.accent,
                      foreground: Colors.white,
                      fontWeight: FontWeight.w700,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the expanded cash-up, and the blind mask.
///
/// Extracted so the Z report, the X report and the drawer count all draw the
/// same figure the same way — and so masking is one flag rather than three
/// screens each remembering to hide something.
class CashUpRow extends StatelessWidget {
  const CashUpRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.masked = false,
    this.tone,
  });

  final String label;
  final Money value;
  final bool emphasis;

  /// Blind close: the figure is replaced by a fixed-length mask.
  final bool masked;

  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: palette.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PosText.ui(
                size: emphasis ? 14 : 13,
                weight: emphasis ? FontWeight.w700 : FontWeight.w400,
                color: tone ?? (emphasis ? palette.ink : palette.body),
              ),
            ),
          ),
          MonoAmount(
            value,
            size: emphasis ? 16 : 13,
            weight: emphasis ? FontWeight.w700 : FontWeight.w400,
            masked: masked,
            color: tone,
          ),
        ],
      ),
    );
  }
}
