import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/parked_ticket_codec.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/combo.dart';
import 'package:shared_module/domain/models/customer.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/service_charge.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

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
  _fullTicketTests();

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

  test('a parked Large is still the price after the size leaves the menu', () {
    const large = Modifier(
      id: 92,
      groupId: 44,
      nameEn: 'Large',
      priceDelta: Money(12000),
      isVariant: true,
    );
    const size = ModifierGroup(
      id: 44,
      nameEn: 'Size',
      isRequired: true,
      isVariant: true,
      modifiers: [large],
    );
    final original = TicketEngine.addLine(
      Ticket(id: 'txn-size', orderType: OrderType.takeaway),
      _burger,
      modifiers: const [large, _cheese],
      groups: const [size, _extras],
    ).ticket!;
    final json = jsonDecode(jsonEncode(ParkedTicketCodec.encode(original)))
        as Map<String, dynamic>;

    // Only the extras are still on the menu: the Large comes back from its
    // snapshot, and must come back as a size rather than as a 120.00 extra.
    final restored =
        ParkedTicketCodec.decode(json.cast<String, Object?>(), _catalog)!;

    expect(restored.lines.single.unitPrice.minor, 12000 + 1500);
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
      // the business has said counts as cash. No lookup can recover that.
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

Ticket _roundTrip(Ticket ticket) => ParkedTicketCodec.decode(
  (jsonDecode(jsonEncode(ParkedTicketCodec.encode(ticket))) as Map)
      .cast<String, Object?>(),
  _catalog,
)!;

void _fullTicketTests() {
  group('the rules a ticket was priced under survive a restart (R-SALE-2)', () {
    /// The failure this guards against is a parked table that comes back
    /// priced under different rules than it was rung up under: an inclusive
    /// business's bill growing its VAT on top, a zero-rated bottle charged
    /// the standard rate, a delivery fee turned back into 12%, and a delivery
    /// with nobody to deliver it to. Before the fix only the four scalar rates
    /// were written, and `adopt` takes the decoded ticket as it is.
    const standard = TaxGroup(
      id: 1,
      nameEn: 'VAT 14%',
      nameAr: 'ضريبة ١٤٪',
      rateBp: 1400,
      isDefault: true,
    );
    const zeroRated = TaxGroup(
      id: 2,
      nameEn: 'Zero-rated',
      nameAr: 'معفاة',
      rateBp: 0,
      etaSubType: EtaTaxCode.zeroRated,
    );
    const service = ServiceCharge(
      id: 5,
      nameEn: 'Service',
      nameAr: 'خدمة',
      rateBp: 1200,
      orderTypes: {OrderType.dineIn},
      sortOrder: 1,
    );
    const deliveryFee = ServiceCharge(
      id: 6,
      nameEn: 'Delivery fee',
      nameAr: 'رسوم التوصيل',
      fixedMinor: 2500,
      orderTypes: {OrderType.delivery},
      isTaxable: false,
      isOptional: true,
      sortOrder: 2,
    );
    const config = TaxConfig(
      serviceBp: 1000,
      vatBp: 1400,
      serviceDineInOnly: false,
      source: TaxSource.server,
      taxMode: TaxMode.inclusive,
      taxGroups: [standard, zeroRated],
      serviceCharges: [service, deliveryFee],
    );
    const customer = PosCustomer(
      id: 44,
      platformId: 9001,
      name: 'Mona Adel',
      phone: '01012345678',
      email: 'mona@example.com',
      address: '12 Tahrir St, flat 4',
      note: 'Ring twice',
    );
    // Not in `_catalog`, so it comes back from its snapshot — which is the
    // only place its zero rating can come from.
    const water = Product(
      id: 301,
      categoryId: 11,
      nameEn: 'Water',
      price: Money(1000),
      taxGroupId: 2,
    );

    Ticket full() {
      final combo = Combo(
        id: 90,
        categoryId: 11,
        nameEn: 'Lunch meal',
        nameAr: 'وجبة الغداء',
        price: const Money(6000),
        taxGroupId: 1,
        groups: [
          ComboGroup(
            id: 1,
            nameEn: 'Main',
            options: [ComboOption(id: 11, product: _burger)],
          ),
        ],
      );

      var ticket = Ticket(
        id: 'txn-full',
        orderType: OrderType.dineIn,
        taxConfig: config,
      );
      ticket = TicketEngine.attachTable(ticket, 12, 'T12', guests: 4);
      ticket = TicketEngine.attachCustomer(ticket, customer);
      ticket = TicketEngine.addLine(
        ticket,
        _burger,
        modifiers: const [_cheese],
        groups: const [_extras],
        quantity: 2,
        note: 'no onions',
      ).ticket!;
      ticket = TicketEngine.addLine(ticket, water, quantity: 3).ticket!;
      ticket = TicketEngine.addComboLine(
        ticket,
        combo,
        chosen: combo.fixedSelection,
        note: 'sauce on the side',
      ).ticket!;
      ticket = TicketEngine.sendRound(ticket);
      return TicketEngine.addTender(
        ticket,
        typeId: 1,
        label: 'Cash',
        amount: const Money(5000),
        countsAsCash: true,
      ).ticket!;
    }

    test('the tax config comes back equal to the one it was parked with', () {
      final original = full();
      final restored = _roundTrip(original);

      // Meaningful only because `TaxConfig ==` now covers the mode, the
      // groups and the charges. Under the old equality this held even while
      // all three were being thrown away.
      expect(restored.taxConfig, original.taxConfig);
      expect(restored.taxConfig.hashCode, original.taxConfig.hashCode);
      expect(restored.taxConfig.taxMode, TaxMode.inclusive);
      expect(restored.taxConfig.taxGroups, [standard, zeroRated]);
      expect(restored.taxConfig.serviceCharges, [service, deliveryFee]);
    });

    test('what the group and charge equalities do not compare comes back too',
        () {
      // `TaxGroup ==` and `ServiceCharge ==` leave these out on purpose, so
      // the equality above cannot vouch for them. Scope, in particular, moves
      // a total: lose it and a delivery fee lands on a dine-in table.
      final restored = _roundTrip(full()).taxConfig;

      final zero = restored.taxGroups.last;
      expect(zero.nameAr, 'معفاة');
      expect(zero.isActive, isTrue);
      expect(zero.etaSubType, EtaTaxCode.zeroRated);

      final fee = restored.serviceCharges.last;
      expect(fee.nameAr, 'رسوم التوصيل');
      expect(fee.orderTypes, {OrderType.delivery});
      expect(fee.isOptional, isTrue);
      expect(fee.sortOrder, 2);
      expect(restored.serviceCharges.first.orderTypes, {OrderType.dineIn});
    });

    test('the customer comes back whole', () {
      final restored = _roundTrip(full()).customer!;

      expect(restored.id, 44);
      expect(restored.platformId, 9001);
      expect(restored.name, 'Mona Adel');
      expect(restored.phone, '01012345678');
      expect(restored.email, 'mona@example.com');
      expect(restored.address, '12 Tahrir St, flat 4');
      expect(restored.note, 'Ring twice');
    });

    test('lines, notes and the meal come back as they were rung up', () {
      final original = full();
      final restored = _roundTrip(original);

      expect(restored.id, original.id);
      expect(restored.tableId, 12);
      expect(restored.guestCount, 4);
      expect(restored.roundsSent, 1);
      expect(restored.lines.map((l) => l.note), [
        'no onions',
        null,
        'sauce on the side',
      ]);
      expect(restored.lines.map((l) => l.taxGroupId), [null, 2, 1]);
      expect(restored.lines.last.isCombo, isTrue);
      expect(restored.lines.last.combo!.items.single.nameEn, 'Classic Burger');
      expect(restored.tenders.single.countsAsCash, isTrue);
    });

    test('the bill is the same, rate by rate, for every order type', () {
      // The number that must not drift. Checked across order types because
      // the charges are scoped by them, and inclusive because that is where
      // a lost mode costs the most: VAT added on top of prices that hold it.
      final original = full();
      final restored = _roundTrip(original);

      for (final type in OrderType.values) {
        final before = original.copyWith(orderType: type).totals;
        final after = restored.copyWith(orderType: type).totals;
        expect(after.total.minor, before.total.minor, reason: type.wire);
        expect(after.service.minor, before.service.minor, reason: type.wire);
        expect(after.vat.minor, before.vat.minor, reason: type.wire);
        expect(
          after.taxLines.map((l) => (l.taxGroupId, l.amount.minor)),
          before.taxLines.map((l) => (l.taxGroupId, l.amount.minor)),
          reason: type.wire,
        );
      }
      // Inclusive: the tax is inside the total, never on top of it.
      final totals = restored.totals;
      expect(totals.total.minor, totals.net.minor + totals.service.minor);
      // And the zero-rated water is billed as zero-rated.
      expect(totals.taxLines.map((l) => l.taxGroupId), contains(2));
    });

    test('a payload parked before these keys existed decodes to the old '
        'defaults', () {
      // Exactly what the previous encoder wrote: the four scalars and no
      // customer. Every parked table already on a branch server looks like
      // this, and must come back priced as it was the day before the upgrade.
      final restored = ParkedTicketCodec.decode(const {
        'v': 1,
        'client_transaction_id': 'txn-legacy',
        'order_type': 'dine_in',
        'table_id': 12,
        'table_label': 'T12',
        'currency': 'EGP',
        'exponent': 2,
        'tax': {
          'service_bp': 1200,
          'vat_bp': 1400,
          'service_dine_in_only': true,
          'source': 'server',
        },
        'lines': [
          {
            'product_id': 101,
            'name_en': 'Classic Burger',
            'price_minor': 9500,
            'quantity': 1,
          },
        ],
      }, _catalog)!;

      expect(
        restored.taxConfig,
        const TaxConfig(source: TaxSource.server),
        reason: 'exclusive, no named rates, no §38 charges',
      );
      expect(restored.customer, isNull);
      // 95.00 + 12% service = 106.40, + 14% VAT on that = 121.30.
      expect(restored.totals.total.minor, 12130);
    });

    test('a charge scoped only to an order type this build cannot read is '
        'off, not everywhere', () {
      // An empty scope means "every order type". Decoding an unreadable one
      // as empty would put a newer build's kerbside fee on a dine-in table.
      final restored = ParkedTicketCodec.decode(const {
        'client_transaction_id': 'txn-future-type',
        'order_type': 'dine_in',
        'tax': {
          'service_charges': [
            {
              'id': 7,
              'name_en': 'Kerbside fee',
              'fixed_minor': 1500,
              'order_types': ['kerbside'],
            },
          ],
        },
      }, _catalog)!;

      final charge = restored.taxConfig.serviceCharges.single;
      expect(charge.isActive, isFalse);
      expect(charge.appliesTo(OrderType.dineIn), isFalse);
    });

    test('a charge or a group with no readable figure is dropped, not '
        'invented', () {
      final restored = ParkedTicketCodec.decode(const {
        'client_transaction_id': 'txn-broken-tax',
        'order_type': 'dine_in',
        'tax': {
          'mode': 'something-new',
          'groups': [
            {'id': 3, 'name_en': 'Float rate', 'rate_bp': 14.0},
            {'name_en': 'No id', 'rate_bp': 500},
          ],
          'service_charges': [
            {'id': 8, 'name_en': 'Nothing to charge'},
          ],
        },
        'customer': {'name': 'No id'},
      }, _catalog)!;

      expect(restored.taxConfig.taxGroups, isEmpty);
      expect(restored.taxConfig.serviceCharges, isEmpty);
      // `TaxMode.fromWire`'s documented fallback.
      expect(restored.taxConfig.taxMode, TaxMode.exclusive);
      expect(restored.customer, isNull);
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
