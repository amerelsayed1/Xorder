/// Turning a settled sale into a receipt owed to the tax authority.
///
/// **Deliberately not inside the order's transaction.** The tempting design is
/// to write the order and queue its e-receipt atomically, so one cannot exist
/// without the other. It is the wrong one, for a reason that only shows up
/// later: a restaurant that starts filing after six weeks of trading, or one
/// whose receipt profile was incomplete on Tuesday, has orders that need
/// queueing and no transaction to put them in.
///
/// So the relationship is a *query* rather than a coupling — an order with no
/// row in `pos_eta_receipts` is one that still owes a receipt, whether it was
/// rung up a second ago or last month — and the same reconciler covers a crash
/// between the two writes and a restaurant that turned this on late. Coupling
/// them would have handled the first case and none of the others.
library;

import '../../core/money/money.dart';
import '../models/receipt_profile.dart';
import '../models/tax.dart';
import '../models/tender_method.dart';
import '../models/ticket.dart';
import 'eta_receipt.dart';

/// Why a sale was not queued.
sealed class EtaFilingSkipped {
  const EtaFilingSkipped();
}

/// This terminal has no queue — no database, or e-receipts are not in use.
class FilingNotInUse extends EtaFilingSkipped {
  const FilingNotInUse();
}

/// The receipt profile is not complete enough to file with.
///
/// Carries the problems so the caller can say which fields, rather than
/// leaving somebody to guess from a queue that stopped growing.
class ProfileIncomplete extends EtaFilingSkipped {
  const ProfileIncomplete(this.problems);

  final List<ProfileProblem> problems;
}

/// A refund whose sale has no receipt yet.
///
/// Not a problem, and not reported as one: a refund receipt names the sale
/// it undoes, and filing one that points at nothing would be the dangling
/// reference the authority rejects. It waits, and the reconciler files it on
/// the pass after its sale is filed.
class RefundAwaitingSale extends EtaFilingSkipped {
  const RefundAwaitingSale();
}

/// The queue refused it — a dropped connection, a constraint. Carries the
/// message rather than a category, because there is nothing useful to
/// categorise it into and the text is what a person needs.
class FilingFailed extends EtaFilingSkipped {
  const FilingFailed(this.detail);

  final String detail;
}

/// Files the receipt a recorded sale or refund owes.
///
/// A port because the till's decorators call it at settlement and refund time
/// and must not know it reads PostgreSQL; `EtaFiler` is the implementation.
abstract interface class EtaFilingPort {
  /// Null when a receipt was queued or none was owed; otherwise why not.
  Future<EtaFilingSkipped?> fileOrder(int orderId);

  Future<EtaFilingSkipped?> fileRefund(int refundId);
}

/// One line as the filing needs it.
class FilingLine {
  const FilingLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.sku,
  });

  final String description;
  final int quantity;
  final Money unitPrice;

  /// What was charged for the line — the repriced figure where it was
  /// repriced, never the menu's.
  final Money lineTotal;
  final String? sku;
}

/// A settled sale — or a refund of one — as the filing needs it.
///
/// **One shape, whichever way it was read.** A sale filed the moment it
/// settles and one caught up by the reconciler a week later are the same
/// document, and the only way to be sure of that is for both to be built by
/// the same function from the same fields. The till builds this from its
/// ticket; the reconciler builds it from the rows the ticket was written to.
class FilingSale {
  const FilingSale({
    required this.receiptNumber,
    required this.issuedAt,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.taxLines,
    required this.cashTenders,
    this.currency = 'EGP',
  });

  final String receiptNumber;

  /// When it happened — the sale's time, not the time it was filed. A receipt
  /// caught up on Thursday for a Tuesday sale is a Tuesday receipt.
  final DateTime issuedAt;

  /// The lines that were charged for. A voided line is not one.
  final List<FilingLine> lines;
  final Money subtotal;
  final Money discount;
  final Money total;

  /// Per rate, as charged.
  final List<TaxLine> taxLines;

  /// One entry per tender: whether it counted as cash, as the tender said at
  /// the time.
  final List<bool> cashTenders;
  final String currency;
}

abstract final class EtaFiling {
  /// ETA's payment method codes, for the tenders this product takes.
  ///
  /// A card and a wallet are both `V` — the authority's list distinguishes
  /// cash from everything electronic and does not care which app it was.
  static String paymentMethodFor(Iterable<Tender> tenders) =>
      paymentMethodFromCash([
        for (final tender in tenders) TenderMethod.isCash(tender.typeId),
      ]);

