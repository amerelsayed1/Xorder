import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../services/stock_costing.dart';

/// How much of one counted item this branch holds, and what it is worth.
///
/// Valued through [StockPosition], the same arithmetic receiving uses, so the
/// figure on this screen and the figure the next delivery averages against
/// are one number rather than two that ought to agree.
class StockLevel {
  const StockLevel({
    required this.productId,
    required this.nameEn,
    required this.onHand,
    required this.unitCost,
    this.nameAr,
    this.onMenu = false,
  });

  final int productId;
  final String nameEn;
  final String? nameAr;

  /// In the unit it is counted in. Signed: a business that sold what the
  /// system never saw arrive is telling the truth about the sale, and the
  /// stock says so rather than clamping at zero and hiding it.
  final Quantity onHand;

  /// The moving average, per whole unit.
  final Money unitCost;

  final bool onMenu;

  Money get value => StockPosition(onHand: onHand, unitCost: unitCost).value;

  /// Whether anything has ever set a cost for this item.
  ///
  /// A cost of zero is how "never received" looks on the ledger, and it is read
  /// that way everywhere else: the profit report counts a sale at zero as not
  /// costed rather than free. So the stock page must not draw it as a price of
  /// 0.00 — that says "free" about the one item nobody has priced.
  bool get hasCost => unitCost.minor > 0;

  String displayName(String languageCode) =>
      languageCode == 'ar' && (nameAr?.trim().isNotEmpty ?? false)
      ? nameAr!.trim()
      : nameEn;
}

/// What the stock on hand is worth — and how much of it that figure leaves out.
///
/// **The total is of costed items only, and says so.** An item nothing has ever
/// received has no cost, so its worth is unknown, not nil: counting it at zero
/// would let the total read as complete while understating the shelf by exactly
/// the stock nobody has priced. [unvalued] is how many items with stock on hand
/// are left out, so the page can say it beside the figure rather than leave the
/// reader to assume. An uncosted item with nothing on hand is not counted — it
/// leaves nothing out — and neither is one below zero, which is a shortage to
/// look at and not stock to value.
class StockValuation {
  const StockValuation({required this.total, required this.unvalued});

  factory StockValuation.of(Iterable<StockLevel> levels) {
    var total = Money.zero;
    var unvalued = 0;
    for (final level in levels) {
      if (level.hasCost) {
        total += level.value;
      } else if (level.onHand.milli > 0) {
        unvalued++;
      }
    }
    return StockValuation(total: total, unvalued: unvalued);
  }

  /// The worth of the items that have a cost.
  final Money total;

  /// Items with stock on hand and no cost: in no figure here.
  final int unvalued;

  bool get isComplete => unvalued == 0;
}
