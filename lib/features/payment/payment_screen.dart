import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money/money.dart';
import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/tender_method.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart' show SubmitOrderResult;

/// A payment method offered at the till.
///
/// In production these come from `tender_types` via `GET /api/pos/config`
/// (POS-BE-013, still PROPOSED) — as data, so v1 can record a card taken on a
/// standalone bank terminal without pretending to be a processor.
/// The keypad's clear key, by identity rather than by caption.
const _clearKey = 'CLR';

/// The tender types this till offers.
///
/// Lifted out of this file when refunds arrived: money going back has to offer
/// the same methods money came in on, and two lists of tender types is how a
/// till ends up refunding to a method it cannot take payment on. See
/// [TenderMethod].
const _methods = TenderMethod.seeded;

/// Take one or many tenders until the balance clears.
/// What a completed settlement hands back to the sale screen.
class SettledSale {
  const SettledSale({required this.ticket, required this.result});

  final Ticket ticket;
  final SubmitOrderResult result;
}

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  static Future<SettledSale?> show(BuildContext context) =>
      showDialog<SettledSale?>(
        context: context,
        barrierColor: context.pos.scrim,
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
      : Money.tryParse(
          _entry,
          currency: ticket.currency,
          exponent: ticket.exponent,
        );

  void _digit(String value) => setState(() => _entry += value);
  void _clear() => setState(() => _entry = '');

  void _quickCash(int major, Ticket ticket) => setState(
    () => _entry = Money(major * 100, currency: ticket.currency).format(),
  );

  Future<void> _take(Ticket ticket) async {
    final controller = ref.read(ticketProvider.notifier);
    final ok = controller.addTender(
      typeId: _methodId,
      label: _methods.firstWhere((m) => m.id == _methodId).wireLabel,
      amount: _parsedEntry(ticket),
    );

    if (!ok) {
      posToast(context, context.strings.enterAmountAboveZero);
      return;
    }

    setState(() => _entry = '');

    final updated = ref.read(ticketProvider);
    if (!updated.totals.isSettled) return;

    // Settled — record it, free the table, and hand the outcome back to the
    // sale screen, which owns what happens next (the receipt, and for a
    // seated ticket the walk back to the floor).
    final result = await ref
        .read(ordersRepositoryProvider)
        // Read here rather than baked into the repository: the sale belongs to
        // whoever took the money, and on a seated table that is routinely not
        // the person who opened the ticket.
        .submit(updated, servedBy: ref.read(signedInStaffProvider));
    if (!mounted) return;

    // Re-read the backlog rather than adding one to a running total. The count
    // is whatever the outbox says it is — a submit that replayed onto an
    // existing order enqueued nothing, and incrementing here would have
    // reported a sale as unsent twice.
    ref.invalidate(pendingSyncCountProvider);

    // The table's money is in the drawer — its seat is free again.
    ref.read(openTicketsProvider.notifier).settle(updated.tableId);

    Navigator.of(context).pop(SettledSale(ticket: updated, result: result));
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider);
    final totals = ticket.totals;
    final strings = context.strings;

    return Dialog(
      backgroundColor: context.pos.surface,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: context.pos.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(strings, ticket),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _left(strings, ticket, totals)),
                  SizedBox(width: 400, child: _right(strings, ticket, totals)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppStrings strings, Ticket ticket) => Container(
    height: PosSize.secondaryAction,
    color: context.pos.ink,
    padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
    child: Row(
      children: [
        PosButton(
          label: strings.backToTicket,
          height: 36,
          background: context.pos.shellCard,
          foreground: context.pos.shellText,
          fontSize: 12.5,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: PosSpace.md),
        Text(
          strings.payment,
          style: PosText.ui(
            size: 15,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Text(
          [
            ticket.orderType.label(strings),
            if (ticket.tableLabel != null) ticket.tableLabel!,
            strings.lineCount(ticket.lines.length),
          ].join(' · '),
          style: PosText.mono(size: 11.5, color: context.pos.shellMuted),
        ),
      ],
    ),
  );

  Widget _left(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      Container(
        color: context.pos.page,
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dueCard(strings, ticket, totals),
            const SizedBox(height: PosSpace.s14),
            Expanded(child: _tendersCard(strings, ticket)),
          ],
        ),
      );

  Widget _dueCard(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      PosSurface(
        border: Border.fromBorderSide(context.pos.emphasis),
        padding: const EdgeInsets.all(PosSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MicroLabel(
                  ticket.tenders.isEmpty
                      ? strings.amountDue
                      : strings.remainingDue,
                ),
                const Spacer(),
                Text(
                  strings.totalIs(totals.total.format()),
                  style: PosText.mono(size: 12, color: context.pos.muted),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.sm),
            Text(totals.due.format(), style: PosText.bigNumeric(color: context.pos.ink)),
            const SizedBox(height: PosSpace.md),
            _progress(totals),
            const SizedBox(height: PosSpace.sm),
            Text(
              strings.paidOfTotal(
                totals.paid.format(),
                totals.total.format(),
                ticket.tenders.length,
              ),
              style: PosText.ui(size: 12, color: context.pos.muted),
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
      child: Row(
        children: [
          Expanded(
            flex: (ratio * 1000).round(),
            child: ColoredBox(color: context.pos.ok),
          ),
          Expanded(
            flex: 1000 - (ratio * 1000).round(),
            child: ColoredBox(color: context.pos.line),
          ),
        ],
      ),
    );
  }

  Widget _tendersCard(AppStrings strings, Ticket ticket) => PosSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(PosSpace.md),
          child: MicroLabel(strings.tendersHeading),
        ),
        if (ticket.tenders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
            child: Text(
              strings.noTenderYet,
              style: PosText.ui(
                size: 12.5,
                color: context.pos.muted,
                height: 1.5,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: ticket.tenders.length,
              itemBuilder: (context, index) =>
                  _tenderRow(strings, ticket, index),
            ),
          ),
      ],
    ),
  );

  Widget _tenderRow(AppStrings strings, Ticket ticket, int index) {
    final tender = ticket.tenders[index];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.md,
      ),
      decoration: BoxDecoration(border: Border(top: context.pos.hairline)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tenderName(tender.typeId, tender.label, strings),
              style: PosText.ui(color: context.pos.inkWarm, size: 13, weight: FontWeight.w600),
            ),
          ),
          Text(tender.amount.format(), style: PosText.mono(color: context.pos.inkWarm, size: 15)),
          const SizedBox(width: PosSpace.md),
          InkWell(
            onTap: () =>
                ref.read(ticketProvider.notifier).removeTenderAt(index),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.fromBorderSide(context.pos.hairline),
              ),
              child: Text(
                '×',
                style: PosText.ui(size: 16, color: context.pos.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _right(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      Container(
        decoration: BoxDecoration(
          color: context.pos.surface,
          border: Border(left: context.pos.emphasis),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _methodGrid(strings),
            _amountBlock(strings, ticket, totals),
            Expanded(child: _keypad(strings)),
            PosButton(
              label: strings.takePayment,
              height: 72,
              alignLeft: true,
              background: context.pos.ok,
              foreground: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              trailing: Text(
                (_parsedEntry(ticket) ?? totals.due).format(),
                style: PosText.mono(
                  size: 16,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              onPressed: () => _take(ticket),
            ),
          ],
        ),
      );

  Widget _methodGrid(AppStrings strings) => Container(
    color: context.pos.lineStrong,
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
            color: method.id == _methodId ? context.pos.ink : context.pos.surface,
            child: InkWell(
              onTap: () => setState(() => _methodId = method.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    method.label(strings),
                    style: PosText.ui(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: method.id == _methodId
                          ? Colors.white
                          : context.pos.inkWarm,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _amountBlock(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      Container(
        padding: const EdgeInsets.all(PosSpace.md),
        decoration: BoxDecoration(
          border: Border(top: context.pos.emphasis, bottom: context.pos.hairline),
        ),
        child: Column(
          children: [
            Row(
              children: [
                MicroLabel(strings.amount),
                const Spacer(),
                Text(
                  _entry.isEmpty ? totals.due.format() : _entry,
                  style: PosText.mono(
                    size: 22,
                    color: _entry.isEmpty ? context.pos.muted : context.pos.ink,
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
                    background: context.pos.page,
                    border: Border.fromBorderSide(context.pos.resting),
                    onPressed: () => _quickCash(amount, ticket),
                  ),
                PosButton(
                  label: strings.exact,
                  background: context.pos.page,
                  border: Border.fromBorderSide(context.pos.resting),
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
  Widget _keypad(AppStrings strings) {
    // 'CLR' is the key's IDENTITY, not its caption — [_key] translates it on
    // the way to the screen. The digits are captions and identities at once,
    // and stay Western in both languages: this pad feeds an amount that is
    // read back off a receipt and counted into a drawer.
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['0', '00', _clearKey],
    ];

    return Container(
      color: context.pos.line,
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
                      Expanded(child: _key(strings, key)),
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

  Widget _key(AppStrings strings, String key) {
    final isClear = key == _clearKey;

    return Material(
      color: isClear ? context.pos.page : context.pos.surface,
      child: InkWell(
        onTap: () => isClear ? _clear() : _digit(key),
        child: Center(
          child: Text(
            isClear ? strings.clear : key,
            style: isClear
                ? PosText.ui(size: 13, color: context.pos.chipText)
                : PosText.mono(color: context.pos.inkWarm, size: 20, weight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
