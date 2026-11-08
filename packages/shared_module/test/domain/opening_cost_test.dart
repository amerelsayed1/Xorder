import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/domain/services/stock_costing.dart';

/// Giving an item nothing has costed its first cost.
///
/// The rule is narrow on purpose: only a cost above zero, only on an item that
/// has none, and quantity is never touched — a count and a price are different
/// claims, and this makes one of them.
void main() {
  StockPosition held(int milli, {int cost = 0}) =>
      StockPosition(onHand: Quantity(milli), unitCost: Money(cost));

  group('what is refused', () {
    test('a cost of zero — it is the state being left', () {
      expect(
        OpeningCost.refusal(held(5000), Money.zero),
        OpeningCostProblem.notPositive,
      );
    });

    test('a negative cost', () {
      expect(
        OpeningCost.refusal(held(5000), const Money(-1)),
        OpeningCostProblem.notPositive,
      );
    });

    test('an item that already has a cost: that is a revaluation', () {
      expect(
        OpeningCost.refusal(held(5000, cost: 300), const Money(400)),
        OpeningCostProblem.alreadyCosted,
      );
    });

    test('zero is reported before "already costed"', () {
      // The more basic mistake first, so the message is about what was typed.
      expect(
        OpeningCost.refusal(held(5000, cost: 300), Money.zero),
        OpeningCostProblem.notPositive,
      );
    });
  });

  group('what is allowed', () {
    test('a first cost on an item with stock', () {
      expect(OpeningCost.refusal(held(5000), const Money(350)), isNull);
    });

    test('a first cost on an item with nothing on hand yet', () {
      expect(OpeningCost.refusal(held(0), const Money(350)), isNull);
    });

    test('a first cost on an item that is short — sold what never arrived', () {
      expect(OpeningCost.refusal(held(-2000), const Money(350)), isNull);
    });
  });

  group('applying it', () {
    test('sets the cost and leaves the quantity exactly as it was', () {
      final after = OpeningCost.apply(held(12500), const Money(350));

      expect(after.unitCost.minor, 350);
      expect(after.onHand.milli, 12500);
    });

    test('keeps a shortage a shortage', () {
      final after = OpeningCost.apply(held(-2000), const Money(350));

      expect(after.onHand.milli, -2000);
    });

    test('values what is on the shelf at the new cost', () {
      // 12.5 units at 3.50.
      expect(OpeningCost.apply(held(12500), const Money(350)).value.minor, 4375);
    });
  });

  group('why it matters to the next delivery', () {
    test('after an opening cost, receiving averages against it', () {
      final costed = OpeningCost.apply(held(10000), const Money(300));

      final after = StockCosting.receive(
        costed,
        received: const Quantity(10000),
        unitCost: const Money(500),
      );

      // 10 at 3.00 and 10 at 5.00 is 20 at 4.00.
      expect(after.unitCost.minor, 400);
    });

    test('without one, the uncosted stock drags the average toward zero', () {
      // The existing behaviour this makes avoidable: ten units nobody priced
      // are blended in at nothing, so the first delivery reads as half its cost.
      final after = StockCosting.receive(
        held(10000),
        received: const Quantity(10000),
        unitCost: const Money(500),
      );

      expect(after.unitCost.minor, 250);
    });
  });
}
