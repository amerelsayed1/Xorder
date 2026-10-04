/// What the menu earned over a range, where the till knows what it cost.
///
/// The last link of the chain `16-back-office-scope.md` §3 draws: purchases set
/// a moving-average cost, every sale of a stocked item records that cost on its
/// stock movement, and this reads the two together.
///
/// **A profit figure that quietly covers half the menu is worse than none**, so
/// the report is built around what it does *not* know:
///
/// * Only a **stocked** item is costed. There is no recipe model, so a burger
///   is not inferred to consume its bun (`PostgresOrdersRepository._issueStock`
///   says why). A dish, a combo and an open-price charge have revenue and no
///   cost, and are reported as such rather than as pure profit.
/// * A sale recorded while the carrying cost was **zero** — a stocked item sold
///   before anything was ever received — is treated as **not costed**. Zero is
///   how "never bought" looks on the ledger, and reading it as "free" would
///   report a 100% margin on exactly the items nobody has priced.
/// * [ProfitReport.coverageBp] says how much of the revenue is costed, so a
///   margin is never read without its denominator.
///
/// **Revenue is the lines' own**, as `ProductSales` has it: units kept, at the
/// price they were sold at, before order-level discounts (which belong to no one
/// line) and with a refunded unit taken off.
///
/// **It is without tax.** On a restaurant whose prices exclude tax the lines are
/// already net. Where prices **include** tax ([ProfitReport.pricesIncludeTax])
/// the tax is taken back out, because a margin measured on money that was
/// handed to the tax authority is a margin nobody earned. The lines do not
/// store their tax, so it is taken out **order by order**: each line's revenue
/// is scaled by its order's recorded net-to-gross ratio (`pos_order_taxes`).
/// That is exact for an order taxed at one rate, and an **estimate** for one
/// that mixes rates — a zero-rated item beside a 14% one is shared out at the
/// order's blend. The page and the file say so. An order with no recorded tax
/// is left as it is: there is nothing to take out.
///
/// The revenue on this report therefore will not match the Items list above it
/// on an inclusive restaurant, which is gross; the column says which it is.
///
/// **Cost is what left the shelf, refunded or not.** A refund writes no stock
/// movement, so the food a refunded plate used is still spent; the revenue came
/// back and the cost did not. That is the conservative reading — it can only
/// understate profit — and it is the one the ledger can actually support.
library;

import '../../core/money/money.dart';
import '../../core/money/rounding.dart';
import 'sales_report.dart' show ReportFilter;

/// One product's revenue and, where known, what it cost.
class ProductProfit {
  const ProductProfit({
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.costedRevenue,
    required this.cost,
  });

  /// Null for a line that names no menu item — an open-price charge or a combo.
  /// Never costed.
  final int? menuItemId;

  /// The name on the most recent line sold.
  final String name;

  /// Whole units kept.
  final int quantity;

  /// Everything this product sold for, kept units at their sold price.
  final Money revenue;

  /// The part of [revenue] whose cost is known: the sales that recorded a real
  /// carrying cost. Equal to [revenue] for an item that was always costed, and
  /// less for one that was sold before its first delivery.
  final Money costedRevenue;

  /// What those costed sales cost. Null when none of them were costed — which
  /// is not zero, and is shown as a dash.
  final Money? cost;

  bool get isCosted => cost != null;

  /// [costedRevenue] less [cost]. Negative is a loss, and is reported as one.
  Money? get profit => cost == null ? null : costedRevenue - cost!;

  /// Profit as a share of the costed revenue, in basis points (3500 = 35%).
  /// Null when there is no cost, or no revenue to be a share of.
  int? get marginBp => marginOf(profit, costedRevenue);
}

/// [profit] as basis points of [revenue], half-up, rounded once.
///
/// Null rather than zero for no revenue: a zero margin is a claim about sales,
/// and there were none.
int? marginOf(Money? profit, Money revenue) {
  if (profit == null || revenue.minor <= 0) return null;
  return roundHalfUp(profit.minor * 10000, revenue.minor);
}

/// The range's profit, by product, with what it does not cover.
class ProfitReport {
  ProfitReport({
    required this.filter,
    required List<ProductProfit> products,
    required this.pricesIncludeTax,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : products = List.unmodifiable(products);

  final ReportFilter filter;

  /// Highest profit first, uncosted products after, by revenue.
  final List<ProductProfit> products;

  /// The restaurant prices tax into the menu. Every revenue figure here has
  /// then had it taken out — exactly for an order at one rate, by estimate for
  /// a mixed one (see the library comment) — and the page says so.
  final bool pricesIncludeTax;

  final String currency;
  final int exponent;

  Money _sum(Iterable<int> minors) => Money(
    minors.fold(0, (a, b) => a + b),
    currency: currency,
    exponent: exponent,
  );

  /// Everything the lines sold for, costed or not.
  Money get revenue => _sum(products.map((p) => p.revenue.minor));

  /// The part of [revenue] the report can speak to.
  Money get costedRevenue => _sum(products.map((p) => p.costedRevenue.minor));

  /// What the costed sales cost.
  Money get cost => _sum(products.map((p) => p.cost?.minor ?? 0));

  /// Revenue the report cannot speak to: dishes, combos, open charges, and
  /// stocked items sold before they had a cost.
  Money get uncostedRevenue => revenue - costedRevenue;

  /// Gross profit **on the costed revenue only** — never presented as the
  /// business's profit.
  Money get profit => costedRevenue - cost;

  int? get marginBp => marginOf(profit, costedRevenue);

  /// How much of the revenue is costed, in basis points. Null with no revenue.
  int? get coverageBp => revenue.minor <= 0
      ? null
      : roundHalfUp(costedRevenue.minor * 10000, revenue.minor);

  /// Nothing costed at all: the page says how to get a cost (receive stock)
  /// rather than showing a column of dashes.
  bool get hasAnyCost => products.any((p) => p.isCosted);

  /// Ranks [products] for display: costed by profit, loss-makers last among
  /// them, then the uncosted by revenue. A stable, total order, so two reads
  /// of the same ledger draw the same page.
  static List<ProductProfit> ranked(Iterable<ProductProfit> products) {
    final list = products.toList();
    list.sort((a, b) {
      if (a.isCosted != b.isCosted) return a.isCosted ? -1 : 1;
      if (a.isCosted) {
        final byProfit = b.profit!.minor.compareTo(a.profit!.minor);
        if (byProfit != 0) return byProfit;
      }
      final byRevenue = b.revenue.minor.compareTo(a.revenue.minor);
      if (byRevenue != 0) return byRevenue;
      return a.name.compareTo(b.name);
    });
    return list;
  }
}