  /// The same answer from whether each tender counted as cash.
  static String paymentMethodFromCash(List<bool> cashTenders) {
    // No tender recorded means cash: a till that took money and did not say
    // how took it out of the drawer, and 'C' is the answer a filing wants
    // rather than a blank field.
    if (cashTenders.isEmpty) return 'C';
    final anyCash = cashTenders.contains(true);
    final anyOther = cashTenders.contains(false);
    if (anyCash && anyOther) return 'M';
    return anyCash ? 'C' : 'V';
  }

  /// Builds the input for one settled ticket.
  ///
  /// Returns null when [profile] cannot be filed with — checked here rather
  /// than at the database, because "your activity code is four digits" is a
  /// sentence somebody can act on and a foreign key violation is not.
  static EtaReceiptInput? inputFor({
    required Ticket ticket,
    required ReceiptProfile profile,
    required String receiptNumber,
    required String deviceSerial,
    required DateTime issuedAt,
  }) {
    final totals = ticket.totals;
    return inputFrom(
      FilingSale(
        receiptNumber: receiptNumber,
        issuedAt: issuedAt,
        lines: [
          for (final line in ticket.lines)
            // A voided line is not a sale. It stays on the customer's slip
            // because the kitchen made it and they watched it happen, and it
            // stays off the filing for exactly the same reason: nobody was
            // charged for it.
            if (!line.isVoided)
              FilingLine(
                description: line.displayName('en'),
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                lineTotal: line.lineTotal,
                sku: line.product.sku,
              ),
        ],
        subtotal: totals.subtotal,
        discount: totals.discount,
        total: totals.total,
        taxLines: totals.taxLines,
        cashTenders: [
          for (final tender in ticket.tenders) TenderMethod.isCash(tender.typeId),
        ],
      ),
      profile: profile,
      deviceSerial: deviceSerial,
    );
  }

  /// Builds the input for one settled sale, or — with [referenceOldUuid] — for
  /// a refund of one.
  ///
  /// Returns null when [profile] cannot be filed with.
  static EtaReceiptInput? inputFrom(
    FilingSale sale, {
    required ReceiptProfile profile,
    required String deviceSerial,
    String? referenceOldUuid,
  }) {
    if (!profile.canFile) return null;

    return EtaReceiptInput(
      profile: profile,
      receiptNumber: sale.receiptNumber,
      issuedAt: sale.issuedAt,
      deviceSerialNumber: deviceSerial,
      items: [
        for (final line in sale.lines)
          EtaItem(
            description: line.description,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            totalSale: line.lineTotal,
            total: line.lineTotal,
            // Per-line tax is apportioned from the sale's own figures, not
            // recomputed here: the sale rounds once per rate, and a second
            // calculation would disagree with what the customer was charged.
            taxes: _taxesFor(line.lineTotal, sale.taxLines, sale.subtotal),
            internalCode: line.sku,
          ),
      ],
      totalSales: sale.subtotal,
      netAmount: sale.subtotal - sale.discount,
      totalAmount: sale.total,
      taxTotals: sale.taxLines,
      totalCommercialDiscount: sale.discount,
      paymentMethod: paymentMethodFromCash(sale.cashTenders),
      currency: sale.currency,
      referenceOldUuid: referenceOldUuid,
      receiptType: referenceOldUuid == null
          ? EtaReceiptType.sale
          : EtaReceiptType.refund,
    );
  }

  /// This line's share of each rate the sale charged.
  ///
  /// Apportioned from the ticket's own figures rather than multiplied out
  /// again, so the sum of the lines is the number on the receipt down to the
  /// piastre. The last line takes the remainder, the same rule the ticket
  /// itself uses for discounts.
  static List<TaxLine> _taxesFor(
    Money lineTotal,
    List<TaxLine> taxLines,
    Money subtotal,
  ) {
    if (taxLines.isEmpty || subtotal.minor <= 0) return const [];

    return [
      for (final tax in taxLines)
        if (tax.base.minor > 0)
          TaxLine(
            name: tax.name,
            rateBp: tax.rateBp,
            base: lineTotal,
            amount: Money(
              // Integer arithmetic throughout: the share of the tax that this
              // line's value represents, never a percentage of a percentage.
              (tax.amount.minor * lineTotal.minor) ~/ subtotal.minor,
              currency: tax.amount.currency,
              exponent: tax.amount.exponent,
            ),
            taxGroupId: tax.taxGroupId,
            etaTaxType: tax.etaTaxType,
            etaSubType: tax.etaSubType,
          ),
    ];
  }
}
