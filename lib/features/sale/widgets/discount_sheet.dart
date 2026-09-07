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
import '../../../domain/models/discount.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/services/ticket_engine.dart';
import '../../admin/presentation/supervisor_override.dart';

/// Take money off — a configured discount, or one the person types.
///
/// One sheet for both scopes. A cashier reaching for `F6` has a ticket in front
/// of them and either a line selected or not; making them choose between two
/// different screens first would be asking them to classify their own intent
/// before they can act on it.
///
/// **This is where the whole permission chain finally runs end to end**: the
/// engine prices the discount against the person's ceiling, a
/// [DiscountAboveLimit] refusal becomes a manager-approval prompt rather than a
/// dead end, and the approver's name travels back onto the applied record.
class DiscountSheet extends ConsumerStatefulWidget {
  const DiscountSheet({
    required this.ticket,
    required this.lineKey,
    required this.lineLabel,
    this.preApprovedBy,
    super.key,
  });

  final Ticket ticket;

  /// The line the cashier had selected, or null for the whole order.
  final String? lineKey;

  /// What that line is called, for the manager-approval prompt.
  final String? lineLabel;

  /// A supervisor who has **already** approved this, because the person at the
  /// till does not hold `discount.apply` at all.
  ///
  /// When set, no ceiling is applied and no second prompt appears. Asking a
  /// manager twice — once for the permission and once for the amount — is the
  /// same question with extra steps, and it is asked while a customer waits.
  final PosStaff? preApprovedBy;

  /// Returns the ticket with the discount on it, or null if nothing changed.
  static Future<Ticket?> show(
    BuildContext context, {
    required Ticket ticket,
    String? lineKey,
    String? lineLabel,
    PosStaff? preApprovedBy,
  }) => showDialog<Ticket>(
    context: context,
    barrierColor: context.pos.scrim,
    builder: (_) => DiscountSheet(
      ticket: ticket,
      lineKey: lineKey,
      lineLabel: lineLabel,
      preApprovedBy: preApprovedBy,
    ),
  );

  @override
  ConsumerState<DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<DiscountSheet> {
  final _value = TextEditingController();
  DiscountKind _customKind = DiscountKind.percentage;
  Discount? _selected;
  String? _error;
  bool _busy = false;

  /// Whether the discount is aimed at one line or the whole bill.
  ///
  /// Starts wherever the cashier already was: a line selected means they were
  /// looking at a line.
  late bool _wholeOrder = widget.lineKey == null;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  String? get _targetLineKey => _wholeOrder ? null : widget.lineKey;

  /// What the discount would come off, so the sheet can show a live total.
  Money get _base {
    final line = _targetLineKey == null
        ? null
        : widget.ticket.lines.where((l) => l.key == _targetLineKey).firstOrNull;
    if (line != null) return line.lineTotal;

    final totals = widget.ticket.totals;
    return totals.net;
  }

  /// Price the current selection without applying it, for the live total.
  Money? get _preview {
    final selected = _selected;
    if (selected != null) return selected.amountOn(_base);

    final typed = _typedValue;
    if (typed == null) return null;
    final raw = _customKind == DiscountKind.percentage
        ? _base.percentBp(typed)
        : Money(typed, currency: _base.currency, exponent: _base.exponent);
    return raw.minor > _base.minor ? _base : raw;
  }

  /// The typed figure: basis points for a percentage, minor units for an
  /// amount. Null when the box is empty or does not hold a number.
  int? get _typedValue {
    final text = _value.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || parsed <= 0) return null;
    return _customKind == DiscountKind.percentage
        ? (parsed * 100).round()
        : (parsed * 100).round();
  }

  bool get _canApply => _selected != null || _typedValue != null;

