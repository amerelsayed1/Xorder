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
import '../../domain/models/order_record.dart';
import '../../domain/models/refund.dart';
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
    this.tableLabel,
    this.serviceBp,
    this.vatBp,
    this.taxFromDeviceConfig = false,
    this.syncNote = ReceiptSyncNote.none,
    this.refunded = Money.zero,
    this.isReprint = false,
  });

  /// Everything on the slip, taken from the ticket that was just settled.
  /// [cloudBacked] is whether this terminal syncs with a platform at all. It
  /// decides between saying nothing and saying something.
  factory ReceiptData.fromTicket(
    Ticket ticket, {
    String? invoiceNumber,
    bool queued = false,
    bool cloudBacked = false,
  }) {
    final totals = ticket.totals;
    return ReceiptData(
      invoiceNumber: invoiceNumber,
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
      serviceBp: ticket.taxConfig.serviceBp,
      vatBp: ticket.taxConfig.vatBp,
      taxFromDeviceConfig: ticket.taxConfig.source == TaxSource.deviceConfig,
      syncNote: !cloudBacked
          ? ReceiptSyncNote.none
          : (queued || invoiceNumber == null
                ? ReceiptSyncNote.queued
                : ReceiptSyncNote.synced),
    );
  }

  /// The same slip, rebuilt from the ledger.
  ///
  /// [serviceBp] and [vatBp] are **null** here, and the paper prints "Service"
  /// and "VAT" without a percentage as a result. The rates are not columns on
  /// `pos_orders`, and deriving them by dividing the tax by the net would print
  /// a figure that is right most of the time and wrong on any order where
  /// rounding went the other way. A reprint that omits a rate is honest; one
  /// that invents a rate is a document somebody will argue with.
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
      refunded: refunded,
      isReprint: isReprint,
    );
  }

  final String? invoiceNumber;
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
  final int? vatBp;

  final bool taxFromDeviceConfig;
  final ReceiptSyncNote syncNote;

  /// What has since gone back. Printed on a reprint so the slip cannot be used
  /// to claim a refund that has already been given.
  final Money refunded;

  final bool isReprint;

  bool get wasRefunded => refunded.minor > 0;
}
