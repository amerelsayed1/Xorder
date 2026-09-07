import 'package:flutter/material.dart';

import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
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
  });

  final Ticket ticket;
  final String cashierName;
  final bool online;
  final void Function(String lineKey, int delta) onQuantityChanged;
  final VoidCallback onSendRound;
  final VoidCallback onVoid;
  final VoidCallback onCharge;
  final VoidCallback? onChangeTable;

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
            child: ticket.isEmpty ? _emptyState(strings, pos: context.pos) : _lines(strings, pos: context.pos),
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
          for (final line in sent) _LineRow(line: line, dimmed: true),
          _sectionBar(s.newRound, pos.accent, pos: pos),
        ],
        for (final line in draft)
          _LineRow(
            line: line,
            onQuantityChanged: (delta) => onQuantityChanged(line.key, delta),
          ),
      ],
    );
  }

  Widget _sectionBar(String label, Color color, {required PosPalette pos}) => Container(
    width: double.infinity,
    color: pos.shellRow,
    padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg, vertical: 9),
    child: MicroLabel(label, color: color),
  );

  Widget _totals(AppStrings s, TicketTotals totals, {required PosPalette pos}) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.s14,
    ),
    decoration: BoxDecoration(border: Border(top: pos.accentBorder)),
    child: Column(
      children: [
        _totalRow(s.subtotal, totals.subtotal.format(), pos: pos),
        // Shown whenever service applies to this order type, even at zero:
        // the design lists all three rows, and a row that appears only once
        // the ticket is non-empty makes the totals block jump as items land.
        if (ticket.taxConfig.appliesServiceTo(ticket.orderType))
          _totalRow(
            s.servicePercent(
              (ticket.taxConfig.serviceBp / 100).toStringAsFixed(0),
            ),
            totals.service.format(),
          pos: pos),
        _totalRow(
          s.vatPercent((ticket.taxConfig.vatBp / 100).toStringAsFixed(0)),
          totals.vat.format(),
        pos: pos),
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
            Text(
              s.totalCaps,
              style: PosText.ui(
                size: 17,
                weight: FontWeight.w800,
                color: pos.shellText,
              ),
            ),
            const Spacer(),
            Text(totals.total.format(), style: PosText.displayTotal(color: pos.accent)),
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4),
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

  Widget _totalRow(String label, String value, {required PosPalette pos}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PosSpace.xs),
    child: Row(
      children: [
        Text(label, style: PosText.ui(size: 13, color: pos.shellText)),
        const Spacer(),
        Text(value, style: PosText.mono(size: 13, color: pos.shellText)),
      ],
    ),
  );

  Widget _actions(AppStrings s, TicketTotals totals, {required PosPalette pos}) {
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
    this.onQuantityChanged,
  });

  final TicketLine line;
  final bool dimmed;
  final ValueChanged<int>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final language = context.strings.languageCode;

    final row = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.md,
      ),
      decoration: BoxDecoration(border: Border(bottom: context.pos.shellBorder)),
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
                Text(
                  line.product.displayName(language),
                  style: PosText.ui(
                    size: 14.5,
                    weight: FontWeight.w600,
                    color: context.pos.shellText,
                  ),
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
              ],
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                line.lineTotal.format(),
                style: PosText.mono(
                  size: 15,
                  weight: FontWeight.w600,
                  color: context.pos.shellText,
                ),
              ),
              if (onQuantityChanged != null) ...[
                const SizedBox(height: PosSpace.sm),
                Row(
                  children: [
                    _stepper('−', () => onQuantityChanged!(-1), pos: context.pos),
                    const SizedBox(width: 2),
                    _stepper('+', () => onQuantityChanged!(1), pos: context.pos),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return dimmed ? Opacity(opacity: 0.62, child: row) : row;
  }

  Widget _stepper(String glyph, VoidCallback onTap, {required PosPalette pos}) => Material(
    color: pos.shellCard,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(
            glyph,
            style: PosText.ui(size: 16, color: pos.shellText),
          ),
        ),
      ),
    ),
  );
}
