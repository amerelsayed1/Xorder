import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/parked_ticket_codec.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/combo.dart';
import 'package:xorder_pos/domain/models/discount.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

const _cheese = Modifier(id: 71, groupId: 7, nameEn: 'Cheese', priceDelta: Money(1500));
const _extras = ModifierGroup(id: 7, nameEn: 'Extras', maxSelect: 3, modifiers: [_cheese]);
const _burger = Product(
  id: 101,
  categoryId: 11,
  nameEn: 'Classic Burger',
  nameAr: 'برجر كلاسيك',
  price: Money(9500),
  modifierGroupIds: [7],
);

final _catalog = Catalog(
  categories: const [Category(id: 11, nameEn: 'Burgers')],
  products: const [_burger],
  modifierGroups: const [_extras],
  syncedAt: DateTime.utc(2026, 9, 5),
);

Ticket _parked() {
  var ticket = Ticket(id: 'txn-abc', orderType: OrderType.dineIn);
  ticket = TicketEngine.attachTable(ticket, 12, 'T12', guests: 3);
  ticket = TicketEngine.addLine(
    ticket,
    _burger,
    modifiers: const [_cheese],
    groups: const [_extras],
    quantity: 2,
    note: 'no onions',
  ).ticket!;
  ticket = TicketEngine.sendRound(ticket);
  ticket = TicketEngine.addTender(
    ticket,
    typeId: 1,
    label: 'Cash',
    amount: const Money(5000),
  ).ticket!;
  return ticket;
}

