import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

/// Sizes and extras, priced the way the platform prices them.
///
/// The platform's rule (`MenuItem::displayPricing`, `PosPricingEngine`): a size
/// **replaces** the item's price, an extra **adds** to it, and the first
/// available size is the default the item is advertised at. Its bootstrap sends
/// a size's whole price in `price_delta_minor`, so a till that added it charged
/// a Medium Burger 85 + 85.
void main() {
  // As the platform sends it: the item's price is already its default size's.
  const burger = Product(
    id: 301,
    categoryId: 5,
    nameEn: 'Burger',
    price: Money(8500),
    modifierGroupIds: [44, 45],
  );

  const medium = Modifier(
    id: 91,
    groupId: 44,
    nameEn: 'Medium',
    priceDelta: Money(8500),
    isVariant: true,
  );
  const large = Modifier(
    id: 92,
    groupId: 44,
    nameEn: 'Large',
    priceDelta: Money(9900),
    isVariant: true,
  );
  const size = ModifierGroup(
    id: 44,
    nameEn: 'Size',
    isRequired: true,
    isVariant: true,
    modifiers: [medium, large],
  );

  const cheese = Modifier(
    id: 101,
    groupId: 45,
    nameEn: 'Cheese',
    priceDelta: Money(1000),
  );
  const bacon = Modifier(
    id: 102,
    groupId: 45,
    nameEn: 'Bacon',
    priceDelta: Money(2000),
  );
  const extras = ModifierGroup(
    id: 45,
    nameEn: 'Extras',
    maxSelect: 3,
    modifiers: [cheese, bacon],
  );

  Ticket ticket() => Ticket(id: 'size-pricing', orderType: OrderType.takeaway);

  TicketLine line(List<Modifier> chosen, {List<ModifierGroup>? groups}) =>
      TicketEngine.addLine(
        ticket(),
        burger,
        modifiers: chosen,
        groups: groups ?? const [size, extras],
      ).ticket!.lines.single;

  group('a size is the price', () {
    test('a Medium Burger is 85, not 85 + 85', () {
      expect(line([medium]).unitPrice, const Money(8500));
    });

    test('a Large replaces the price, whatever the item says', () {
      expect(line([large]).unitPrice, const Money(9900));
    });

    test('an extra still adds, on top of the size', () {
      expect(line([large, cheese, bacon]).unitPrice, const Money(12900));
    });

    test('the order they were tapped in does not matter', () {
      expect(
        line([cheese, large]).unitPrice,
        line([large, cheese]).unitPrice,
      );
    });

    test('an item without sizes keeps its own price', () {
      expect(line([cheese], groups: const [extras]).unitPrice,
          const Money(9500));
    });

    test('a free allowance never makes the size free', () {
      const generous = ModifierGroup(
        id: 44,
        nameEn: 'Size',
        isRequired: true,
        isVariant: true,
        freeOptions: 1,
        modifiers: [medium, large],
      );
      expect(line([large], groups: const [generous, extras]).unitPrice,
          const Money(9900));
    });

    test('the sheet and the ticket use the one rule', () {
      expect(
        priceWithOptions(burger, const [large, cheese]),
        line([large, cheese]).unitPrice,
      );
    });
  });

  group('what the sheet opens on', () {
    test('the first size', () {
      expect(TicketEngine.defaultSelection(const [size, extras]), [medium]);
    });

    test('the first AVAILABLE size, as the platform advertises it', () {
      const outOfMedium = ModifierGroup(
        id: 44,
        nameEn: 'Size',
        isRequired: true,
        isVariant: true,
        modifiers: [
          Modifier(
            id: 91,
            groupId: 44,
            nameEn: 'Medium',
            priceDelta: Money(8500),
            isVariant: true,
            isAvailable: false,
          ),
          large,
        ],
      );
      expect(TicketEngine.defaultSelection(const [outOfMedium]), [large]);
    });

    test('a required pick-one group opens on its first option too', () {
      const doneness = ModifierGroup(
        id: 7,
        nameEn: 'Doneness',
        isRequired: true,
        modifiers: [
          Modifier(id: 71, groupId: 7, nameEn: 'Medium', priceDelta: Money.zero),
          Modifier(id: 72, groupId: 7, nameEn: 'Well', priceDelta: Money.zero),
        ],
      );
      expect(
        TicketEngine.defaultSelection(const [doneness]).map((m) => m.id),
        [71],
      );
    });

    test('a size opens on the first available one, whatever is marked', () {
      // The tile advertises the first available size; a sheet opening on a
      // marked Large would charge a figure the tile never showed.
      const marked = ModifierGroup(
        id: 44,
        nameEn: 'Size',
        isRequired: true,
        isVariant: true,
        modifiers: [
          medium,
          Modifier(
            id: 92,
            groupId: 44,
            nameEn: 'Large',
            priceDelta: Money(9900),
            isVariant: true,
            isDefault: true,
          ),
        ],
      );
      expect(TicketEngine.defaultSelection(const [marked]), [medium]);
    });

    test('optional extras open empty', () {
      expect(TicketEngine.defaultSelection(const [extras]), isEmpty);
    });

    test('an option marked as a default is ticked', () {
      const withDefault = ModifierGroup(
        id: 45,
        nameEn: 'Extras',
        maxSelect: 3,
        modifiers: [
          cheese,
          Modifier(
            id: 102,
            groupId: 45,
            nameEn: 'Bacon',
            priceDelta: Money(2000),
            isDefault: true,
          ),
        ],
      );
      expect(
        TicketEngine.defaultSelection(const [withDefault]).map((m) => m.id),
        [102],
      );
    });
  });
}
