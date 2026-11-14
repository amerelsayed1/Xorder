import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

/// Free allowances, defaults and minimum selections.
///
/// "Two toppings included, then 5.00 each" is how half the market prices a
/// pizza, and the schema could express neither half of that sentence.
void main() {
  Modifier topping(int id, int price, {bool isDefault = false}) => Modifier(
    id: id,
    groupId: 1,
    nameEn: 'Topping $id',
    priceDelta: Money(price),
    isDefault: isDefault,
  );

  // Named `toppings`, not `group`: a local helper called `group` shadows the
  // test framework's own `toppings()`, and the failure reads as an argument-count
  // error rather than as a name collision.
  ModifierGroup toppings({
    int freeOptions = 0,
    int minSelect = 0,
    int maxSelect = 4,
    bool isRequired = false,
    List<Modifier>? modifiers,
  }) => ModifierGroup(
    id: 1,
    nameEn: 'Toppings',
    modifiers: modifiers ?? [topping(1, 500), topping(2, 800), topping(3, 300)],
    freeOptions: freeOptions,
    minSelect: minSelect,
    maxSelect: maxSelect,
    isRequired: isRequired,
  );

  const pizza = Product(
    id: 101,
    categoryId: 1,
    nameEn: 'Pizza',
    price: Money(10000),
  );

  Ticket add(ModifierGroup g, List<Modifier> chosen) => TicketEngine.addLine(
    Ticket(
      id: 'txn',
      orderType: OrderType.takeaway,
      taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    ),
    pizza,
    modifiers: chosen,
    groups: [g],
  ).ticket!;

  group('free options', () {
    test('none chosen costs the base price', () {
      final t = add(toppings(freeOptions: 2), const []);
      expect(t.lines.single.unitPrice.minor, 10000);
    });

    test('within the allowance costs nothing extra', () {
      final g = toppings(freeOptions: 2);
      final t = add(g, [g.modifiers[0], g.modifiers[1]]);
      expect(t.lines.single.unitPrice.minor, 10000);
      // Both are still on the line — the kitchen needs them and so does the
      // receipt. They are simply not charged for.
      expect(t.lines.single.modifiers, hasLength(2));
    });

    test('past the allowance charges the dearest', () {
      // One free of {5.00, 8.00, 3.00}: the free one is the 3.00, so 13.00 is
      // charged. Anything else makes the price depend on tap order, which a
      // customer notices and a cashier cannot explain.
      final g = toppings(freeOptions: 1);
      final t = add(g, [g.modifiers[0], g.modifiers[1], g.modifiers[2]]);
      expect(t.lines.single.unitPrice.minor, 10000 + 500 + 800);
    });

    test('the order they were tapped in does not change the price', () {
      final g = toppings(freeOptions: 1);
      final forwards = add(g, [g.modifiers[0], g.modifiers[1], g.modifiers[2]]);
      final backwards = add(g, [g.modifiers[2], g.modifiers[1], g.modifiers[0]]);
      expect(
        forwards.lines.single.unitPrice.minor,
        backwards.lines.single.unitPrice.minor,
      );
    });

    test('no allowance charges for everything, as before', () {
      final g = toppings();
      final t = add(g, [g.modifiers[0], g.modifiers[1]]);
      expect(t.lines.single.unitPrice.minor, 10000 + 500 + 800);
    });

    test('an allowance larger than the choice charges nothing', () {
      final g = toppings(freeOptions: 5);
      final t = add(g, [g.modifiers[0]]);
      expect(t.lines.single.unitPrice.minor, 10000);
    });

    test('the allowance is a snapshot, not a live lookup', () {
      // A group edited from "two free" to "none free" tomorrow must not
      // reprice a table that is still sitting there.
      final g = toppings(freeOptions: 2);
      final t = add(g, [g.modifiers[0], g.modifiers[1]]);

      final line = t.lines.single;
      expect(line.includedAllowance.minor, 1300);
      // Carried on the line itself, with no reference to the group.
      expect(line.unitPrice.minor, 10000);
    });

    test('it never drives a line below nothing', () {
      final negative = Modifier(
        id: 9,
        groupId: 1,
        nameEn: 'Remove cheese',
        priceDelta: const Money(-500),
      );
      final g = ModifierGroup(
        id: 1,
        nameEn: 'Toppings',
        modifiers: [negative],
        freeOptions: 0,
      );
      final t = add(g, [negative]);
      expect(t.lines.single.unitPrice.minor, 9500);
    });
  });

  group('minimum selection', () {
    test('a minimum of two blocks at one', () {
      final g = toppings(minSelect: 2);
      final refusal = TicketEngine.validateSelection(
        [g],
        [g.modifiers[0]],
      );
      // Blocks at one, not only at none — which `isRequired` alone could not
      // say.
      expect(refusal, isA<RequiredGroupUnsatisfied>());
    });

    test('two satisfies it', () {
      final g = toppings(minSelect: 2);
      expect(
        TicketEngine.validateSelection([g], [g.modifiers[0], g.modifiers[1]]),
        isNull,
      );
    });

    test('required with no explicit minimum still means one', () {
      final g = toppings(isRequired: true);
      expect(g.effectiveMinimum, 1);
      expect(TicketEngine.validateSelection([g], const []),
          isA<RequiredGroupUnsatisfied>());
      expect(TicketEngine.validateSelection([g], [g.modifiers[0]]), isNull);
    });

    test('an optional group with no minimum accepts nothing', () {
      expect(TicketEngine.validateSelection([toppings()], const []), isNull);
    });

    test('the maximum still applies', () {
      final g = toppings(maxSelect: 1, minSelect: 1);
      expect(
        TicketEngine.validateSelection([g], [g.modifiers[0], g.modifiers[1]]),
        isA<TooManySelected>(),
      );
    });
  });

  group('defaults', () {
    test('an option can say it starts selected', () {
      // "Regular size" already ticked is the difference between three taps and
      // one. The flag lives on the option; the sheet reads it.
      final regular = topping(1, 0, isDefault: true);
      expect(regular.isDefault, isTrue);
      expect(topping(2, 500).isDefault, isFalse);
    });
  });
}