  /// Apply, and turn a limit refusal into a manager standing at the till.
  Future<void> _apply() async {
    if (!_canApply || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final staff = ref.read(signedInStaffProvider);
    final approver = widget.preApprovedBy;

    // Already approved at the door, so no ceiling and no second prompt.
    final limit = approver != null
        ? null
        : await ref.read(discountLimitProvider.future);
    if (!mounted) return;

    var result = _attempt(
      limit: limit,
      appliedBy: staff?.id ?? approver?.id ?? 0,
      approvedByName: approver?.name,
      approvedByStaffId: approver?.id,
    );

    if (result.refusal is DiscountAboveLimit) {
      final refusal = result.refusal! as DiscountAboveLimit;
      final approved = await _askManager(refusal);
      if (!mounted) return;
      if (approved == null) {
        setState(() => _busy = false);
        return;
      }
      // Retried with **no ceiling at all** — that is what "lent for this one
      // action" means — and carrying the approver onto the record.
      result = _attempt(
        limit: null,
        appliedBy: staff?.id ?? 0,
        approvedByName: approved.approver.name,
        approvedByStaffId: approved.approver.id,
        reasonId: approved.reason?.reasonId,
        note: approved.reason?.note,
      );
    }

    if (!mounted) return;
    if (result.isOk) {
      Navigator.of(context).pop(result.ticket);
      return;
    }
    setState(() {
      _busy = false;
      _error = _explain(context.strings, result.refusal);
    });
  }

  TicketResult _attempt({
    required DiscountLimit? limit,
    required int appliedBy,
    String? approvedByName,
    int? approvedByStaffId,
    int? reasonId,
    String? note,
  }) {
    final now = DateTime.now();
    final selected = _selected;
    final lineKey = _targetLineKey;

    if (selected != null) {
      return lineKey == null
          ? TicketEngine.applyOrderDiscount(
              widget.ticket,
              selected,
              now: now,
              appliedBy: appliedBy,
              limit: limit,
              reasonId: reasonId,
              note: note,
              approvedByName: approvedByName,
              approvedByStaffId: approvedByStaffId,
            )
          : TicketEngine.applyLineDiscount(
              widget.ticket,
              lineKey,
              selected,
              now: now,
              appliedBy: appliedBy,
              limit: limit,
              reasonId: reasonId,
              note: note,
              approvedByName: approvedByName,
              approvedByStaffId: approvedByStaffId,
            );
    }

    final typed = _typedValue!;
    return TicketEngine.applyCustomDiscount(
      widget.ticket,
      name: context.strings.discountApprovalAct(_valueLabel()),
      kind: _customKind,
      valueBp: _customKind == DiscountKind.percentage ? typed : null,
      valueMinor: _customKind == DiscountKind.fixed
          ? Money(typed, currency: _base.currency, exponent: _base.exponent)
          : null,
      lineKey: lineKey,
      appliedBy: appliedBy,
      limit: limit,
      reasonId: reasonId,
      note: note,
      approvedByName: approvedByName,
      approvedByStaffId: approvedByStaffId,
    );
  }

  Future<ApprovalOutcome?> _askManager(DiscountAboveLimit refusal) async {
    final strings = context.strings;
    final reasons = await ref.read(
      reasonCodesProvider(ReasonScope.discount).future,
    );
    if (!mounted) return null;

    return SupervisorOverrideDialog.show(
      context,
      capability: PosCapability.discountApply,
      // The act in words. A supervisor approving "discount.apply" is approving
      // a string.
      action: strings.discountApprovalAct(_valueLabel()),
      requestedBy: ref.read(signedInStaffProvider)?.name,
      subjectLabel: _wholeOrder
          ? strings.discountWholeOrder.toUpperCase()
          : strings.discountThisLine.toUpperCase(),
      subject: widget.lineLabel ?? refusal.base.format(),
      // Both figures, so the supervisor is not left working out what the
      // cashier actually asked for.
      limitNote: strings.discountAboveLimitNote(
        _limitLabel(refusal.limit),
        _shareOf(refusal.requested, refusal.base),
      ),
      approveLabel: strings.discountApplyAction,
      reasons: reasons,
      reasonRequirement: SystemReasons.defaultRequirement(ReasonScope.discount),
    );
  }

  String _valueLabel() {
    final selected = _selected;
    if (selected != null) {
      return selected.displayName(context.strings.languageCode);
    }
    return _customKind == DiscountKind.percentage
        ? '${_value.text.trim()}%'
        : _preview?.format() ?? _value.text.trim();
  }

  String _limitLabel(DiscountLimit limit) {
    final bp = limit.maxBp;
    if (bp != null) return _percent(bp);
    return limit.maxAmount?.format() ?? '—';
  }

  /// Basis points as a percentage, without trailing noise: 1000 → 10, 1250 →
  /// 12.5. The same presentation the money pane uses, for the same reason.
  static String _percent(int bp) =>
      '${(bp / 100).toStringAsFixed(bp % 100 == 0 ? 0 : 1)}%';

  /// A discount as a share of what it came off, for the limit sentence.
  String _shareOf(Money amount, Money base) {
    if (base.minor <= 0) return amount.format();
    return _percent((amount.minor * 10000 / base.minor).round());
  }

  String _explain(AppStrings strings, TicketRefusal? refusal) =>
      switch (refusal) {
        DiscountNotOffered() => strings.discountNotApplicable,
        DiscountRequiresCustomer() => strings.discountNeedsCustomer,
        AlreadyDiscounted() => strings.discountAlreadyOn,
        NothingToDiscount() => strings.discountNothingToDiscount,
        LineNotOnTicket() => strings.discountNotApplicable,
        _ => strings.discountNotApplicable,
      };

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final offered = ref.watch(discountsProvider).valueOrNull ?? const [];
    final now = DateTime.now();

    // Only what is actually on offer, for this scope, right now. A list that
    // showed expired promotions would make the cashier the one who has to know
    // which are live.
    final applicable = offered
        .where(
          (d) =>
              d.isLiveAt(now) &&
              d.scope ==
                  (_wholeOrder ? DiscountScope.order : DiscountScope.item) &&
              d.targets.allowsOrderType(widget.ticket.orderType),
        )
        .toList();

    return Dialog(
      backgroundColor: palette.surface,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: Border.all(color: palette.lineStrong, width: 2),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
          const SingleActivator(LogicalKeyboardKey.enter): _apply,
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PosSize.dialogReason),
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
                      MicroLabel(strings.discountPresets),
                      const SizedBox(height: PosSpace.sm),
                      if (applicable.isEmpty)
                        Text(
                          strings.discountNoneOffered,
                          style: PosText.ui(
                            size: 13,
                            color: palette.muted,
                            height: 1.55,
                          ),
                        )
                      else
                        _presets(applicable, palette),
                      const SizedBox(height: PosSpace.s18),
                      MicroLabel(strings.discountCustom),
                      const SizedBox(height: PosSpace.sm),
                      _custom(strings, palette),
                      const SizedBox(height: PosSpace.s18),
                      _newTotal(strings, palette),
                      if (_error != null) ...[
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.discountTitle,
          style: PosText.panelTitle(color: palette.inkWarm),
        ),
        // Only offered when there is a line to aim at. A ticket with nothing
        // selected has one honest answer and should not be asked the question.
        if (widget.lineKey != null) ...[
          const SizedBox(height: PosSpace.md),
          Row(
            children: [
              Expanded(
                child: _scopeTab(
                  palette,
                  strings.discountThisLine,
                  selected: !_wholeOrder,
                  onTap: () => setState(() {
                    _wholeOrder = false;
                    _selected = null;
                  }),
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: _scopeTab(
                  palette,
                  strings.discountWholeOrder,
                  selected: _wholeOrder,
                  onTap: () => setState(() {
                    _wholeOrder = true;
                    _selected = null;
                  }),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _scopeTab(
    PosPalette palette,
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => Material(
    color: selected ? palette.accentSoft : palette.page,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: PosSize.minTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? palette.accent : palette.lineStrong,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: PosText.ui(
            size: 13.5,
            weight: FontWeight.w600,
            color: palette.inkWarm,
          ),
        ),
      ),
    ),
  );

  Widget _presets(List<Discount> discounts, PosPalette palette) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final discount in discounts)
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Material(
            color: _selected?.id == discount.id
                ? palette.accentSoft
                : palette.surface,
            child: InkWell(
              onTap: () => setState(() {
                _selected = _selected?.id == discount.id ? null : discount;
                if (_selected != null) {
                  _value.clear();
                }
                _error = null;
              }),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: PosSize.minTouchTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: PosSpace.s14,
                  vertical: PosSpace.s10,
                ),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    top: BorderSide(color: palette.line),
                    bottom: BorderSide(color: palette.line),
                    end: BorderSide(color: palette.line),
                    start: BorderSide(
                      color: _selected?.id == discount.id
                          ? palette.accent
                          : palette.line,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        discount.displayName(context.strings.languageCode),
                        style: PosText.ui(
                          size: 14,
                          weight: FontWeight.w500,
                          color: palette.inkWarm,
                        ),
                      ),
                    ),
                    MonoAmount(
                      discount.amountOn(_base),
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: palette.accentPressed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _custom(AppStrings strings, PosPalette palette) => Row(
    children: [
      _kindTab(palette, strings.discountPercent, kind: DiscountKind.percentage),
      const SizedBox(width: 1),
      _kindTab(palette, strings.discountAmount, kind: DiscountKind.fixed),
      const SizedBox(width: PosSpace.md),
      Expanded(
        child: SizedBox(
          height: PosSize.minTouchTarget,
          child: TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textDirection: TextDirection.ltr,
            style: PosText.mono(size: 16, color: palette.ink),
            onChanged: (_) => setState(() {
              _selected = null;
              _error = null;
            }),
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.page,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: PosSpace.md,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _kindTab(
    PosPalette palette,
    String label, {
    required DiscountKind kind,
  }) {
    final selected = _customKind == kind && _selected == null;
    return Material(
      color: selected ? palette.accentSoft : palette.page,
      child: InkWell(
        onTap: () => setState(() {
          _customKind = kind;
          _selected = null;
          _error = null;
        }),
        child: Container(
          height: PosSize.minTouchTarget,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? palette.accent : palette.lineStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: PosText.ui(
              size: 13,
              weight: FontWeight.w600,
              color: palette.inkWarm,
            ),
          ),
        ),
      ),
    );
  }

  /// What the bill comes to if this is applied. Live, because the number the
  /// customer will be told is the one the cashier is deciding about.
  Widget _newTotal(AppStrings strings, PosPalette palette) {
    final preview = _preview;
    final totals = widget.ticket.totals;
    final after = preview == null
        ? totals.total
        : (totals.net - preview).clampToZero();

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: PosSpace.md,
        horizontal: PosSpace.s14,
      ),
      decoration: BoxDecoration(
        color: palette.page,
        border: Border.fromBorderSide(palette.resting),
      ),
      child: Row(
        children: [
          MicroLabel(strings.discountNewTotal),
          const Spacer(),
          if (preview != null) ...[
            MonoAmount(
              -preview,
              size: 13.5,
              weight: FontWeight.w600,
              color: palette.danger,
            ),
            const SizedBox(width: PosSpace.md),
          ],
          MonoAmount(
            preview == null ? totals.total : after,
            size: 20,
            weight: FontWeight.w600,
            color: palette.inkWarm,
          ),
        ],
      ),
    );
  }

  Widget _footer(AppStrings strings, PosPalette palette) {
    final existing =
        widget.ticket.discountOnLine(_targetLineKey ?? '') ??
        (_wholeOrder ? widget.ticket.orderDiscounts.firstOrNull : null);

    return Container(
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
            label: existing != null ? strings.discountRemove : strings.cancel,
            height: PosSize.secondaryAction,
            border: Border.fromBorderSide(palette.resting),
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pop(
                    existing == null
                        ? null
                        : TicketEngine.removeDiscount(
                            widget.ticket,
                            lineKey: _targetLineKey,
                          ),
                  ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: PosButton(
              label: strings.discountApplyAction,
              height: PosSize.primaryCta,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              background: _canApply ? palette.accent : palette.page,
              foreground: _canApply ? palette.ink : palette.muted,
              border: Border.fromBorderSide(
                _canApply
                    ? BorderSide(color: palette.accentPressed)
                    : palette.resting,
              ),
              onPressed: _canApply && !_busy ? _apply : null,
            ),
          ),
        ],
      ),
    );
  }
}
