/// What goes on a receipt, independent of where it came from.
///
/// **Why this exists.** The receipt was built straight from a live [Ticket],
/// which is fine until somebody wants to reprint one. A settled order is not a
/// ticket: it has no `Product` objects, its prices are snapshots, and rebuilding
/// a ticket from it would re-price the sale against today's menu — printing a
/// customer a receipt that disagrees with the one in their hand.
///
/// So the paper takes plain data and both paths feed it: a live ticket at
/// settlement, an [OrderRecordDetail] on a reprint. Neither can accidentally
/// recompute anything, because there is nothing here to recompute *with*.
library;

import '../../core/money/money.dart';
import '../../domain/models/discount.dart';
import '../../domain/models/order_record.dart';
import '../../domain/models/refund.dart';
import '../../domain/models/tax.dart';
import '../../domain/models/ticket.dart';

/// What the slip says about where this sale has got to.
///
/// **An offline terminal says nothing.** It used to print `SYNCED TO XORDER`,
/// because `queued` is false on a till that queues nothing — so the one
/// deployment that has never contacted a platform, and never will, was the one
/// claiming it had. That is a false statement on a document a customer keeps.
enum ReceiptSyncNote {
  /// Offline deployment. There is no platform, so there is nothing to report.
  none,

  /// Cloud, and this sale has not reached the platform yet.
  queued,

  /// Cloud, and it has.
  synced,
}

/// One printed line.
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.lineTotal,
    this.isVoided = false,
    this.wasRepriced = false,
  });

  final String name;
  final int quantity;
  final Money lineTotal;

  /// Printed struck through. A voided line stays on the slip because the
  /// kitchen made it and the customer watched it happen.
  final bool isVoided;

  /// Sold at a price somebody set by hand. Marked so a customer comparing two
  /// receipts for the same dish is not looking at a mistake.
  final bool wasRepriced;
}

/// One rate's worth of tax — the engine's `TaxLine`, or a `pos_order_taxes`
/// row, carrying only what the paper prints.
class ReceiptTaxLine {
  const ReceiptTaxLine({required this.rateBp, required this.amount});

  final int rateBp;
  final Money amount;
}

/// One tender, as it was taken.
class ReceiptPayment {
  const ReceiptPayment({
    required this.label,
    required this.amount,
    this.tenderTypeId,
  });

  /// The label written when the money moved — English by design, see
  /// `TenderMethod.wireLabel`. The slip translates it only where it can prove
  /// the method has not been renamed since; see `ReceiptDocument.of`.
  final String label;
  final Money amount;
  final int? tenderTypeId;
}

class ReceiptData {
  const ReceiptData({
    required this.orderType,
    required this.occurredAt,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.service,
    required this.vat,
    required this.total,
    required this.paid,
    required this.change,
    this.invoiceNumber,
    this.dayOrderNumber,
    this.tableLabel,
    this.serviceBp,
    this.taxLines = const [],
    this.discountBp,
    this.payments = const [],
    this.taxFromDeviceConfig = false,
    this.syncNote = ReceiptSyncNote.none,
    this.refunded = Money.zero,
    this.isReprint = false,
    this.etaQrPayload,
  });

  /// The QR square Egypt requires on a customer's printed copy.
  ///
  /// Null until the e-receipt has been sealed, which on a till selling through
  /// an outage may be minutes or hours after the slip was handed over. That is
  /// not a bug and not a compliance failure — ETA allow twenty-four hours — so
  /// the slip prints without it rather than refusing to print.
  final String? etaQrPayload;

