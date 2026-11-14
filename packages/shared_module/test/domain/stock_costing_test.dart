import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/domain/services/stock_costing.dart';

/// What stock costs, after something arrives at a different price.
///
/// Moving average, chosen over last-cost and FIFO. Every profit number the
/// reports will ever show starts here, so the tests are arithmetic first and
/// behaviour second — and the arithmetic is checkable by eye on purpose.
void main() {
  const kg = QuantityUnit.kilogram;

  StockPosition position(int milli, int cost) => StockPosition(
    onHand: Quantity(milli, unit: kg),
    unitCost: Money(cost),
  );

  group('the average moves, weighted by quantity', () {
    test('the textbook case', () {
      // 10 kg at 40.00 plus 10 kg at 50.00 is 20 kg at 45.00.
      final after = StockCosting.receive(
        position(10000, 4000),
        received: const Quantity(10000, unit: kg),
        unitCost: const Money(5000),
      );

      expect(after.onHand.milli, 20000);
      expect(after.unitCost.minor, 4500);
    });

    test('it is weighted, not a midpoint', () {
      // 30 kg at 40.00 plus 10 kg at 60.00 is 40 kg at 45.00 — not 50.00,
      // which a naive average of the two prices would give.
      final after = StockCosting.receive(
        position(30000, 4000),
        received: const Quantity(10000, unit: kg),
        unitCost: const Money(6000),
      );
      expect(after.unitCost.minor, 4500);
    });

    test('a fractional delivery still lands on a whole piastre', () {
      // 12.5 kg at 47.30 into 7.5 kg at 44.00 — 921.25 over 20 kg = 46.0625,
      // which rounds to 46.06.
      final after = StockCosting.receive(
        position(7500, 4400),
        received: const Quantity(12500, unit: kg),
        unitCost: const Money(4730),
      );
      expect(after.onHand.milli, 20000);
      expect(after.unitCost.minor, 4606);
    });

    test('the value it implies is the value that went in', () {
      // The property that matters more than any single figure: what the stock
      // is worth after a delivery is what it was worth before plus what
      // arrived, to within the one rounding.
      final before = position(7000, 4400);
      final after = StockCosting.receive(
        before,
        received: const Quantity(3000, unit: kg),
        unitCost: const Money(5100),
      );

      final expected = before.value.minor + const Quantity(3000).costAt(5100);
      expect((after.value.minor - expected).abs(), lessThanOrEqualTo(1));
    });
  });

  group('the cases that are not an average', () {
    test('nothing on hand takes the arriving price', () {
      final after = StockCosting.receive(
        StockPosition.nothing,
        received: const Quantity(10000, unit: kg),
        unitCost: const Money(4730),
      );
      expect(after.unitCost.minor, 4730);
      expect(after.onHand.milli, 10000);
    });

    test('negative on hand takes it too, and the debt settles', () {
      // The day somebody starts using this properly, the kitchen has already
      // used stock the system never saw arrive. Averaging against a negative
      // produces a cost that can be negative or absurd, and a nonsense cost
      // silently poisons every margin downstream.
      final after = StockCosting.receive(
        position(-2000, 9999),
        received: const Quantity(10000, unit: kg),
        unitCost: const Money(4730),
      );

      expect(after.unitCost.minor, 4730, reason: 'not averaged against a debt');
      expect(after.onHand.milli, 8000, reason: 'but the quantity settles');
    });

    test('receiving nothing changes nothing', () {
      final before = position(10000, 4000);
      final after = StockCosting.receive(
        before,
        received: Quantity.zero,
        unitCost: const Money(9999),
      );
      expect(after.unitCost.minor, 4000);
      expect(after.onHand.milli, 10000);
    });

    test('a free delivery drops the average rather than being ignored', () {
      // A supplier replacing a spoiled crate at no charge genuinely does lower
      // what the stock cost.
      final after = StockCosting.receive(
        position(10000, 4000),
        received: const Quantity(10000, unit: kg),
        unitCost: Money.zero,
      );
      expect(after.unitCost.minor, 2000);
    });
  });

  group('issuing', () {
    test('does not move the cost', () {
      // The whole point of a moving average: stock leaves at the average it
      // was carried at. Recalculating here would make last month's margin
      // depend on this month's sales.
      final after = StockCosting.issue(
        position(10000, 4500),
        issued: const Quantity(3000, unit: kg),
      );
      expect(after.unitCost.minor, 4500);
      expect(after.onHand.milli, 7000);
    });

    test('is allowed to go negative', () {
      // A business selling something the system does not know arrived is
      // telling the truth about the sale and the wrong thing about the stock.
      // Refusing the sale to protect the number would be the wrong way round.
      final after = StockCosting.issue(
        position(1000, 4500),
        issued: const Quantity(3000, unit: kg),
      );
      expect(after.onHand.milli, -2000);
    });

    test('issuing nothing changes nothing', () {
      final before = position(10000, 4500);
      expect(
        StockCosting.issue(before, issued: Quantity.zero).onHand.milli,
        10000,
      );
    });
  });

  group('what it cost to sell', () {
    test('is the average at the moment it left', () {
      final cost = StockCosting.costOfGoods(
        position(10000, 4500),
        issued: const Quantity(3000, unit: kg),
      );
      expect(cost.minor, 13500);
    });

    test('and not the average after a later delivery moved it', () {
      // Computed from the position before the issue. A COGS that moved when
      // next week's delivery arrived would make every historic margin drift.
      final before = position(10000, 4500);
      final sold = StockCosting.costOfGoods(
        before,
        issued: const Quantity(3000, unit: kg),
      );

      StockCosting.receive(
        StockCosting.issue(before, issued: const Quantity(3000, unit: kg)),
        received: const Quantity(10000, unit: kg),
        unitCost: const Money(9000),
      );

      expect(sold.minor, 13500, reason: 'unchanged by what happened after');
    });

    test('a fractional issue rounds once', () {
      final cost = StockCosting.costOfGoods(
        position(10000, 3333),
        issued: const Quantity(333, unit: kg),
      );
      expect(cost.minor, 1110, reason: '0.333 × 33.33 = 11.0989 → 11.10');
    });
  });

  group('valuation', () {
    test('is quantity times the average', () {
      expect(position(12500, 4730).value.minor, 59125);
    });

    test('nothing on hand is worth nothing', () {
      expect(StockPosition.nothing.value.minor, 0);
    });

    test('negative stock is worth a negative — it is not hidden', () {
      // A valuation that clamped at zero would let a business hold an
      // unrecorded liability that nothing on the screen adds up to.
      expect(position(-2000, 4500).value.minor, -9000);
    });
  });

  test('receiving a different unit into stock is an assertion', () {
    // A product is bought in one unit, and converting silently is how a stock
    // figure stops meaning anything.
    expect(
      () => StockCosting.receive(
        position(10000, 4000),
        received: const Quantity(500, unit: QuantityUnit.gram),
        unitCost: const Money(4),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
