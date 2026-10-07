import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/domain/models/stock_level.dart';

/// What the stock is worth, and how much of it that figure leaves out.
///
/// The rule under test: an item nothing has ever received has an UNKNOWN worth,
/// so it is out of the total and counted beside it — never added as zero, which
/// would let the total read as the whole shelf.
void main() {
  StockLevel level(
    String name, {
    required int onHandMilli,
    required int cost,
  }) => StockLevel(
    productId: name.hashCode,
    nameEn: name,
    onHand: Quantity(onHandMilli),
    unitCost: Money(cost),
  );

  test('costed items are summed at their average cost', () {
    final v = StockValuation.of([
      level('Cola', onHandMilli: 48000, cost: 500), // 240.00
      level('Beef', onHandMilli: 12500, cost: 9500), // 1,187.50
    ]);

    expect(v.total.minor, 24000 + 118750);
    expect(v.unvalued, 0);
    expect(v.isComplete, isTrue);
  });

  test('an uncosted item with stock is out of the total and counted', () {
    final v = StockValuation.of([
      level('Cola', onHandMilli: 48000, cost: 500),
      level('Ketchup', onHandMilli: 6000, cost: 0),
    ]);

    expect(v.total.minor, 24000, reason: 'the Ketchup is not added as zero');
    expect(v.unvalued, 1);
    expect(v.isComplete, isFalse);
  });

  test('every uncosted item with stock is counted', () {
    final v = StockValuation.of([
      level('Ketchup', onHandMilli: 6000, cost: 0),
      level('Mayo', onHandMilli: 2000, cost: 0),
      level('Cola', onHandMilli: 48000, cost: 500),
    ]);

    expect(v.unvalued, 2);
  });

  test('an uncosted item with nothing on hand leaves nothing out', () {
    final v = StockValuation.of([
      level('Cola', onHandMilli: 48000, cost: 500),
      level('Ketchup', onHandMilli: 0, cost: 0),
    ]);

    expect(v.unvalued, 0);
    expect(v.isComplete, isTrue);
  });

  test('an uncosted shortage is not stock to value either', () {
    // Sold what never arrived: a line to look at, not a shelf to price.
    final v = StockValuation.of([
      level('Ketchup', onHandMilli: -2000, cost: 0),
    ]);

    expect(v.unvalued, 0);
  });

  test('a costed shortage still counts against the total, as it always did', () {
    final v = StockValuation.of([
      level('Cola', onHandMilli: 48000, cost: 500), // +240.00
      level('Milk', onHandMilli: -2000, cost: 6000), // −120.00
    ]);

    expect(v.total.minor, 24000 - 12000);
  });

  test('no items at all is a complete zero', () {
    final v = StockValuation.of(const []);

    expect(v.total.minor, 0);
    expect(v.isComplete, isTrue);
  });
}