  /// Everything on the slip, taken from the ticket that was just settled.
  /// [cloudBacked] is whether this terminal syncs with a platform at all. It
  /// decides between saying nothing and saying something.
  factory ReceiptData.fromTicket(
    Ticket ticket, {
    String? invoiceNumber,
    int? dayOrderNumber,
    bool queued = false,
    bool cloudBacked = false,
  }) {
    final totals = ticket.totals;
    return ReceiptData(
      invoiceNumber: invoiceNumber,
      dayOrderNumber: dayOrderNumber,
      orderType: ticket.orderType,
      tableLabel: ticket.tableLabel,
      occurredAt: DateTime.now(),
      lines: [
        for (final line in ticket.lines)
          ReceiptLine(
            name: line.product.nameEn,
            quantity: line.quantity,
            lineTotal: line.lineTotal,
            isVoided: line.isVoided,
            wasRepriced: line.isRepriced,
          ),
      ],
      subtotal: totals.subtotal,
      discount: totals.discount,
      service: totals.service,
      vat: totals.vat,
      total: totals.total,
      paid: totals.paid,
      change: totals.change,
      // The legacy single rate only when it is what was charged. Once §38's
      // charges are configured `serviceBp` is a fallback nobody used, and this
      // printed "SERVICE 12%" over a service charge taken at 10%.
      serviceBp: ticket.taxConfig.serviceCharges.isEmpty
          ? ticket.taxConfig.serviceBp
          : null,
      taxLines: _explaining(totals.taxLines, totals.vat),
      discountBp: _singlePercentage(ticket, totals),
      payments: [
        for (final tender in ticket.tenders)
          ReceiptPayment(
            label: tender.label,
            amount: tender.amount,
            tenderTypeId: tender.typeId,
          ),
      ],
      taxFromDeviceConfig: ticket.taxConfig.source == TaxSource.deviceConfig,
      syncNote: !cloudBacked
          ? ReceiptSyncNote.none
          : (queued || invoiceNumber == null
                ? ReceiptSyncNote.queued
                : ReceiptSyncNote.synced),
    );
  }

  /// This slip once the platform has numbered the sale (XORD-058): the same
  /// paper, time included, carrying [invoice] and saying it reached the
  /// platform.
  ReceiptData numbered(String invoice) => ReceiptData(
    invoiceNumber: invoice,
    orderType: orderType,
    tableLabel: tableLabel,
    occurredAt: occurredAt,
    lines: lines,
    subtotal: subtotal,
    discount: discount,
    service: service,
    vat: vat,
    total: total,
    paid: paid,
    change: change,
    serviceBp: serviceBp,
    taxLines: taxLines,
    discountBp: discountBp,
    payments: payments,
    taxFromDeviceConfig: taxFromDeviceConfig,
    syncNote: syncNote == ReceiptSyncNote.none
        ? ReceiptSyncNote.none
        : ReceiptSyncNote.synced,
    refunded: refunded,
    isReprint: isReprint,
    etaQrPayload: etaQrPayload,
  );

  /// The same slip, rebuilt from the ledger.
  ///
  /// **The VAT rate comes from `pos_order_taxes`**, the per-rate breakdown
  /// written at settlement — a stored rate, not one derived by dividing the tax
  /// by the net, which would be right most of the time and wrong wherever
  /// rounding went the other way. [serviceBp] and [discountBp] stay **null**:
  /// neither rate is stored on the order, and a reprint that omits a rate is
  /// honest where one that invents a rate is a document somebody will argue
  /// with.
  factory ReceiptData.fromOrder(
    OrderRecordDetail detail, {
    List<Refund> refunds = const [],
    bool isReprint = true,
  }) {
    final order = detail.order;
    final zero = Money(
      0,
      currency: order.total.currency,
      exponent: order.total.exponent,
    );

    var paid = zero;
    for (final payment in detail.payments) {
      paid += payment.amount;
    }
    var refunded = zero;
    for (final refund in refunds) {
      refunded += refund.total;
    }

    return ReceiptData(
      invoiceNumber: order.invoiceNumber,
      dayOrderNumber: order.dayOrderNumber,
      orderType: order.orderType,
      tableLabel: order.tableLabel,
      // The time of the **sale**, not of the reprint. A receipt reprinted a
      // week later that claimed to be a week old sale from today would be a
      // forgery the till produced on request.
      occurredAt: order.occurredAt,
      lines: [
        for (final line in detail.lines)
          ReceiptLine(
            name: line.name,
            quantity: line.quantity,
            lineTotal: line.lineTotal,
            isVoided: line.isVoided,
          ),
      ],
      subtotal: order.subtotal,
      discount: order.discount,
      service: order.service,
      vat: order.vat,
      total: order.total,
      paid: paid,
      // A settled order has no change to give back — whatever the drawer
      // returned was returned at the time and is not part of this record.
      change: zero,
      taxLines: _explaining(detail.taxLines, order.vat),
      payments: [
        for (final payment in detail.payments)
          ReceiptPayment(
            label: payment.label,
            amount: payment.amount,
            tenderTypeId: payment.tenderTypeId,
          ),
      ],
      refunded: refunded,
      isReprint: isReprint,
    );
  }