void main() {
  _comboTests();

  _priceOverrideTests();

  _tenderCashTests();

  test('a parked ticket round-trips exactly — id, money and stages included', () {
    final original = _parked();
    final json = jsonDecode(jsonEncode(ParkedTicketCodec.encode(original)))
        as Map<String, dynamic>;
    final restored =
        ParkedTicketCodec.decode(json.cast<String, Object?>(), _catalog)!;

    expect(restored.id, original.id,
        reason: 'the parked ticket IS the transaction — same idempotency key');
    expect(restored.tableId, 12);
    expect(restored.tableLabel, 'T12');
    expect(restored.guestCount, 3);
    expect(restored.roundsSent, 1);
    expect(restored.lines.single.quantity, 2);
    expect(restored.lines.single.stage, LineStage.sent);
    expect(restored.lines.single.note, 'no onions');
    expect(restored.lines.single.modifiers.single.id, 71);
    expect(restored.tenders.single.amount.minor, 5000);
    // The number that must not drift: the guest's bill.
    expect(restored.totals.total.minor, original.totals.total.minor);
  });

  test('a product deleted while parked settles from its snapshots', () {
    final original = _parked();
    final json = jsonDecode(jsonEncode(ParkedTicketCodec.encode(original)))
        as Map<String, dynamic>;

    final emptyCatalog = Catalog(
      categories: const [],
      products: const [],
      modifierGroups: const [],
      syncedAt: DateTime.utc(2026, 9, 5),
    );
    final restored = ParkedTicketCodec.decode(
        json.cast<String, Object?>(), emptyCatalog)!;

    // The bill the guests are eating from must not change because head
    // office edited the menu: names and prices come from the snapshots.
    expect(restored.lines.single.product.nameEn, 'Classic Burger');
    expect(restored.lines.single.product.price.minor, 9500);
    expect(restored.lines.single.modifiers.single.priceDelta.minor, 1500);
    expect(restored.totals.total.minor, original.totals.total.minor);
  });

  test('garbage decodes to null or the best partial ticket, never a throw', () {
    expect(ParkedTicketCodec.decode(const {}, _catalog), isNull);
    expect(
      ParkedTicketCodec.decode(const {'client_transaction_id': ''}, _catalog),
      isNull,
    );

    // A payload with a broken line keeps the ticket and drops the line.
    final partial = ParkedTicketCodec.decode(const {
      'client_transaction_id': 'txn-x',
      'order_type': 'dine_in',
      'lines': [
        {'product_id': 'not-an-int'},
        12,
      ],
    }, _catalog)!;
    expect(partial.id, 'txn-x');
    expect(partial.lines, isEmpty);
  });

  group('discounts survive a restart', () {
    /// The failure this guards against is not an exception — it is a parked
    /// table whose discount quietly vanishes overnight, so the guests are
    /// handed a larger bill in the morning with nothing on screen to say why.
    Ticket discounted() {
      var ticket = Ticket(id: 'txn-disc', orderType: OrderType.dineIn);
      ticket = TicketEngine.attachTable(ticket, 12, 'T12', guests: 2);
      ticket = TicketEngine.addLine(
        ticket,
        _burger,
        modifiers: const [_cheese],
        groups: const [_extras],
        quantity: 2,
      ).ticket!;
      return TicketEngine.applyLineDiscount(
        ticket,
        TicketLine.keyFor(_burger, const [_cheese]),
        const Discount(
          id: 31,
          code: 'staff',
          nameEn: 'Staff meal',
          kind: DiscountKind.percentage,
          scope: DiscountScope.item,
          valueBp: 2500,
        ),
        now: DateTime(2026, 9, 8, 12),
        appliedBy: 7,
        reasonId: 4,
        note: 'Kitchen team',
        approvedByName: 'Hana Mostafa',
      ).ticket!;
    }

    test('the bill is the same after a round trip through the database', () {
      final original = discounted();
      final wire =
          jsonDecode(jsonEncode(ParkedTicketCodec.encode(original)))
              as Map<String, Object?>;
      final restored = ParkedTicketCodec.decode(wire, _catalog)!;

      expect(restored.totals.discount.minor, original.totals.discount.minor);
      expect(restored.totals.total.minor, original.totals.total.minor);
      expect(restored.totals.discount.minor, greaterThan(0));
    });

    test('everything the audit will ask about comes back', () {
      final wire =
          jsonDecode(jsonEncode(ParkedTicketCodec.encode(discounted())))
              as Map<String, Object?>;
      final applied = ParkedTicketCodec.decode(wire, _catalog)!.discounts.single;

      expect(applied.discountId, 31);
      expect(applied.nameSnapshot, 'Staff meal');
      expect(applied.kind, DiscountKind.percentage);
      expect(applied.valueBp, 2500);
      expect(applied.reasonId, 4);
      expect(applied.note, 'Kitchen team');
      // An approved discount with no approver on the record is
      // indistinguishable from one nobody approved.
      expect(applied.approvedByName, 'Hana Mostafa');
    });

    test('it stays attached to the line it came off', () {
      final original = discounted();
      final key = original.discounts.single.lineKey;
      final wire =
          jsonDecode(jsonEncode(ParkedTicketCodec.encode(original)))
              as Map<String, Object?>;
      final restored = ParkedTicketCodec.decode(wire, _catalog)!;

      expect(restored.discountOnLine(key!), isNotNull);
      expect(restored.orderDiscounts, isEmpty);
    });

    test('a payload written before discounts existed decodes to none', () {
      // Every parked ticket already on a branch server. An absent key must mean
      // "no discount", not a crash and not an invented one.
      final restored = ParkedTicketCodec.decode(const {
        'client_transaction_id': 'txn-old',
        'order_type': 'dine_in',
      }, _catalog)!;

      expect(restored.discounts, isEmpty);
      expect(restored.totals.discount.isZero, isTrue);
    });

    test('an unreadable kind keeps the amount the guests were told', () {
      // The amount is already the answer — a fixed discount needs no rate to
      // re-price from — so a payload from a future build that names a kind this
      // one does not know still bills correctly.
      final restored = ParkedTicketCodec.decode(const {
        'client_transaction_id': 'txn-future',
        'order_type': 'takeaway',
        'discounts': [
          {'name_snapshot': 'Mystery', 'kind': 'buy_one_get_one', 'amount_minor': 750},
        ],
      }, _catalog)!;

      expect(restored.discounts.single.kind, DiscountKind.fixed);
      expect(restored.discounts.single.amount.minor, 750);
    });
  });
}

