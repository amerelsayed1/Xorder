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

  /// In the unit it is counted in. Signed: a restaurant that sold what the
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
