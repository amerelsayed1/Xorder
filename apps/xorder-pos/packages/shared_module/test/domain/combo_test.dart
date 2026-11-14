import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/combo.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

/// Combos — a meal at one price.
///
/// The claim that matters: **a combo is not the sum of its parts.** 85.00 is
/// less than 45 + 25 + 20, and that is the entire reason one exists. The
/// components' own prices are never consulted.
void main() {
  Product item(int id, int price, {String? name}) => Product(
    id: id,
    categoryId: 1,
    nameEn: name ?? 'Item $id',
    price: Money(price),
  );

  ComboOption option(int id, Product product, {int delta = 0}) =>
      ComboOption(id: id, product: product, priceDelta: Money(delta));

  final sandwich = item(1, 4500, name: 'Chicken sandwich');
  final beef = item(2, 5500, name: 'Beef sandwich');
  final chips = item(3, 2500, name: 'Chips');
  final largeChips = item(4, 3500, name: 'Large chips');
  final cola = item(5, 2000, name: 'Cola');

  Combo meal({
    int price = 8500,
    int? taxGroupId,
    bool isAvailable = true,
    List<ComboGroup>? groups,
  }) => Combo(
    id: 90,
    categoryId: 1,
    nameEn: 'Lunch meal',
    nameAr: 'وجبة الغداء',
    price: Money(price),
    taxGroupId: taxGroupId,
    isAvailable: isAvailable,
    groups:
        groups ??
        [
          ComboGroup(
            id: 1,
            nameEn: 'Sandwich',
            options: [option(11, sandwich), option(12, beef, delta: 1000)],
          ),
          ComboGroup(
            id: 2,
            nameEn: 'Side',
            options: [option(21, chips), option(22, largeChips, delta: 500)],
          ),
          ComboGroup(id: 3, nameEn: 'Drink', options: [option(31, cola)]),
        ],
  );

  Ticket empty() => Ticket(
    id: 'txn',
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
  );

  Ticket ok(TicketResult result) {
    expect(result.refusal, isNull, reason: '${result.refusal.runtimeType}');
    return result.ticket!;
  }

  group('pricing', () {
    test('is the combo price, not the sum of the parts', () {
      final combo = meal();
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );

      // The parts come to 90.00; the meal is 85.00.
      expect(t.lines.single.unitPrice.minor, 8500);
      expect(t.totals.subtotal.minor, 8500);
    });

    test('upgrades are added on top', () {
      final combo = meal();
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[1], // beef, +10.00
            combo.groups[1].options[1], // large chips, +5.00
            combo.groups[2].options[0],
          ],
        ),
      );
      expect(t.lines.single.unitPrice.minor, 8500 + 1000 + 500);
    });

    test('quantity multiplies the meal', () {
      final combo = meal();
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
          quantity: 3,
        ),
      );
      expect(t.totals.subtotal.minor, 25500);
    });

    test('modifiers do not apply to a meal', () {
      // A modifier belongs to an item; the components are real items. A combo
      // line has none, and its price ignores the product it borrows.
      final combo = meal();
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );
      expect(t.lines.single.modifiers, isEmpty);
      expect(t.lines.single.menuUnitPrice.minor, 8500);
    });
  });

  group('what it records', () {
    test('the components, so the kitchen knows what to make', () {
      final combo = meal();
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[1],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );

      final selection = t.lines.single.combo!;
      expect(selection.items.map((i) => i.nameEn), [
        'Beef sandwich',
        'Chips',
        'Cola',
      ]);
      // Real menu items, not modifiers — the kitchen has to make each of them.
      expect(selection.items.map((i) => i.menuItemId), [2, 3, 5]);
    });

    test('a snapshot, not a live lookup', () {
      // A combo repriced next week must not reprice a table still sitting
      // there.
      final combo = meal(price: 8500);
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );

      final selection = t.lines.single.combo!;
      expect(selection.price.minor, 8500);
      expect(selection.nameEn, 'Lunch meal');
      expect(selection.comboId, 90);
    });

    test('it reads as a meal in both languages', () {
      final combo = meal();
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );

      final selection = t.lines.single.combo!;
      expect(selection.displayName('ar'), 'وجبة الغداء');
      expect(selection.displayName('en'), 'Lunch meal');
      expect(selection.summary('en'), 'Chicken sandwich · Chips · Cola');
    });

    test('two different meals stay two lines', () {
      final combo = meal();
      var t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );
      t = ok(
        TicketEngine.addComboLine(
          t,
          combo,
          chosen: [
            combo.groups[0].options[1],
            combo.groups[1].options[1],
            combo.groups[2].options[0],
          ],
        ),
      );

      // Merging them would show `2×` at whichever price came first, with one
      // set of components and the other silently gone.
      expect(t.lines, hasLength(2));
      expect(t.totals.subtotal.minor, 8500 + 10000);
    });
  });

  group('what is refused', () {
    test('a group left unanswered', () {
      final combo = meal();
      final result = TicketEngine.addComboLine(
        empty(),
        combo,
        chosen: [combo.groups[0].options[0]],
      );
      expect(result.refusal, isA<ComboGroupUnsatisfied>());
    });

    test('more from a group than it allows', () {
      final combo = meal();
      final result = TicketEngine.addComboLine(
        empty(),
        combo,
        chosen: [
          combo.groups[0].options[0],
          combo.groups[0].options[1],
          combo.groups[1].options[0],
          combo.groups[2].options[0],
        ],
      );
      expect(result.refusal, isA<ComboTooManyChosen>());
    });

    test('a combo that is off', () {
      final combo = meal(isAvailable: false);
      final result = TicketEngine.addComboLine(
        empty(),
        combo,
        chosen: combo.fixedSelection,
      );
      expect(result.refusal, isA<OutOfStock>());
    });

    test('a quantity of nothing', () {
      final combo = meal();
      final result = TicketEngine.addComboLine(
        empty(),
        combo,
        chosen: [
          combo.groups[0].options[0],
          combo.groups[1].options[0],
          combo.groups[2].options[0],
        ],
        quantity: 0,
      );
      expect(result.refusal, isNotNull);
    });
  });

  group('a fixed meal asks nothing', () {
    test('one option per group and all required is fixed', () {
      final fixed = meal(
        groups: [
          ComboGroup(id: 1, nameEn: 'Sandwich', options: [option(11, sandwich)]),
          ComboGroup(id: 2, nameEn: 'Drink', options: [option(31, cola)]),
        ],
      );
      // Three taps to say the only thing that could be said.
      expect(fixed.isFixed, isTrue);
      expect(fixed.fixedSelection, hasLength(2));
    });

    test('a real choice is not fixed', () {
      expect(meal().isFixed, isFalse);
    });

    test('the fixed selection rings up', () {
      final fixed = meal(
        groups: [
          ComboGroup(id: 1, nameEn: 'Sandwich', options: [option(11, sandwich)]),
        ],
      );
      final t = ok(
        TicketEngine.addComboLine(
          empty(),
          fixed,
          chosen: fixed.fixedSelection,
        ),
      );
      expect(t.lines.single.unitPrice.minor, 8500);
    });
  });

  group('it behaves like any other line', () {
    test('taxed at the combo’s own rate, not a component’s', () {
      const standard = TaxGroup(
        id: 1,
        nameEn: 'VAT',
        rateBp: 1400,
        isDefault: true,
      );
      const zero = TaxGroup(id: 2, nameEn: 'Zero', rateBp: 0);

      final combo = meal(taxGroupId: 2);
      final t = ok(
        TicketEngine.addComboLine(
          Ticket(
            id: 'txn',
            orderType: OrderType.takeaway,
            taxConfig: const TaxConfig(
              serviceBp: 0,
              vatBp: 1400,
              taxGroups: [standard, zero],
            ),
          ),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );

      // A meal is taxed as a meal, not as whichever component the merge key
      // happens to name.
      expect(t.totals.vat.minor, 0);
      expect(t.totals.taxLines.single.rateBp, 0);
    });

    test('it can be voided', () {
      final combo = meal();
      var t = ok(
        TicketEngine.addComboLine(
          empty(),
          combo,
          chosen: [
            combo.groups[0].options[0],
            combo.groups[1].options[0],
            combo.groups[2].options[0],
          ],
        ),
      );
      t = t.copyWith(
        lines: [t.lines.single.copyWith(stage: LineStage.sent)],
      );
      t = ok(
        TicketEngine.voidLine(
          t,
          t.lines.single.key,
          by: 4,
          now: DateTime(2026, 9, 8),
        ),
      );
      expect(t.totals.subtotal.minor, 0);
      expect(t.lines, hasLength(1));
    });
  });
}