void _priceOverrideTests() {
  group('a repriced line survives a restart', () {
    Ticket repriced({Money price = const Money(8000)}) {
      var ticket = Ticket(id: 'txn-price', orderType: OrderType.dineIn);
      ticket = TicketEngine.attachTable(ticket, 12, 'T12', guests: 2);
      ticket = TicketEngine.addLine(
        ticket,
        _burger,
        modifiers: const [_cheese],
        groups: const [_extras],
        quantity: 2,
      ).ticket!;
      return TicketEngine.overridePrice(
        ticket,
        ticket.lines.single.key,
        price,
        by: 4,
        now: DateTime.utc(2026, 9, 7, 13),
        reasonId: 12,
        note: 'Regular customer',
        approvedByStaffId: 9,
        approvedByName: 'Hana Mostafa',
      ).ticket!;
    }

    test('the agreed price comes back, not the menu price', () {
      // A parked line that came back at list price overnight would hand the
      // guests a bill larger than the one they were quoted, with nothing on
      // screen to say why.
      final restored = ParkedTicketCodec.decode(
        (jsonDecode(jsonEncode(ParkedTicketCodec.encode(repriced()))) as Map).cast<String, Object?>(),
        _catalog,
      )!;

      final line = restored.lines.single;
      expect(line.isRepriced, isTrue);
      expect(line.unitPrice.minor, 8000);
      // 95.00 + 15.00 of cheese is what it would have been.
      expect(line.menuUnitPrice.minor, 11000);
      expect(line.lineTotal.minor, 16000);
    });

    test('the whole record comes back, both names included', () {
      final restored = ParkedTicketCodec.decode(
        (jsonDecode(jsonEncode(ParkedTicketCodec.encode(repriced()))) as Map).cast<String, Object?>(),
        _catalog,
      )!;

      final override = restored.lines.single.priceOverride!;
      expect(override.original.minor, 11000);
      expect(override.byStaffId, 4);
      expect(override.at, DateTime.utc(2026, 9, 7, 13));
      expect(override.reasonId, 12);
      expect(override.note, 'Regular customer');
      expect(override.approvedByStaffId, 9);
      expect(override.approvedByName, 'Hana Mostafa');
    });

    test('the price_overridden event round-trips with both figures', () {
      final restored = ParkedTicketCodec.decode(
        (jsonDecode(jsonEncode(ParkedTicketCodec.encode(repriced()))) as Map).cast<String, Object?>(),
        _catalog,
      )!;

      final event = restored.lineEvents.single;
      expect(event.event, 'price_overridden');
      expect(event.unitPriceBefore, 11000);
      expect(event.unitPriceAfter, 8000);
    });

    test('a comp round-trips as a comp, not as an absent override', () {
      // Zero is a real price. Decoding it as "no override" would put the item
      // back on the bill at full price.
      final restored = ParkedTicketCodec.decode(
        (jsonDecode(
              jsonEncode(
                ParkedTicketCodec.encode(repriced(price: Money.zero)),
              ),
            )
            as Map).cast<String, Object?>(),
        _catalog,
      )!;

      expect(restored.lines.single.isRepriced, isTrue);
      expect(restored.totals.subtotal.minor, 0);
    });

    test('an unreadable price decodes to zero, never to the menu price', () {
      // The safe direction. A line that came back free is wrong in a way
      // somebody notices at the counter; one that came back at list price
      // silently overcharges a guest who was quoted less.
      final encoded = ParkedTicketCodec.encode(repriced());
      ((encoded['lines'] as List).first as Map)['price_override'] =
          <String, Object?>{'by_staff_id': 4};

      final restored = ParkedTicketCodec.decode(
        (jsonDecode(jsonEncode(encoded)) as Map).cast<String, Object?>(),
        _catalog,
      )!;
      expect(restored.lines.single.unitPrice.minor, 0);
    });

    test('a line with no override decodes without one', () {
      var plain = Ticket(id: 'txn-plain', orderType: OrderType.takeaway);
      plain = TicketEngine.addLine(
        plain,
        _burger,
        groups: const [_extras],
      ).ticket!;

      final restored = ParkedTicketCodec.decode(
        (jsonDecode(jsonEncode(ParkedTicketCodec.encode(plain))) as Map).cast<String, Object?>(),
        _catalog,
      )!;
      expect(restored.lines.single.isRepriced, isFalse);
      expect(restored.lines.single.unitPrice.minor, 9500);
    });
  });
}

