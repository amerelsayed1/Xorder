/// What stock costs, after something arrives at a different price.
///
/// **Moving average, chosen deliberately over last-cost and FIFO** (owner,
/// 9 September 2026). It survives a part delivery at a new price without lot
/// tracking, it needs no layer bookkeeping, and it is what most restaurant
/// systems in this market use — so a bookkeeper reading the numbers recognises
/// them. Last-cost would make a single expensive delivery reprice the whole
/// larder; FIFO would need every unit to remember which crate it came from.
///
/// The choice is not cheaply reversible once there is history, which is why it
/// is written down here rather than implied by the code.
///
/// **Pure, and integer end to end.** A cost per unit is minor units; a quantity
/// is thousandths. The average is a fold over arrivals, so it is the one number
/// in this product that cannot be recomputed from a filter — see the note on
/// storing it in `pos_products`.
library;

import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../core/money/rounding.dart';

/// Stock as it stands: how much, and what it cost on average.
class StockPosition {
  const StockPosition({required this.onHand, required this.unitCost});

  static const nothing = StockPosition(
    onHand: Quantity.zero,
    unitCost: Money.zero,
  );

  final Quantity onHand;

  /// The moving average, per whole unit.
  final Money unitCost;

  /// What the stock on hand is worth.
  ///
  /// The number an inventory valuation reports and a COGS calculation starts
  /// from — which is why the rounding lives in one place.
  Money get value => unitCost.copyWith(minor: onHand.costAt(unitCost.minor));
}

abstract final class StockCosting {
  /// The position after [received] arrives at [unitCost] each.
  ///
  /// The average is weighted by quantity:
  ///
  /// ```
  /// (value on hand + value arriving) ÷ (quantity on hand + quantity arriving)
  /// ```
  ///
  /// Two cases are not that, and both are deliberate:
  ///
  /// * **Nothing on hand** — the new cost is simply what just arrived. An
  ///   average weighted by zero is the arriving price anyway; saying so
  ///   explicitly avoids a division that only looks safe.
  /// * **Negative on hand** — the kitchen used stock the system had not
  ///   recorded arriving, which happens on the day somebody starts using this
  ///   properly. The arriving price wins rather than being averaged against a
  ///   debt, because averaging against negative stock produces a cost that can
  ///   be negative or absurd, and a nonsense cost silently poisons every margin
  ///   downstream. The quantity still settles the debt.
  static StockPosition receive(
    StockPosition position, {
    required Quantity received,
    required Money unitCost,
  }) {
    // Before the unit check, not after: receiving nothing is a no-op whatever
    // it was nominally denominated in, and `Quantity.zero` carries the default
    // unit — so asserting first would fire on a caller that is doing nothing
    // wrong.
    if (received.milli <= 0) return position;

    assert(
      received.unit == position.onHand.unit || position.onHand.milli == 0,
      'Receiving ${received.unit.wire} into ${position.onHand.unit.wire} — '
      'a product is bought in one unit, and converting silently is how a '
      'stock figure stops meaning anything.',
    );

    final settled = Quantity(
      position.onHand.milli + received.milli,
      unit: received.unit,
    );

    if (position.onHand.milli <= 0) {
      return StockPosition(onHand: settled, unitCost: unitCost);
    }

    final valueOnHand = position.onHand.costAt(position.unitCost.minor);
    final valueArriving = received.costAt(unitCost.minor);

    // Back to a per-unit cost: total value ÷ total quantity, with the
    // thousandths scaled out. Rounded half-up once, here, so that no caller
    // has to decide where a third of a piastre goes.
    final cost = roundHalfUp((valueOnHand + valueArriving) * 1000, settled.milli);

    return StockPosition(
      onHand: settled,
      unitCost: unitCost.copyWith(minor: cost),
    );
  }

  /// The position after [issued] leaves — a sale, or waste.
  ///
  /// **The cost does not move.** That is the whole point of a moving average:
  /// stock leaves at the average it was carried at, so issuing never reprices
  /// what remains. A method that recalculated here would be a method that made
  /// last month's margin depend on this month's sales.
  ///
  /// The quantity is allowed to go negative. A restaurant that sells something
  /// the system does not know arrived is telling the truth about the sale and
  /// the wrong thing about the stock, and refusing the sale to protect the
  /// number would be the wrong way round.
  static StockPosition issue(
    StockPosition position, {
    required Quantity issued,
  }) {
    if (issued.milli <= 0) return position;
    return StockPosition(
      onHand: Quantity(
        position.onHand.milli - issued.milli,
        unit: position.onHand.unit,
      ),
      unitCost: position.unitCost,
    );
  }

  /// What [issued] cost, at the average it was carried at.
  ///
  /// This is COGS for one movement, and it is computed from the position
  /// **before** the issue — the average at the moment the stock left, not the
  /// one after some later delivery moved it.
  static Money costOfGoods(StockPosition position, {required Quantity issued}) =>
      position.unitCost.copyWith(minor: issued.costAt(position.unitCost.minor));
}

/// Why an opening cost cannot be set.
///
/// Data, not a sentence: the screen words each one in its own language, and a
/// reason added here is a compile error in the message table.
enum OpeningCostProblem {
  /// Zero or below. A cost of zero is how "never received" looks on the ledger,
  /// so setting one would leave the item exactly as uncosted as it was.
  notPositive,

  /// It already has a cost. Changing one is a revaluation — a different act with
  /// different consequences for every margin measured against the old figure —
  /// and not something to do through a box meant for the first.
  alreadyCosted,

  /// The item is not counted here, so there is no stock to give a cost to.
  itemUnknown,
}

/// Setting the cost of an item nothing has ever costed.
///
/// **Only ever the first cost.** An item reaches "uncosted" by being set up as
/// counted and never received. Receiving gives it a cost, and until then every
/// sale of it is recorded at zero and its stock cannot be valued. This is the
/// other way in: a restaurant that starts using the system with stock already
/// on the shelf says what that stock cost. Quantity is untouched — that is a
/// count, and this is a price.
abstract final class OpeningCost {
  /// Null when [cost] may be set on [position]; otherwise why not.
  static OpeningCostProblem? refusal(StockPosition position, Money cost) {
    if (cost.minor <= 0) return OpeningCostProblem.notPositive;
    if (position.unitCost.minor > 0) return OpeningCostProblem.alreadyCosted;
    return null;
  }

  /// [position] with its cost set and its quantity as it was.
  static StockPosition apply(StockPosition position, Money cost) =>
      StockPosition(onHand: position.onHand, unitCost: cost);
}
