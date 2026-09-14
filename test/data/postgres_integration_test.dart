@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/discount.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

import 'pg_fixture.dart';

/// Exercises the real SQL against a real PostgreSQL.
///
/// Skipped unless `POS_PG_HOST` is set, so `flutter test` stays green on a
/// machine with no database. Untested SQL is the biggest risk in this layer —
/// idempotency and invoice sequencing are enforced by constraints and row locks,
/// and neither can be verified by a unit test.
///
///   docker run -d --rm --name xorder-pos-itest \
///     -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=xorder_pos \
///     -p 55432:5432 postgres:16-alpine
///   POS_PG_HOST=127.0.0.1 POS_PG_PORT=55432 POS_PG_PASSWORD=postgres \
///     flutter test test/data/postgres_integration_test.dart
void main() {
  if (PgFixture.host == null) {
    test(
      'postgres integration (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late PosDatabase db;

  /// A real person to attribute a void to.
  ///
  /// `pos_order_lines.voided_by` has a foreign key to `pos_staff` — deliberately,
  /// so a void can never name somebody who does not work here — which means this
  /// suite needs an actual staff row rather than an invented id.
  late int staffId;

  setUp(() async {
    pg = await PgFixture.open('orders');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    final restaurant = await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('orders', 'Orders') "
      'RETURNING id',
    );
    final staff = await db.query(
      pg.config,
      'INSERT INTO pos_staff (restaurant_id, name, username, pin_salt, pin_hash) '
      "VALUES (@r, 'Nour Adel', 'nour', 'salt', 'hash') RETURNING id",
      parameters: {'r': restaurant.first[0]},
    );
    staffId = staff.first[0] as int;
  });

  tearDown(() => pg.close());

  PostgresOrdersRepository repository() => PostgresOrdersRepository(
    database: db,
    config: pg.config,
    context: const PosWriteContext(
      restaurantId: 1,
      branchId: 13,
      terminalId: '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
      branchCode: 'MAADI',
    ),
    clock: () => DateTime.utc(2026, 8, 26, 12),
  );

  test('migrations are idempotent and run once', () async {
    final second = await PosMigrator(db).migrate(pg.config);
    expect(
      second,
      isEmpty,
      reason: 'a second till booting must not re-run the schema',
    );
  });

  test(
    'a settled ticket writes order, lines and payments in one transaction',
    () async {
      final result = await repository().submit(
        _ticket('11111111-1111-4111-8111-111111111111'),
      );

      expect(result.serverId, isNotNull);
      expect(result.invoiceNumber, 'MAADI-2026-000001');

      final rows = await db.query(pg.config, '''
      SELECT o.total_minor, o.currency,
             (SELECT count(*) FROM pos_order_lines l WHERE l.order_id = o.id),
             (SELECT count(*) FROM pos_order_payments p WHERE p.order_id = o.id)
      FROM pos_orders o
    ''');
      expect(rows.length, 1);
      // 2 × (10.00 + 1.50) = 23.00 subtotal; +12% service = 2.76; +14% VAT on
      // 25.76 = 3.61 (half-up, the single rounding point); total 29.37.
      expect(rows.first[0], 2937);
      expect(rows.first[1], 'EGP');
      expect(rows.first[2], 1, reason: 'one line');
      expect(
        rows.first[3],
        2,
        reason: 'split tender is two payment rows, not two columns',
      );
    },
  );

  test('replaying a client transaction id returns the original, and issues no second number', () async {
    const id = '22222222-2222-4222-8222-222222222222';
    final first = await repository().submit(_ticket(id));
    final replay = await repository().submit(_ticket(id));

    expect(replay.serverId, first.serverId);
    expect(replay.invoiceNumber, first.invoiceNumber);

    final count = await db.query(pg.config, 'SELECT count(*) FROM pos_orders');
    expect(
      count.first[0],
      1,
      reason: 'five submissions must create exactly one sale',
    );

    final seq = await db.query(
      pg.config,
      'SELECT next_value FROM pos_invoice_sequences',
    );
    expect(
      seq.first[0],
      2,
      reason: 'a replay must not consume an invoice number',
    );
  });

  test('concurrent settlements never share an invoice number', () async {
    // The case a MAX(number)+1 scan gets wrong, and the reason the sequence row
    // is locked FOR UPDATE inside the same transaction as the insert.
    final results = await Future.wait([
      for (var i = 0; i < 8; i++)
        repository().submit(_ticket('33333333-3333-4333-8333-00000000000$i')),
    ]);

    final numbers = results.map((r) => r.invoiceNumber).toSet();
    expect(numbers.length, 8, reason: 'eight tills, eight distinct numbers');
    expect(results.map((r) => r.serverId).toSet().length, 8);
  });

  test('the database refuses money that should be impossible', () async {
    // Constraints, not client-side hope. A negative payment is a refund and has
    // its own record type; it must never arrive as a tender.
    await expectLater(
      db.runTx(pg.config, (tx) async {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_order_payments (order_id, tender_type_id, label, amount_minor)
            VALUES (@order, 1, 'Cash', -500)
          '''),
          parameters: {'order': 1},
        );
      }),
      throwsA(isA<PosDbException>()),
    );
  });

  group('a voided line and a discount reach the ledger', () {
    test('the order totals exclude what was voided', () async {
      await repository().submit(
        _messyTicket('22222222-2222-4222-8222-222222222222', staffId),
      );

      final rows = await db.query(
        pg.config,
        'SELECT subtotal_minor, discount_minor, total_minor FROM pos_orders '
        'ORDER BY id DESC LIMIT 1',
      );

      // 100.00 grill voided, 25.00 chips left, 5.00 comped.
      expect(rows.first[0], 2500);
      expect(rows.first[1], 500);
      expect(rows.first[2], 2000);
    });

    test('the voided line is still written, with who and when', () async {
      await repository().submit(
        _messyTicket('33333333-3333-4333-8333-333333333333', staffId),
      );

      final rows = await db.query(
        pg.config,
        'SELECT line_key, voided_at, voided_by, line_total_minor '
        'FROM pos_order_lines WHERE voided_at IS NOT NULL',
      );

      // The row is the evidence. Deleting it would leave the kitchen ticket and
      // the bill describing different meals with nothing to say why.
      expect(rows, hasLength(1));
      expect(rows.first[0], '501:');
      expect(rows.first[2], staffId);
      expect(rows.first[3], 10000, reason: 'the price it would have been');
    });

    test('the event log says it was voided after send', () async {
      await repository().submit(
        _messyTicket('44444444-4444-4444-8444-444444444444', staffId),
      );

      final rows = await db.query(
        pg.config,
        'SELECT event, line_key, quantity_before, quantity_after, note, '
        '       order_line_id IS NOT NULL '
        'FROM pos_order_line_events ORDER BY id',
      );

      expect(rows, hasLength(1));
      expect(rows.first[0], 'voided_after_send');
      expect(rows.first[1], '501:');
      expect(rows.first[2], 1);
      expect(rows.first[3], 0);
      expect(rows.first[4], 'Dropped by the runner');
      // The line still exists, so the event points at it as well as naming it.
      expect(rows.first[5], true);
    });

    test('the discount points at the line it came off', () async {
      await repository().submit(
        _messyTicket('55555555-5555-4555-8555-555555555555', staffId),
      );

      final rows = await db.query(
        pg.config,
        'SELECT d.amount_minor, d.name_snapshot, l.line_key '
        'FROM pos_order_discounts d '
        'JOIN pos_order_lines l ON l.id = d.order_line_id',
      );

      expect(rows, hasLength(1));
      expect(rows.first[0], 500);
      expect(rows.first[1], 'Manager comp');
      expect(rows.first[2], '502:');
    });

    test('a cancelled line leaves an event and no line', () async {
      var ticket = Ticket(
        id: '66666666-6666-4666-8666-666666666666',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
        lines: [
          TicketLine(
            product: const Product(
              id: 601,
              categoryId: 9,
              nameEn: 'Typo',
              price: Money(3000),
            ),
            quantity: 1,
          ),
        ],
      );
      ticket = TicketEngine.cancelLine(
        ticket,
        '601:',
        by: staffId,
        now: DateTime.utc(2026, 8, 26, 12),
      ).ticket!;
      ticket = ticket.copyWith(
        lines: [
          TicketLine(
            product: const Product(
              id: 602,
              categoryId: 9,
              nameEn: 'The real one',
              price: Money(3000),
            ),
            quantity: 1,
          ),
        ],
        tenders: const [Tender(typeId: 1, label: 'Cash', amount: Money(3000))],
      );

      await repository().submit(ticket);

      final rows = await db.query(
        pg.config,
        "SELECT event, line_key, order_line_id FROM pos_order_line_events "
        "WHERE event = 'removed_before_send'",
      );

      // Null `order_line_id`, because the line never became a row — which is
      // exactly why the table keys on `line_key` as well.
      expect(rows, hasLength(1));
      expect(rows.first[1], '601:');
      expect(rows.first[2], isNull);
    });
  });

  group('a repriced line reaches the ledger', () {
    Ticket repriced(String id) {
      const grill = Product(
        id: 501,
        categoryId: 9,
        nameEn: 'Mixed Grill',
        price: Money(5000),
      );

      var ticket = Ticket(
        id: id,
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
        lines: [TicketLine(product: grill, quantity: 2)],
      );
      ticket = TicketEngine.overridePrice(
        ticket,
        '501:',
        const Money(4000),
        by: staffId,
        now: DateTime.utc(2026, 9, 7, 13),
        note: 'Regular customer',
      ).ticket!;

      return ticket.copyWith(
        tenders: const [Tender(typeId: 1, label: 'Cash', amount: Money(8000))],
      );
    }

    test('the line is written at the price that was agreed', () async {
      // Not the menu price. `unit_price_minor` is what the receipt said and
      // what a refund will be measured against.
      await repository().submit(
        repriced('66666666-6666-4666-8666-000000000001'),
      );

      final rows = await db.query(
        pg.config,
        'SELECT unit_price_minor, line_total_minor FROM pos_order_lines '
        'ORDER BY id DESC LIMIT 1',
      );
      expect(rows.first[0], 4000);
      expect(rows.first[1], 8000);
    });

    test('the order total follows the agreed price', () async {
      await repository().submit(
        repriced('66666666-6666-4666-8666-000000000002'),
      );

      final rows = await db.query(
        pg.config,
        'SELECT subtotal_minor, total_minor FROM pos_orders '
        'ORDER BY id DESC LIMIT 1',
      );
      expect(rows.first[0], 8000);
      expect(rows.first[1], 8000);
    });

    test('the event records both prices, which is the whole audit', () async {
      // Migration 9 provisioned `unit_price_before_minor` and
      // `unit_price_after_minor` for exactly this. "Was 50.00, now 40.00" is
      // the only way anybody later can tell a repricing from a cheap menu.
      await repository().submit(
        repriced('66666666-6666-4666-8666-000000000003'),
      );

      final rows = await db.query(
        pg.config,
        'SELECT event, unit_price_before_minor, unit_price_after_minor, '
        '       staff_id, note, order_line_id '
        'FROM pos_order_line_events ORDER BY id DESC LIMIT 1',
      );

      expect(rows.first[0], 'price_overridden');
      expect(rows.first[1], 5000);
      expect(rows.first[2], 4000);
      expect(rows.first[3], staffId);
      expect(rows.first[4], 'Regular customer');
      // The line still exists, so the event points at it.
      expect(rows.first[5], isNotNull);
    });

    test('the event name is one the CHECK constraint accepts', () async {
      // A string this build invents that migration 9 does not know would fail
      // the whole settlement transaction — silently, from the cashier's side,
      // as a sale that would not go through.
      final result = await repository().submit(
        repriced('66666666-6666-4666-8666-000000000004'),
      );
      expect(result.serverId, isNotNull);
    });
  });

  group('a voided order', () {
    Ticket sentTicket(String id) => Ticket(
      id: id,
      orderType: OrderType.dineIn,
      tableId: 4,
      tableLabel: 'T4',
      guestCount: 2,
      taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
      lines: [
        TicketLine(
          product: const Product(
            id: 701,
            categoryId: 9,
            nameEn: 'Mixed Grill',
            price: Money(26800),
          ),
          quantity: 1,
          stage: LineStage.sent,
          roundNumber: 1,
        ),
      ],
    );

    // A supervisor: the repository asks for `order.void` now.
    PosStaff staff() => PosStaff(
      id: staffId,
      name: 'Nour Adel',
      role: const PosRole(
        id: 1,
        code: SystemRoles.supervisorCode,
        nameEn: 'Supervisor',
        capabilities: SystemRoles.supervisor,
      ),
    );

    PosStaff cashier() => PosStaff(
      id: staffId,
      name: 'Nour Adel',
      role: const PosRole(
        id: 2,
        code: SystemRoles.cashierCode,
        nameEn: 'Cashier',
        capabilities: SystemRoles.cashier,
      ),
    );

    Future<int> voided() async => (await db.query(
      pg.config,
      "SELECT count(*) FROM pos_orders WHERE status = 'VOIDED'",
    )).first[0]! as int;

    test('somebody without order.void is refused, and nothing is written',
        () async {
      await expectLater(
        repository().voidOrder(
          sentTicket('dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
          by: cashier(),
        ),
        throwsA(isA<PermissionRefused>()),
      );
      expect(await voided(), 0);
    });

    test('a supervisor\'s approval for this ticket lets a cashier void it',
        () async {
      const id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
      final approval = (Authorization.approve(
        approver: staff(),
        capability: PosCapability.orderVoid,
        subject: id,
      ) as Allowed).approval!;

      await repository().voidOrder(sentTicket(id), by: cashier(), approval: approval);
      expect(await voided(), 1);

      // And not a second, different ticket on the same approval.
      await expectLater(
        repository().voidOrder(
          sentTicket('ffffffff-ffff-4fff-8fff-ffffffffffff'),
          by: cashier(),
          approval: approval,
        ),
        throwsA(isA<PermissionRefused>()),
      );
    });

    test('is written with its real totals, not zeroed', () async {
      await repository().voidOrder(
        sentTicket('77777777-7777-4777-8777-777777777777'),
        by: staff(),
        note: 'Table walked out',
      );

      final rows = await db.query(
        pg.config,
        'SELECT status, subtotal_minor, total_minor, voided_by, void_note '
        'FROM pos_orders ORDER BY id DESC LIMIT 1',
      );

      // What was thrown away is the number a waste report exists to show. An
      // order recording zero would erase it.
      expect(rows.first[0], 'VOIDED');
      expect(rows.first[1], 26800);
      expect(rows.first[2], 26800);
      expect(rows.first[3], staffId);
      expect(rows.first[4], 'Table walked out');
    });

    test('takes an invoice number, so there is no gap to explain', () async {
      final result = await repository().voidOrder(
        sentTicket('88888888-8888-4888-8888-888888888888'),
        by: staff(),
      );

      // A missing number in the sequence is a question nobody can answer. A
      // voided entry is one anybody can.
      expect(result.invoiceNumber, isNotNull);
      expect(result.invoiceNumber, startsWith('MAADI-'));
    });

    test('keeps its lines, so the waste can be itemised', () async {
      await repository().voidOrder(
        sentTicket('99999999-9999-4999-8999-999999999999'),
        by: staff(),
      );

      final rows = await db.query(
        pg.config,
        'SELECT l.name_snapshot, l.line_total_minor FROM pos_order_lines l '
        'JOIN pos_orders o ON o.id = l.order_id '
        "WHERE o.status = 'VOIDED'",
      );
      expect(rows, hasLength(1));
      expect(rows.first[0], 'Mixed Grill');
      expect(rows.first[1], 26800);
    });

    test('takes no money', () async {
      await repository().voidOrder(
        sentTicket('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        by: staff(),
      );

      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_order_payments p '
        'JOIN pos_orders o ON o.id = p.order_id '
        "WHERE o.status = 'VOIDED'",
      );
      expect(rows.first[0], 0);
    });

    test('a replay records it once and returns the same number', () async {
      final ticket = sentTicket('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

      final first = await repository().voidOrder(ticket, by: staff());
      final second = await repository().voidOrder(ticket, by: staff());

      // A till that retried after a timeout must not record the waste twice.
      expect(second.serverId, first.serverId);
      expect(second.invoiceNumber, first.invoiceNumber);

      final rows = await db.query(
        pg.config,
        "SELECT count(*) FROM pos_orders WHERE status = 'VOIDED'",
      );
      expect(rows.first[0], 1);
    });

    test('is not owed to the platform', () async {
      await repository().voidOrder(
        sentTicket('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
        by: staff(),
      );

      // `POS-BE-006` is the contract for a settled sale. What a voided one
      // looks like on the wire is not decided, and sending a shape we invented
      // would have to be unsent later.
      final rows = await db.query(pg.config, 'SELECT count(*) FROM pos_outbox');
      expect(rows.first[0], 0);
    });
  });
}

/// A ticket with a discount, a voided sent line, and a cancelled one.
///
/// The point of settling it is that four different tables have to end up
/// agreeing about one meal: the order's totals, the lines with their void
/// columns, the discounts, and the line-event log.
Ticket _messyTicket(String id, int staffId) {
  const grill = Product(
    id: 501,
    categoryId: 9,
    nameEn: 'Mixed Grill',
    price: Money(10000),
  );
  const chips = Product(
    id: 502,
    categoryId: 9,
    nameEn: 'Chips',
    price: Money(2500),
  );

  var ticket = Ticket(
    id: id,
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    lines: [
      TicketLine(
        product: grill,
        quantity: 1,
        stage: LineStage.sent,
        roundNumber: 1,
      ),
      TicketLine(
        product: chips,
        quantity: 1,
        stage: LineStage.sent,
        roundNumber: 1,
      ),
    ],
  );

  ticket = TicketEngine.voidLine(
    ticket,
    '501:',
    by: staffId,
    now: DateTime.utc(2026, 8, 26, 12),
    reasonId: null,
    note: 'Dropped by the runner',
    approvedByStaffId: null,
  ).ticket!;

  ticket = TicketEngine.applyCustomDiscount(
    ticket,
    name: 'Manager comp',
    kind: DiscountKind.fixed,
    appliedBy: staffId,
    valueMinor: const Money(500),
    lineKey: '502:',
  ).ticket!;

  return ticket.copyWith(
    tenders: const [Tender(typeId: 1, label: 'Cash', amount: Money(2000))],
  );
}

Ticket _ticket(String id) {
  const product = Product(
    id: 501,
    categoryId: 9,
    nameEn: 'Mixed Grill',
    price: Money(1000),
  );
  const extra = Modifier(
    id: 77,
    groupId: 4,
    nameEn: 'Extra bread',
    priceDelta: Money(150),
  );

  return Ticket(
    id: id,
    orderType: OrderType.dineIn,
    tableId: 4,
    tableLabel: 'T4',
    guestCount: 2,
    lines: [
      TicketLine(product: product, quantity: 2, modifiers: const [extra]),
    ],
    tenders: const [
      Tender(typeId: 1, label: 'Cash', amount: Money(2000)),
      Tender(
        typeId: 2,
        label: 'Card',
        amount: Money(937),
        reference: 'AUTH-4471',
      ),
    ],
  );
}
