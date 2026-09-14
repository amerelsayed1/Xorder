/// Refunds as a list — the back office's Returns (المرتجعات), one row per
/// `pos_refunds` row.
///
/// Not a [Refund]. That is one refund with its lines and tenders, read when a
/// sale is opened, and it is what the refund engine and the detail pane work
/// from. This is what a person scanning a week of returns needs on one line,
/// and nothing more — the lines are counted, not carried, for the reason the
/// sales list carries no lines: two hundred rows each dragging their items
/// along is how a list gets slow at the moment somebody is in a hurry.
library;

import '../../core/money/money.dart';
import 'refund.dart' show Refund, RefundKind;

/// One refund, as its row in Returns shows it.
class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.orderId,
    required this.invoiceNumber,
    required this.occurredAt,
    required this.total,
    required this.kind,
    required this.lineCount,
    this.refundedByName,
    this.approvedByName,
    this.reasonName,
    this.reasonNameAr,
    this.note,
    this.terminalId,
    this.terminalName,
    this.servedByStaffId,
    this.businessDate,
  });

  /// `pos_refunds.id`, which is also the refund's number on screen. The table
  /// has no number of its own: `client_refund_id` is a uuid nobody can read
  /// out over a phone, and a sequence shown as a number is one they can.
  final int id;

  /// The sale it gives money back on, and that sale's invoice number.
  final int orderId;
  final String invoiceNumber;

  final DateTime occurredAt;

  /// What went back, in the sale's currency.
  final Money total;
  final RefundKind kind;

  /// How many of the sale's lines it names. Zero is an amount given back
  /// against the bill as a whole ([Refund.isAmountOnly]).
  final int lineCount;

  /// Who gave it, and — above the threshold — who allowed it.
  final String? refundedByName;
  final String? approvedByName;

  /// The reason as configured, in both languages; null when none was asked.
  final String? reasonName;
  final String? reasonNameAr;
  final String? note;

  /// The till the money left, and what it is called. The name is null for a
  /// terminal whose row is gone; the refund still lists.
  final String? terminalId;
  final String? terminalName;

  /// Who rang up the sale this refund is against — what `HistoryScope`
  /// narrows a cashier's Returns by, as it narrows their sales.
  final int? servedByStaffId;

  /// The trading day the refund belongs to, local midnight; null when no
  /// business day covers it.
  final DateTime? businessDate;
}

/// Which refunds to list.
///
/// The sales list's shape ([OrderHistoryQuery]) with the filters Returns has:
/// a window of business dates, a search, the scope and a keyset page.
class RefundHistoryQuery {
  const RefundHistoryQuery({
    this.from,
    this.to,
    this.search,
    this.servedByStaffId,
    this.afterRefundId,
    this.limit = pageSize,
  });

  /// Rows per page — the sales list's, so the two pagers turn alike.
  static const pageSize = 50;

  /// Inclusive lower bound, as a business date. A refund is filed under the
  /// trading day that was open when it was given — the reports' rule for
  /// refunds, and the sales list's for sales.
  final DateTime? from;

  /// Exclusive upper bound, the same kind of date as [from].
  final DateTime? to;

  /// Matches anywhere in the original invoice number, or the refund's number
  /// exactly. Exactly, because "12" anywhere in a refund id is every tenth
  /// refund, and the number somebody reads off a screen is the whole of it.
  final String? search;

  /// Refunds against this person's sales only. Set by `HistoryScope`, never
  /// by a control on the screen.
  final int? servedByStaffId;

  /// The page begins after this refund. Keyset rather than offset, for the
  /// reason [OrderHistoryQuery.afterOrderId] gives.
  final int? afterRefundId;
  final int limit;

  /// The same filter from its first page — what the strip is keyed by.
  RefundHistoryQuery get unpaged => afterRefundId == null && limit == pageSize
      ? this
      : copyWith(clearAfter: true, limit: pageSize);

  /// Whether the person narrowed the list — the scope is not theirs to clear.
  bool get isFiltered => search != null && search!.trim().isNotEmpty;

  RefundHistoryQuery copyWith({
    DateTime? from,
    DateTime? to,
    String? search,
    int? servedByStaffId,
    int? afterRefundId,
    bool clearAfter = false,
    int? limit,
  }) => RefundHistoryQuery(
    from: from ?? this.from,
    to: to ?? this.to,
    search: search ?? this.search,
    servedByStaffId: servedByStaffId ?? this.servedByStaffId,
    afterRefundId: clearAfter ? null : (afterRefundId ?? this.afterRefundId),
    limit: limit ?? this.limit,
  );

  /// Value equality: this keys a `FutureProvider.family`, and the screen
  /// builds a fresh query every rebuild. See [OrderHistoryQuery.==].
  @override
  bool operator ==(Object other) =>
      other is RefundHistoryQuery &&
      other.from == from &&
      other.to == to &&
      other.search == search &&
      other.servedByStaffId == servedByStaffId &&
      other.afterRefundId == afterRefundId &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(from, to, search, servedByStaffId, afterRefundId, limit);
}

/// The strip over Returns: how many refunds, and what they gave back.
///
/// **Over exactly the rows the list pages through.** `summariseRefunds` runs
/// the list's own WHERE, and [of] is the rule it is held to:
/// `test/data/refund_history_test.dart` requires the database's two figures to
/// equal this over every page of the list, for every filter.
class RefundHistorySummary {
  const RefundHistorySummary({required this.count, required this.total});

  static const empty = RefundHistorySummary(count: 0, total: Money(0));

  final int count;

  /// Every refund's total. No row is struck through here: a refund is money
  /// that left the drawer, and there is no state of one that makes it not.
  final Money total;

  static RefundHistorySummary of(Iterable<RefundRecord> rows) {
    var count = 0;
    var total = 0;
    Money? unit;
    for (final row in rows) {
      unit ??= row.total;
      count++;
      total += row.total.minor;
    }
    return RefundHistorySummary(
      count: count,
      total: unit == null
          ? Money(total)
          : Money(total, currency: unit.currency, exponent: unit.exponent),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RefundHistorySummary &&
      other.count == count &&
      other.total == total;

  @override
  int get hashCode => Object.hash(count, total);

  @override
  String toString() =>
      'RefundHistorySummary(count: $count, total: ${total.minor})';
}
