import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/parked_ticket_codec.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
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