  /// The breakdown, but only if it accounts for every piastre of [vat].
  ///
  /// On a live ticket it always does — `vat` is summed from these lines. On a
  /// reprint the lines are a second table, and a breakdown that disagrees with
  /// the order's own figure would print two VAT numbers that do not add up. The
  /// slip then prints the one figure with no rate, which is what it did before
  /// the breakdown existed.
  static List<ReceiptTaxLine> _explaining(List<TaxLine> lines, Money vat) {
    var sum = 0;
    for (final line in lines) {
      sum += line.amount.minor;
    }
    if (lines.isEmpty || sum != vat.minor) return const [];
    return [
      for (final line in lines)
        ReceiptTaxLine(rateBp: line.rateBp, amount: line.amount),
    ];
  }

  /// The percentage to print beside "Discount", or null to print none.
  ///
  /// **Only when one percentage explains the whole figure.** A slip reading
  /// "Discount (12%)" is a claim a customer can check against the subtotal
  /// above it, so it must hold: one discount, on the order rather than a line,
  /// a percentage, and that percentage of the printed subtotal is exactly the
  /// printed discount. The last test is integer arithmetic on two figures the
  /// engine already produced and decides only the label — it prints nothing.
  /// It is what catches "20% off, capped at 50 EGP", which is a percentage
  /// discount whose amount is not 20% of anything on the paper.
  static int? _singlePercentage(Ticket ticket, TicketTotals totals) {
    if (totals.discount.isZero) return null;

    // The same set `Ticket.totals` counts: a discount on a voided line came
    // off with the line.
    final live = {for (final line in ticket.chargeableLines) line.key};
    final counted = [
      for (final discount in ticket.discounts)
        if (discount.lineKey == null || live.contains(discount.lineKey))
          discount,
    ];
    if (counted.length != 1) return null;

    final only = counted.single;
    final bp = only.valueBp;
    if (!only.isOrderLevel ||
        only.kind != DiscountKind.percentage ||
        bp == null) {
      return null;
    }
    if (only.amount.minor != totals.discount.minor) return null;
    if (totals.subtotal.percentBp(bp).minor != totals.discount.minor) {
      return null;
    }
    return bp;
  }

  final String? invoiceNumber;

  /// The count of orders in the trading day, shared by every till: the number
  /// a cashier calls out. Printed beside the invoice number, never instead of
  /// it. Null prints nothing.
  final int? dayOrderNumber;
  final OrderType orderType;
  final String? tableLabel;
  final DateTime occurredAt;
  final List<ReceiptLine> lines;

  final Money subtotal;
  final Money discount;
  final Money service;
  final Money vat;
  final Money total;
  final Money paid;
  final Money change;

  /// Null when the rate is not known — see [ReceiptData.fromOrder].
  final int? serviceBp;

  /// [vat] by rate. Empty when there is no breakdown that accounts for it, and
  /// the slip then prints "VAT" with no rate.
  final List<ReceiptTaxLine> taxLines;

  /// See [_singlePercentage].
  final int? discountBp;

  /// One per tender. Empty on a record written before payments were rows.
  final List<ReceiptPayment> payments;

  final bool taxFromDeviceConfig;
  final ReceiptSyncNote syncNote;

  /// What has since gone back. Printed on a reprint so the slip cannot be used
  /// to claim a refund that has already been given.
  final Money refunded;

  final bool isReprint;

  bool get wasRefunded => refunded.minor > 0;
}
