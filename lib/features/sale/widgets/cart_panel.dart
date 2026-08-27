import 'package:flutter/material.dart';

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

    return Container(
      width: PosSize.cartPanel,
      decoration: const BoxDecoration(
        color: PosColors.shell,
        border: Border(left: PosBorders.emphasis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(child: ticket.isEmpty ? _emptyState() : _lines()),
          _totals(totals),
          _actions(totals),
        ],
      ),
    );
  }

  String get _title {
    if (ticket.isSeated) {
      final guests = ticket.guestCount;
      return '${ticket.tableLabel}${guests == null ? '' : ' · $guests guests'}';
    }
    if (ticket.orderType == OrderType.dineIn) return 'No table yet';
    return '${ticket.orderType.label} · walk-in';
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.s14,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: PosBorders.shell),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    overflow: TextOverflow.ellipsis,
                    style: PosText.panelTitle(color: PosColors.shellText),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'OPEN · ${cashierName.toUpperCase()} · ${online ? 'LIVE' : 'OFFLINE'}',
                    overflow: TextOverflow.ellipsis,
                    style: PosText.mono(size: 11.5, color: PosColors.shellMuted),
                  ),
                ],
              ),
            ),
            if (ticket.isSeated && onChangeTable != null)
              PosButton(
                label: 'Change table',
                height: 38,
                background: PosColors.shellCard,
                foreground: PosColors.shellText,
                fontSize: 12.5,
                onPressed: onChangeTable,
              ),
          ],
        ),
      );

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.xl,
        ),
        child: Text(
          'Ticket is empty. Tap a product, or press F2 and type to search. '
          'Items with modifiers open a sheet first.',
          style: PosText.ui(size: 13, color: PosColors.shellMuted, height: 1.6),
        ),
      );

  Widget _lines() {
    final sent = ticket.sentLines;
    final draft = ticket.draftLines;

    return ListView(
      children: [
        if (sent.isNotEmpty) ...[
          _sectionBar('Already sent · ${sent.length} lines', PosColors.shellMuted),
          for (final line in sent) _LineRow(line: line, dimmed: true),
          _sectionBar('New round', PosColors.accent),
        ],
        for (final line in draft)
          _LineRow(
            line: line,
            onQuantityChanged: (delta) => onQuantityChanged(line.key, delta),
          ),
      ],
    );
  }

  Widget _sectionBar(String label, Color color) => Container(
        width: double.infinity,
        color: PosColors.shellRow,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg, vertical: 9),
        child: MicroLabel(label, color: color),
      );

  Widget _totals(TicketTotals totals) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.s14,
        ),
        decoration: const BoxDecoration(border: Border(top: PosBorders.accent)),
        child: Column(
          children: [
            _totalRow('Subtotal', totals.subtotal.format()),
            // Shown whenever service applies to this order type, even at zero:
            // the design lists all three rows, and a row that appears only once
            // the ticket is non-empty makes the totals block jump as items land.
            if (ticket.taxConfig.appliesServiceTo(ticket.orderType))
              _totalRow(
                'Service ${(ticket.taxConfig.serviceBp / 100).toStringAsFixed(0)}%',
                totals.service.format(),
              ),
            _totalRow(
              'VAT ${(ticket.taxConfig.vatBp / 100).toStringAsFixed(0)}%',
              totals.vat.format(),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: PosSpace.sm),
              child: ColoredBox(color: PosColors.shellLine, child: SizedBox(height: 1, width: double.infinity)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'TOTAL',
                  style: PosText.ui(size: 17, weight: FontWeight.w800, color: PosColors.shellText),
                ),
                const Spacer(),
                Text(totals.total.format(), style: PosText.displayTotal()),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 4),
                  child: Text(
                    ticket.currency,
                    style: PosText.ui(size: 14, color: PosColors.shellMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _totalRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.xs),
        child: Row(
          children: [
            Text(label, style: PosText.ui(size: 13, color: PosColors.shellText)),
            const Spacer(),
            Text(value, style: PosText.mono(size: 13, color: PosColors.shellText)),
          ],
        ),
      );

  Widget _actions(TicketTotals totals) {
    final hasAnything = !ticket.isEmpty;
    final ctaLabel = ticket.isSeated ? 'CLOSE TABLE' : 'CHARGE';

    return Column(
      children: [
        Container(
          color: PosColors.shellLine,
          child: Row(
            children: [
              Expanded(
                child: PosButton(
                  label: ticket.isSeated ? 'Send round  F4' : 'Park  F4',
                  height: PosSize.secondaryAction,
                  background: PosColors.shell,
                  foreground: PosColors.shellText,
                  onPressed: ticket.hasDraft ? onSendRound : null,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: PosButton(
                  label: 'Void ticket',
                  height: PosSize.secondaryAction,
                  background: PosColors.shell,
                  foreground: PosColors.offlinePillText,
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
          background: hasAnything ? PosColors.accent : const Color(0xFF4A3F31),
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
  const _LineRow({required this.line, this.dimmed = false, this.onQuantityChanged});

  final TicketLine line;
  final bool dimmed;
  final ValueChanged<int>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.md,
      ),
      decoration: const BoxDecoration(border: Border(bottom: PosBorders.shell)),
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
                color: dimmed ? PosColors.shellMuted : PosColors.accent,
              ),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.nameEn,
                  style: PosText.ui(
                    size: 14.5,
                    weight: FontWeight.w600,
                    color: PosColors.shellText,
                  ),
                ),
                if (line.modifiers.isNotEmpty)
                  Text(
                    line.modifierSummary('en'),
                    style: PosText.ui(
                      size: 12,
                      color: PosColors.shellLineMeta,
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
                  color: PosColors.shellText,
                ),
              ),
              if (onQuantityChanged != null) ...[
                const SizedBox(height: PosSpace.sm),
                Row(children: [
                  _stepper('−', () => onQuantityChanged!(-1)),
                  const SizedBox(width: 2),
                  _stepper('+', () => onQuantityChanged!(1)),
                ]),
              ],
            ],
          ),
        ],
      ),
    );

    return dimmed ? Opacity(opacity: 0.62, child: row) : row;
  }

  Widget _stepper(String glyph, VoidCallback onTap) => Material(
        color: PosColors.shellCard,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Text(
                glyph,
                style: PosText.ui(size: 16, color: PosColors.shellText),
              ),
            ),
          ),
        ),
      );
}