void _tenderCashTests() {
  group('a part-payment keeps whether it is in the drawer', () {
    /// The failure this guards against is not an exception. A partly paid
    /// table whose cash came back as "not cash" settles with
    /// `counts_as_cash = false`, so the cash-up expects less in the drawer than
    /// is there, and ETA is told the sale was paid by card.
    Ticket partlyPaid() {
      var ticket = Ticket(id: 'txn-part', orderType: OrderType.dineIn);
      ticket = TicketEngine.attachTable(ticket, 12, 'T12', guests: 2);
      ticket = TicketEngine.addLine(
        ticket,
        _burger,
        groups: const [_extras],
        quantity: 2,
      ).ticket!;
      ticket = TicketEngine.addTender(
        ticket,
        typeId: 1,
        label: 'Cash',
        amount: const Money(5000),
        countsAsCash: true,
      ).ticket!;
      // A cloud till's platform tender: an id above the seeded ones, which
      // the restaurant has said counts as cash. No lookup can recover that.
      ticket = TicketEngine.addTender(
        ticket,
        typeId: 17,
        label: 'Vodafone Cash',
        amount: const Money(3000),
        countsAsCash: true,
      ).ticket!;
      return TicketEngine.addTender(
        ticket,
        typeId: 2,
        label: 'Card',
        amount: const Money(2000),
        reference: 'AUTH-889',
      ).ticket!;
    }

    test('each tender comes back with the flag it was taken with', () {
      final restored = ParkedTicketCodec.decode(
        (jsonDecode(jsonEncode(ParkedTicketCodec.encode(partlyPaid()))) as Map)
            .cast<String, Object?>(),
        _catalog,
      )!;

      expect(restored.tenders.map((t) => t.countsAsCash), [true, true, false]);
      expect(restored.tenders.last.reference, 'AUTH-889');
    });

    test('a payload written before the flag existed falls back to the seeded '
        'list', () {
      // Every partly paid table already parked on a branch server when this
      // shipped. Seeded Cash is still cash; anything the seeded list does not
      // know is not — the one thing no fallback can get right.
      final restored = ParkedTicketCodec.decode(const {
        'client_transaction_id': 'txn-old',
        'order_type': 'dine_in',
        'tenders': [
          {'type_id': 1, 'label': 'Cash', 'amount_minor': 5000},
          {'type_id': 2, 'label': 'Card', 'amount_minor': 2000},
          {'type_id': 17, 'label': 'Vodafone Cash', 'amount_minor': 3000},
        ],
      }, _catalog)!;

      expect(restored.tenders.map((t) => t.countsAsCash), [true, false, false]);
    });
  });
}

void _comboTests() {
  group('a parked meal survives a restart', () {
    Ticket withCombo() {
      const sandwich = Product(
        id: 201,
        categoryId: 11,
        nameEn: 'Chicken sandwich',
        price: Money(4500),
      );
      const chips = Product(
        id: 202,
        categoryId: 11,
        nameEn: 'Chips',
        price: Money(2500),
      );
      final combo = Combo(
        id: 90,
        categoryId: 11,
        nameEn: 'Lunch meal',
        nameAr: 'وجبة الغداء',
        price: const Money(6000),
        taxGroupId: 3,
        groups: [
          ComboGroup(
            id: 1,
            nameEn: 'Sandwich',
            options: [ComboOption(id: 11, product: sandwich)],
          ),
          ComboGroup(
            id: 2,
            nameEn: 'Side',
            options: [
              ComboOption(
                id: 21,
                product: chips,
                priceDelta: const Money(500),
              ),
            ],
          ),
        ],
      );

      var ticket = Ticket(id: 'txn-combo', orderType: OrderType.dineIn);
      ticket = TicketEngine.attachTable(ticket, 12, 'T12', guests: 2);
      return TicketEngine.addComboLine(
        ticket,
        combo,
        chosen: combo.fixedSelection,
      ).ticket!;
    }

    Ticket restored() => ParkedTicketCodec.decode(
      (jsonDecode(jsonEncode(ParkedTicketCodec.encode(withCombo()))) as Map)
          .cast<String, Object?>(),
      _catalog,
    )!;

    test('it comes back a meal, at the meal price', () {
      // A parked meal that came back as a bare product would price at the
      // component's price and lose what the kitchen was told to make.
      final line = restored().lines.single;
      expect(line.isCombo, isTrue);
      expect(line.unitPrice.minor, 6500);
    });

    test('the components come with it', () {
      final selection = restored().lines.single.combo!;
      expect(selection.items.map((i) => i.nameEn), [
        'Chicken sandwich',
        'Chips',
      ]);
      expect(selection.items.last.priceDelta.minor, 500);
    });

    test('so do its name and its rate', () {
      final selection = restored().lines.single.combo!;
      expect(selection.comboId, 90);
      expect(selection.displayName('ar'), 'وجبة الغداء');
      // A meal is taxed as a meal.
      expect(selection.taxGroupId, 3);
    });

    test('a line with no combo decodes without one', () {
      var plain = Ticket(id: 'txn-plain', orderType: OrderType.takeaway);
      plain = TicketEngine.addLine(plain, _burger, groups: const [_extras]).ticket!;
      final line = ParkedTicketCodec.decode(
        (jsonDecode(jsonEncode(ParkedTicketCodec.encode(plain))) as Map)
            .cast<String, Object?>(),
        _catalog,
      )!.lines.single;
      expect(line.isCombo, isFalse);
    });
  });
}
