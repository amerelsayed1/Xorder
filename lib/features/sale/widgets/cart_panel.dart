import 'package:flutter/material.dart';

import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/discount.dart';
import '../../../domain/models/ticket.dart';

/// 378px cart panel on shell ground with a 2px ink left border.
class CartPanel extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.ticket,
    required this.cashierName,
    required this.online,
    required this.onQuantityChanged,
    required this.onSendRound,
    required this.onVoid,
    required this.onCharge,
    this.onChangeTable,
    this.selectedLineKey,
    this.onSelectLine,
  });

  final Ticket ticket;
  final String cashierName;
  final bool online;
  final void Function(String lineKey, int delta) onQuantityChanged;
  final VoidCallback onSendRound;
  final VoidCallback onVoid;
  final VoidCallback onCharge;
  final VoidCallback? onChangeTable;

  /// The line the cashier is working on, if any.
  ///
  /// Selection exists so a line-level act — discount today, void and price
  /// override next — has something to aim at. It is deliberately **not**
  /// persisted with the ticket: it is where a person's attention is, not a
  /// property of the sale, and a resumed table should not come back with
  /// somebody's cursor on it.
  final String? selectedLineKey;
  final ValueChanged<String>? onSelectLine;

  @override
  Widget build(BuildContext context) {
    final totals = ticket.totals;
    final strings = context.strings;

    return Container(
      width: PosSize.cartPanel,
      decoration: BoxDecoration(
        color: context.pos.shell,
        border: Border(left: context.pos.emphasis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(strings, pos: context.pos),
          Expanded(
            child: ticket.isEmpty
                ? _emptyState(strings, pos: context.pos)
                : _lines(strings, pos: context.pos),
          ),
          _totals(strings, totals, pos: context.pos),
          _actions(strings, totals, pos: context.pos),
        ],
      ),
    );
  }

  String _title(AppStrings s) {
    if (ticket.isSeated) {
      return s.seatedTable(ticket.tableLabel!, ticket.guestCount);
    }
    if (ticket.orderType == OrderType.dineIn) return s.noTableYet;
    return s.walkIn(ticket.orderType.label(s));
  }

  Widget _header(AppStrings s, {required PosPalette pos}) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.s14,
    ),
    decoration: BoxDecoration(border: Border(bottom: pos.shellBorder)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title(s),
                overflow: TextOverflow.ellipsis,
                style: PosText.panelTitle(color: pos.shellText),
              ),
              const SizedBox(height: 2),
              Text(
                s.cartStatusLine(cashierName, online),
                overflow: TextOverflow.ellipsis,
                style: PosText.mono(size: 11.5, color: pos.shellMuted),
              ),
            ],
          ),
        ),
        if (ticket.isSeated && onChangeTable != null)
          PosButton(
            label: s.changeTable,
            height: 38,
            background: pos.shellCard,
            foreground: pos.shellText,
            fontSize: 12.5,
            onPressed: onChangeTable,
          ),
      ],
    ),
  );

  Widget _emptyState(AppStrings s, {required PosPalette pos}) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.xl,
    ),
    child: Text(
      s.cartEmptyHelp,
      style: PosText.ui(size: 13, color: pos.shellMuted, height: 1.6),
    ),
  );

  Widget _lines(AppStrings s, {required PosPalette pos}) {
    final sent = ticket.sentLines;
    final draft = ticket.draftLines;

    return ListView(
      children: [
        if (sent.isNotEmpty) ...[
          _sectionBar(s.alreadySent(sent.length), pos.shellMuted, pos: pos),
          for (final line in sent)
            _LineRow(
              line: line,
              dimmed: true,
              discount: ticket.discountOnLine(line.key),
              isSelected: line.key == selectedLineKey,
              onSelect: onSelectLine == null
                  ? null
                  : () => onSelectLine!(line.key),
            ),
          _sectionBar(s.newRound, pos.accent, pos: pos),
        ],
        for (final line in draft)
          _LineRow(
            line: line,
            discount: ticket.discountOnLine(line.key),
            isSelected: line.key == selectedLineKey,
            onSelect: onSelectLine == null
                ? null
                : () => onSelectLine!(line.key),
            onQuantityChanged: (delta) => onQuantityChanged(line.key, delta),
          ),
      ],
    );
  }

  Widget _sectionBar(String label, Color color, {required PosPalette pos}) =>
      Container(
        width: double.infinity,
        color: pos.shellRow,
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: 9,
        ),
        child: MicroLabel(label, color: color),
      );

  Widget _totals(
    AppStrings s,
    TicketTotals totals, {
    required PosPalette pos,
  }) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.s14,
    ),
    decoration: BoxDecoration(border: Border(top: pos.accentBorder)),
    child: Column(
      children: [
        _totalRow(s.subtotal, totals.subtotal.format(), pos: pos),
        // **Order-level discounts live here, never inside a line.** A discount
        // that came off the whole bill has no line to belong to, and drawing it
        // under one would be a claim about what it discounted.
        for (final discount in ticket.orderDiscounts)
          _totalRow(
            discount.nameSnapshot,
            '-${discount.amount.format()}',
            pos: pos,
            emphasis: pos.accent,
          ),
        // Shown whenever service applies to this order type, even at zero:
        // the design lists all three rows, and a row that appears only once
        // the ticket is non-empty makes the totals block jump as items land.
        if (ticket.taxConfig.appliesServiceTo(ticket.orderType))
          _totalRow(
            s.servicePercent(
              (ticket.taxConfig.serviceBp / 100).toStringAsFixed(0),
            ),
            totals.service.format(),
            pos: pos,
          ),
        _totalRow(
          s.vatPercent((ticket.taxConfig.vatBp / 100).toStringAsFixed(0)),
          totals.vat.format(),
          pos: pos,
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: PosSpace.sm),
          child: ColoredBox(
            color: pos.shellLine,
            child: SizedBox(height: 1, width: double.infinity),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Flexible, because the word for "total" is longer in some
            // languages than in English and the figure beside it is the
            // largest type in the product. The label yields; the number never
            // does.
            Flexible(
              child: Text(
                s.totalCaps,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(
                  size: 17,
                  weight: FontWeight.w800,
                  color: pos.shellText,
                ),
              ),
            ),
            const Spacer(),
            Text(
              totals.total.format(),
              style: PosText.displayTotal(color: pos.accent),
            ),
            Padding(
              // Directional: the currency sits after the figure, which is the
              // right of it in English and the left of it in Arabic.
              padding: const EdgeInsetsDirectional.only(bottom: 3, start: 4),
              child: Text(
                ticket.currency,
                style: PosText.ui(size: 14, color: pos.shellMuted),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _totalRow(
    String label,
    String value, {
    required PosPalette pos,
    Color? emphasis,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PosSpace.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 13, color: emphasis ?? pos.shellText),
          ),
        ),
        const SizedBox(width: PosSpace.sm),
        // Directionality, not `MonoAmount`: the value arrives already
        // formatted — some of these rows are a rate, not an amount — and the
        // one guarantee that must hold either way is that it reads
        // left-to-right on an Arabic till.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            value,
            style: PosText.mono(size: 13, color: emphasis ?? pos.shellText),
          ),
        ),
      ],
    ),
  );

  Widget _actions(
    AppStrings s,
    TicketTotals totals, {
    required PosPalette pos,
  }) {
    final hasAnything = !ticket.isEmpty;
    final ctaLabel = ticket.isSeated ? s.closeTableCta : s.chargeCta;

    return Column(
      children: [
        Container(
          color: pos.shellLine,
          child: Row(
            children: [
              Expanded(
                child: PosButton(
                  label: ticket.isSeated ? s.sendRoundKey : s.parkKey,
                  height: PosSize.secondaryAction,
                  background: pos.shell,
                  foreground: pos.shellText,
                  onPressed: ticket.hasDraft ? onSendRound : null,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: PosButton(
                  label: s.voidTicket,
                  height: PosSize.secondaryAction,
                  background: pos.shell,
                  foreground: pos.offlinePillText,
                  onPressed: hasAnything ? onVoid : null,
                ),
              ),
            ],
          ),
        ),
        PosButton(
          label: '$ctaLabel  ${totals.total.format()}',
          height: PosSize.primaryCta,
          alignLeft: true,
          background: hasAnything ? pos.accent : pos.ctaDisabled,
          foreground: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
          trailing: const KeyChip('F9', onShell: true),
          onPressed: hasAnything ? onCharge : null,
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    this.dimmed = false,
    this.discount,
    this.isSelected = false,
    this.onSelect,
    this.onQuantityChanged,
  });

  final TicketLine line;
  final bool dimmed;

  /// What was taken off this line, if anything. Null for most lines.
  final AppliedDiscount? discount;

  final bool isSelected;
  final VoidCallback? onSelect;
  final ValueChanged<int>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final language = context.strings.languageCode;

    final row = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.md,
      ),
      decoration: BoxDecoration(
        color: isSelected ? context.pos.shellCard : null,
        border: BorderDirectional(
          bottom: context.pos.shellBorder,
          // Directional, so the selection mark sits on the leading edge in
          // both languages — and 2px, the one weight this system uses for
          // "this one", the same as a selected category or a selected reason.
          start: BorderSide(
            color: isSelected ? context.pos.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${line.quantity}×',
              style: PosText.mono(
                size: 15,
                weight: FontWeight.w600,
                color: dimmed ? context.pos.shellMuted : context.pos.accent,
              ),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        line.product.displayName(language),
                        overflow: TextOverflow.ellipsis,
                        style:
                            PosText.ui(
                              size: 14.5,
                              weight: FontWeight.w600,
                              color: line.isVoided
                                  ? context.pos.shellMuted
                                  : context.pos.shellText,
                            ).copyWith(
                              decoration: line.isVoided
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: context.pos.shellMuted,
                            ),
                      ),
                    ),
                    if (line.isVoided) ...[
                      const SizedBox(width: PosSpace.sm),
                      _VoidChip(),
                    ] else if (line.isRepriced) ...[
                      const SizedBox(width: PosSpace.sm),
                      const _RepricedChip(),
                    ],
                  ],
                ),
                if (line.modifiers.isNotEmpty)
                  Text(
                    line.modifierSummary(language),
                    style: PosText.ui(
                      size: 12,
                      color: context.pos.shellLineMeta,
                      height: 1.4,
                    ),
                  ),
                // Why it went. On the meta row rather than in a chip, because
                // it is a sentence a cashier reads aloud to a customer, not a
                // status somebody scans for.
                if (line.voided?.note != null)
                  Text(
                    line.voided!.note!,
                    style: PosText.ui(
                      size: 12,
                      color: context.pos.danger,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The menu price, struck through, above what is actually being
              // charged. It is the sentence a cashier reads to a customer —
              // "that was 50, it's 40" — and without it a repriced line is
              // just a line at an odd price that nobody can explain later.
              if (line.isRepriced && !line.isVoided)
                Text(
                  (line.menuUnitPrice * line.quantity).format(),
                  style:
                      PosText.mono(
                        size: 11.5,
                        color: context.pos.shellMuted,
                      ).copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: context.pos.shellMuted,
                      ),
                ),
              Text(
                line.lineTotal.format(),
                style:
                    PosText.mono(
                      size: 15,
                      weight: FontWeight.w600,
                      color: line.isVoided
                          ? context.pos.shellMuted
                          : line.isRepriced
                          ? context.pos.accent
                          : context.pos.shellText,
                    ).copyWith(
                      // Struck through, not removed. The price is what the customer
                      // is being shown they are NOT paying.
                      decoration: line.isVoided
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: context.pos.shellMuted,
                    ),
              ),
              if (onQuantityChanged != null && !line.isVoided) ...[
                const SizedBox(height: PosSpace.sm),
                Row(
                  children: [
                    _stepper(
                      '−',
                      () => onQuantityChanged!(-1),
                      pos: context.pos,
                    ),
                    const SizedBox(width: 2),
                    _stepper(
                      '+',
                      () => onQuantityChanged!(1),
                      pos: context.pos,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // A discount is a **child row of its line**, not a sibling. Drawing it as
    // its own line would make the ticket read as though something else was
    // sold; drawing it only in the totals would leave the cashier unable to
    // show a customer which item was reduced.
    final withDiscount = discount == null
        ? row
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [row, _discountRow(context, discount!)],
          );

    final selectable = onSelect == null
        ? withDiscount
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onSelect, child: withDiscount),
          );

    return dimmed ? Opacity(opacity: 0.62, child: selectable) : selectable;
  }

  /// The discount, named, with **who approved it** when somebody did.
  ///
  /// The approver's name is the point. A line reading "Discount 30%" invites
  /// the question the cashier cannot answer at the till; one reading "approved
  /// by Hana M." has already answered it, in front of the customer.
  Widget _discountRow(BuildContext context, AppliedDiscount discount) {
    final pos = context.pos;
    final label = discount.approvedByName == null
        ? discount.nameSnapshot
        : '${discount.nameSnapshot} · ${context.strings.approvedByShort(discount.approvedByName!)}';

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        PosSpace.s28,
        PosSpace.sm,
        PosSpace.lg,
        PosSpace.s10,
      ),
      decoration: BoxDecoration(
        border: BorderDirectional(
          bottom: pos.shellBorder,
          start: BorderSide(color: pos.accent, width: 2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: PosText.mono(size: 11, color: pos.shellMuted),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '-${discount.amount.format()}',
              style: PosText.mono(
                size: 13,
                weight: FontWeight.w600,
                color: pos.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper(
    String glyph,
    VoidCallback onTap, {
    required PosPalette pos,
  }) => Material(
    color: pos.shellCard,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(glyph, style: PosText.ui(size: 16, color: pos.shellText)),
        ),
      ),
    ),
  );
}

/// The mark that says this line is not being charged for.
/// Marks a line that is not being sold at the menu price.
///
/// Accent rather than danger: repricing is a decision somebody made on purpose,
/// not a loss. The void chip beside it is danger, and the two must not read as
/// the same kind of event.
class _RepricedChip extends StatelessWidget {
  const _RepricedChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: context.pos.accent.withValues(alpha: 0.6)),
    ),
    child: Text(
      context.strings.priceOverrideChip,
      style: PosText.mono(
        size: 9.5,
        weight: FontWeight.w600,
        color: context.pos.accent,
      ),
    ),
  );
}

class _VoidChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(border: Border.all(color: context.pos.danger)),
    child: Text(
      context.strings.lineVoidedChip,
      style: PosText.mono(
        size: 9.5,
        weight: FontWeight.w600,
        color: context.pos.danger,
        letterSpacing: 0.9,
      ),
    ),
  );
}
