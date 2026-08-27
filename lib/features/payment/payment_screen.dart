import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money/money.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/ticket.dart';
import '../receipt/receipt_dialog.dart';

/// A payment method offered at the till.
///
/// In production these come from `tender_types` via `GET /api/pos/config`
/// (POS-BE-013, still PROPOSED) — as data, so v1 can record a card taken on a
/// standalone bank terminal without pretending to be a processor.
class _Method {
  const _Method(this.id, this.label);
  final int id;
  final String label;
}

const _methods = [
  _Method(1, 'Cash'),
  _Method(2, 'Card'),
  _Method(3, 'Wallet · InstaPay'),
  _Method(4, 'On account'),
];

/// Take one or many tenders until the balance clears.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierColor: PosColors.scrim,
        builder: (_) => const PaymentScreen(),
      );

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  int _methodId = 1;
  String _entry = '';

  Money? _parsedEntry(Ticket ticket) => _entry.isEmpty
      ? null // empty entry means "the whole remaining due"
      : Money.tryParse(_entry, currency: ticket.currency, exponent: ticket.exponent);

  void _digit(String value) => setState(() => _entry += value);
  void _clear() => setState(() => _entry = '');

  void _quickCash(int major, Ticket ticket) => setState(
        () => _entry = Money(major * 100, currency: ticket.currency).format(),
      );

  Future<void> _take(Ticket ticket) async {
    final controller = ref.read(ticketProvider.notifier);
    final ok = controller.addTender(
      typeId: _methodId,
      label: _methods.firstWhere((m) => m.id == _methodId).label,
      amount: _parsedEntry(ticket),
    );

    if (!ok) {
      posToast(context, 'Enter an amount above zero.');
      return;
    }

    setState(() => _entry = '');

    final updated = ref.read(ticketProvider);
    if (!updated.totals.isSettled) return;

    // Settled — hand off to the receipt, which is what starts the next sale.
    final result = await ref.read(ordersRepositoryProvider).submit(updated);
    if (!mounted) return;

    ref.read(posUiProvider.notifier).noteQueued(
          ref.read(posUiProvider).queuedCount + (result.queued ? 1 : 0),
        );

    Navigator.of(context).pop();
    await ReceiptDialog.show(context, ticket: updated, result: result);
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider);
    final totals = ticket.totals;

    return Dialog(
      backgroundColor: PosColors.surface,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: const RoundedRectangleBorder(
        side: PosBorders.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(ticket),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _left(ticket, totals)),
                  SizedBox(width: 400, child: _right(ticket, totals)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Ticket ticket) => Container(
        height: PosSize.secondaryAction,
        color: PosColors.ink,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
        child: Row(
          children: [
            PosButton(
              label: '← Back to ticket',
              height: 36,
              background: PosColors.shellCard,
              foreground: PosColors.shellText,
              fontSize: 12.5,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: PosSpace.md),
            Text(
              'Payment',
              style: PosText.ui(size: 15, weight: FontWeight.w800, color: Colors.white),
            ),
            const Spacer(),
            Text(
              [
                ticket.orderType.label,
                if (ticket.tableLabel != null) ticket.tableLabel!,
                '${ticket.lines.length} lines',
              ].join(' · '),
              style: PosText.mono(size: 11.5, color: PosColors.shellMuted),
            ),
          ],
        ),
      );

  Widget _left(Ticket ticket, TicketTotals totals) => Container(
        color: PosColors.page,
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dueCard(ticket, totals),
            const SizedBox(height: PosSpace.s14),
            Expanded(child: _tendersCard(ticket)),
          ],
        ),
      );

  Widget _dueCard(Ticket ticket, TicketTotals totals) => PosSurface(
        border: const Border.fromBorderSide(PosBorders.emphasis),
        padding: const EdgeInsets.all(PosSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MicroLabel(ticket.tenders.isEmpty ? 'Amount due' : 'Remaining due'),
                const Spacer(),
                Text(
                  'Total ${totals.total.format()}',
                  style: PosText.mono(size: 12, color: PosColors.muted),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.sm),
            Text(totals.due.format(), style: PosText.bigNumeric()),
            const SizedBox(height: PosSpace.md),
            _progress(totals),
            const SizedBox(height: PosSpace.sm),
            Text(
              '${totals.paid.format()} paid of ${totals.total.format()} · '
              '${ticket.tenders.length} tender${ticket.tenders.length == 1 ? '' : 's'}',
              style: PosText.ui(size: 12, color: PosColors.muted),
            ),
          ],
        ),
      );

  Widget _progress(TicketTotals totals) {
    final ratio = totals.total.isZero
        ? 0.0
        : (totals.paid.minor / totals.total.minor).clamp(0.0, 1.0);

    return SizedBox(
      height: 8,
      child: Row(children: [
        Expanded(flex: (ratio * 1000).round(), child: const ColoredBox(color: PosColors.ok)),
        Expanded(
          flex: 1000 - (ratio * 1000).round(),
          child: const ColoredBox(color: PosColors.line),
        ),
      ]),
    );
  }

  Widget _tendersCard(Ticket ticket) => PosSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(PosSpace.md),
              child: MicroLabel('Tenders'),
            ),
            if (ticket.tenders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                child: Text(
                  'No tender yet — pick a method, key an amount or tap a '
                  'quick-cash button.',
                  style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: ticket.tenders.length,
                  itemBuilder: (context, index) => _tenderRow(ticket, index),
                ),
              ),
          ],
        ),
      );

  Widget _tenderRow(Ticket ticket, int index) {
    final tender = ticket.tenders[index];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.md,
      ),
      decoration: const BoxDecoration(border: Border(top: PosBorders.hairline)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tender.label,
              style: PosText.ui(size: 13, weight: FontWeight.w600),
            ),
          ),
          Text(tender.amount.format(), style: PosText.mono(size: 15)),
          const SizedBox(width: PosSpace.md),
          InkWell(
            onTap: () => ref.read(ticketProvider.notifier).removeTenderAt(index),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border.fromBorderSide(PosBorders.hairline),
              ),
              child: Text('×', style: PosText.ui(size: 16, color: PosColors.danger)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _right(Ticket ticket, TicketTotals totals) => Container(
        decoration: const BoxDecoration(
          color: PosColors.surface,
          border: Border(left: PosBorders.emphasis),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _methodGrid(),
            _amountBlock(ticket, totals),
            Expanded(child: _keypad()),
            PosButton(
              label: 'TAKE PAYMENT',
              height: 72,
              alignLeft: true,
              background: PosColors.ok,
              foreground: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              trailing: Text(
                (_parsedEntry(ticket) ?? totals.due).format(),
                style: PosText.mono(size: 16, weight: FontWeight.w600, color: Colors.white),
              ),
              onPressed: () => _take(ticket),
            ),
          ],
        ),
      );

  Widget _methodGrid() => Container(
        color: PosColors.lineStrong,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          childAspectRatio: 200 / 64,
          children: [
            for (final method in _methods)
              Material(
                color: method.id == _methodId ? PosColors.ink : PosColors.surface,
                child: InkWell(
                  onTap: () => setState(() => _methodId = method.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        method.label,
                        style: PosText.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: method.id == _methodId ? Colors.white : PosColors.inkWarm,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _amountBlock(Ticket ticket, TicketTotals totals) => Container(
        padding: const EdgeInsets.all(PosSpace.md),
        decoration: const BoxDecoration(
          border: Border(top: PosBorders.emphasis, bottom: PosBorders.hairline),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const MicroLabel('Amount'),
                const Spacer(),
                Text(
                  _entry.isEmpty ? totals.due.format() : _entry,
                  style: PosText.mono(
                    size: 22,
                    color: _entry.isEmpty ? PosColors.muted : PosColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.md),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: PosSpace.sm,
              crossAxisSpacing: PosSpace.sm,
              childAspectRatio: 120 / PosSize.minTouchTarget,
              children: [
                for (final amount in [50, 100, 200, 500, 1000])
                  PosButton(
                    label: '$amount',
                    background: PosColors.page,
                    border: const Border.fromBorderSide(PosBorders.resting),
                    onPressed: () => _quickCash(amount, ticket),
                  ),
                PosButton(
                  label: 'Exact',
                  background: PosColors.page,
                  border: const Border.fromBorderSide(PosBorders.resting),
                  onPressed: () => setState(() => _entry = totals.due.format()),
                ),
              ],
            ),
          ],
        ),
      );

  /// The keypad fills the remaining height as a flex grid rather than a
  /// GridView. A GridView scrolls, and a scrolled keypad silently hides a key —
  /// which is how a cashier ends up unable to find CLR mid-transaction.
  Widget _keypad() {
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['0', '00', 'CLR'],
    ];

    return Container(
      color: PosColors.line,
      padding: const EdgeInsets.only(top: 1),
      child: Column(
        children: [
          for (final row in rows)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Row(
                  children: [
                    for (final key in row) ...[
                      Expanded(child: _key(key)),
                      if (key != row.last) const SizedBox(width: 1),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(String key) {
    final isClear = key == 'CLR';

    return Material(
      color: isClear ? PosColors.page : PosColors.surface,
      child: InkWell(
        onTap: () => isClear ? _clear() : _digit(key),
        child: Center(
          child: Text(
            key,
            style: isClear
                ? PosText.ui(size: 13, color: PosColors.chipText)
                : PosText.mono(size: 20, weight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
