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

/// The queue refused it — a dropped connection, a constraint. Carries the
/// message rather than a category, because there is nothing useful to
/// categorise it into and the text is what a person needs.
class FilingFailed extends EtaFilingSkipped {
  const FilingFailed(this.detail);

  final String detail;
}

abstract final class EtaFiling {
  /// ETA's payment method codes, for the tenders this product takes.
  ///
  /// A card and a wallet are both `V` — the authority's list distinguishes
  /// cash from everything electronic and does not care which app it was.
  static String paymentMethodFor(Iterable<Tender> tenders) {
    // No tender recorded means cash: a till that took money and did not say
    // how took it out of the drawer, and 'C' is the answer a filing wants
    // rather than a blank field.
    if (tenders.isEmpty) return 'C';
    final anyCash = tenders.any((t) => TenderMethod.isCash(t.typeId));
    final anyOther = tenders.any((t) => !TenderMethod.isCash(t.typeId));
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
    if (!profile.canFile) return null;

    final totals = ticket.totals;
    final items = <EtaItem>[];

    for (final line in ticket.lines) {
      // A voided line is not a sale. It stays on the customer's slip because
      // the kitchen made it and they watched it happen, and it stays off the
      // filing for exactly the same reason: nobody was charged for it.
      if (line.isVoided) continue;

      items.add(
        EtaItem(
          description: line.displayName('en'),
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          totalSale: line.lineTotal,
          total: line.lineTotal,
          // Per-line tax is apportioned by the ticket, not recomputed here:
          // the ticket rounds once per rate, and a second calculation would
          // disagree with the total the customer was actually charged.
          taxes: _taxesFor(line, totals),
          internalCode: line.product.sku,
        ),
      );
    }

    return EtaReceiptInput(
      profile: profile,
      receiptNumber: receiptNumber,
      issuedAt: issuedAt,
      deviceSerialNumber: deviceSerial,
      items: items,
      totalSales: totals.subtotal,
      netAmount: totals.net,
      totalAmount: totals.total,
      taxTotals: totals.taxLines,
      totalCommercialDiscount: totals.discount,
      paymentMethod: paymentMethodFor(ticket.tenders),
    );
  }

  /// This line's share of each rate the ticket charged.
  ///
  /// Apportioned from the ticket's own figures rather than multiplied out
  /// again, so the sum of the lines is the number on the receipt down to the
  /// piastre. The last line takes the remainder, the same rule the ticket
  /// itself uses for discounts.
  static List<TaxLine> _taxesFor(TicketLine line, TicketTotals totals) {
    if (totals.taxLines.isEmpty || totals.subtotal.minor <= 0) return const [];

    return [
      for (final tax in totals.taxLines)
        if (tax.base.minor > 0)
          TaxLine(
            name: tax.name,
            rateBp: tax.rateBp,
            base: line.lineTotal,
            amount: Money(
              // Integer arithmetic throughout: the share of the tax that this
              // line's value represents, never a percentage of a percentage.
              (tax.amount.minor * line.lineTotal.minor) ~/ totals.subtotal.minor,
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
