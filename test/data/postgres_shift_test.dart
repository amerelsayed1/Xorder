@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_shift_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

import 'pg_fixture.dart';

/// Shifts, and the money they are answerable for.
///
/// Before this existed, *Close shift* navigated to the start screen and did
/// nothing: no shift was opened, no drawer was counted, and an in-progress
/// ticket was discarded without a word. Everything here is a question a manager
/// asks at the end of a night, so the answers have to survive a restart, a
/// second till, and somebody pressing the button twice.
void main() {
  if (PgFixture.host == null) {
    test('shifts (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late String terminalId;
  late PosStaff sara;
  late PosStaff omar;

  setUp(() async {
    pg = await PgFixture.open('shifts');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    // The ledger goes first. `pos_orders` references `pos_shifts`, and orders
    // are deliberately not cascade-deleted from a restaurant — a sale is a
    // record of money that moved, not a child of the configuration that
    // described it.
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    final restaurant = await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('shift-test', 'Shift Test') RETURNING id",
    );
    restaurantId = restaurant.first[0] as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) VALUES (@r, 'SHF', 'Shift') RETURNING id",
      parameters: {'r': restaurantId},
    );
    branchId = branch.first[0] as int;

    final terminal = await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
      "VALUES (gen_random_uuid(), @r, @b, 'Counter 1') RETURNING id::text",
      parameters: {'r': restaurantId, 'b': branchId},
    );
    terminalId = terminal.first[0] as String;

    Future<PosStaff> staff(String name, String username, String pin) async {
      final salt = PinHash.newSalt();
      final row = await db.query(
        pg.config,
        'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, pin_salt, pin_hash) '
        'VALUES (@r, @b, @n, @u, @s, @h) RETURNING id',
        parameters: {
          'r': restaurantId,
          'b': branchId,
          'n': name,
          'u': username,
          's': salt,
          'h': await PinHash.hash(pin, salt),
        },
      );
      return PosStaff(id: row.first[0] as int, name: name);
    }

    sara = await staff('Sara M.', 'sara', '1111');
    omar = await staff('Omar T.', 'omar', '2222');
  });

  tearDown(() => pg.close());

  PostgresShiftRepository shifts() => PostgresShiftRepository(
        database: db,
        config: pg.config,
        restaurantId: restaurantId,
        branchId: branchId,
        terminalId: terminalId,
      );

  /// Sell something into [shift], paid with the given tenders.
  ///
  /// Returns the **order total**, which is not the product price: the engine
  /// adds VAT, and a test that counted the drawer against the shelf price would
  /// manufacture a variance on every assertion.
  Future<int> sell(
    PosShift shift, {
    required int priceMinor,
    List<(int, String, int?)> tenders = const [(1, 'Cash', null)],
    // What the tender type said when the money moved. Defaults to matching the
    // seeded list, which is what the payment screen passes.
    bool? countsAsCash,
  }) async {
    final product = Product(
      id: 1,
      categoryId: 1,
      nameEn: 'Thing',
      price: Money(priceMinor),
    );

    var ticket = Ticket(id: const Uuid().v4(), orderType: OrderType.takeaway);
    ticket = TicketEngine.addLine(ticket, product).ticket!;
    for (final (typeId, label, amount) in tenders) {
      ticket = TicketEngine.addTender(
        ticket,
        typeId: typeId,
        label: label,
        amount: amount == null ? null : Money(amount),
        countsAsCash: countsAsCash ?? TenderMethod.isCash(typeId),
      ).ticket!;
    }

    await PostgresOrdersRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        restaurantId: restaurantId,
        branchId: branchId,
        terminalId: terminalId,
        branchCode: 'SHF',
      ),
      shiftId: shift.id,
    ).submit(ticket);

    return ticket.totals.total.minor;
  }

  group('opening', () {
    test('records who opened it and what was in the drawer', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money(50000));

      expect(shift.isOpen, isTrue);
      expect(shift.openedByName, 'Sara M.');
      expect(shift.openingFloat.minor, 50000);
      expect(shift.reference, matches(RegExp(r'^SHIFT #\d{4}$')));
    });

    test('a till restarted mid-service comes back to the same shift', () async {
      final first = await shifts().open(by: sara, openingFloat: Money(50000));

      // A fresh repository is what a relaunched app has. The drawer never
      // closed, so neither did the shift — asking for a second opening float
      // against the same cash would make every later variance wrong.
      final resumed = await shifts().open(by: omar, openingFloat: Money(999));

      expect(resumed.id, first.id);
      expect(resumed.openingFloat.minor, 50000, reason: 'the original float stands');
      expect(resumed.openedByName, 'Sara M.');
    });

    test('the database itself refuses a second open shift on one terminal', () async {
      await shifts().open(by: sara, openingFloat: Money.zero);

      // Not a check this code does — a partial unique index does it, so a race
      // between two processes cannot slip past it either.
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_shifts (restaurant_id, branch_id, terminal_id, opened_by) '
          'VALUES (@r, @b, @t, @s)',
          parameters: {'r': restaurantId, 'b': branchId, 't': terminalId, 's': omar.id},
        ),
        throwsA(isA<PosDbException>()),
      );
    });

    test('a different terminal opens its own shift freely', () async {
      await shifts().open(by: sara, openingFloat: Money.zero);

      final second = await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
        "VALUES (gen_random_uuid(), @r, @b, 'Counter 2') RETURNING id::text",
        parameters: {'r': restaurantId, 'b': branchId},
      );
      final other = PostgresShiftRepository(
        database: db,
        config: pg.config,
        restaurantId: restaurantId,
        branchId: branchId,
        terminalId: second.first[0] as String,
      );

      expect((await other.open(by: omar, openingFloat: Money.zero)).isOpen, isTrue);
    });
  });

  group('the Z report', () {
    test('totals only the sales that belong to this shift', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money(20000));
      final kept = await sell(shift, priceMinor: 10000);
      final detached = await sell(shift, priceMinor: 5000);

      // A sale belonging to no shift must not be counted into one.
      await db.query(
        pg.config,
        'UPDATE pos_orders SET shift_id = NULL WHERE total_minor = @total',
        parameters: {'total': detached},
      );

      final summary = await shifts().summarise(shift);
      expect(summary.saleCount, 1);
      expect(summary.gross.minor, kept);
    });

    test('expected cash is the float plus cash taken, and nothing else', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money(20000));
      final inCash = await sell(shift, priceMinor: 10000);
      final onCard = await sell(shift, priceMinor: 30000, tenders: [(2, 'Card', null)]);

      final summary = await shifts().summarise(shift);

      expect(summary.gross.minor, inCash + onCard, reason: 'both sales were taken');
      expect(summary.cashTaken.minor, inCash, reason: 'the card sale is not in the drawer');
      // Counting card takings against the drawer would manufacture a shortfall
      // on every single shift.
      expect(summary.expectedCash.minor, 20000 + inCash);
    });

    test('a cash-up does not move when a payment method is later edited',
        () async {
      // §40 made payment methods data, which means somebody can decide on
      // Thursday that the wallet counts as cash. Last week's cash-up must not
      // change: the manager investigating that variance needs the number the
      // shift was judged against, and a figure that moves under them is worse
      // than no figure at all.
      final shift = await shifts().open(by: sara, openingFloat: Money.zero);
      final inCash = await sell(shift, priceMinor: 10000);
      await sell(shift, priceMinor: 30000, tenders: [(3, 'Wallet', null)]);

      expect((await shifts().summarise(shift)).cashTaken.minor, inCash);

      // Thursday. The wallet now counts as cash for everything taken from here.
      await db.query(
        pg.config,
        "UPDATE pos_tender_types SET counts_as_cash = true WHERE code = 'wallet'",
      );

      expect(
        (await shifts().summarise(shift)).cashTaken.minor,
        inCash,
        reason: 'the flag was snapshotted onto the payment, not looked up',
      );
    });

    test('a method that counted as cash at the time still does', () async {
      // The other direction, and the one a migration gets wrong: a payment
      // taken on a method that has since been demoted is still in the drawer.
      final shift = await shifts().open(by: sara, openingFloat: Money.zero);
      final taken = await sell(
        shift,
        priceMinor: 5000,
        tenders: [(3, 'Wallet', null)],
        countsAsCash: true,
      );

      expect((await shifts().summarise(shift)).cashTaken.minor, taken);
    });

    test('a split payment lands on both tender lines', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money.zero);
      final total = await sell(
        shift,
        priceMinor: 10000,
        tenders: [(1, 'Cash', 4000), (2, 'Card', null)],
      );

      final summary = await shifts().summarise(shift);
      final byLabel = {for (final t in summary.tenders) t.label: t.amount.minor};

      expect(byLabel['Cash'], 4000);
      expect(byLabel['Card'], total - 4000, reason: 'the card covered the balance');
      // Only the cash half reaches the drawer.
      expect(summary.expectedCash.minor, 4000);
    });
  });

  group('closing', () {
    test('a balanced drawer records a zero variance', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money(20000));
      final taken = await sell(shift, priceMinor: 10000);

      final closed = await shifts().close(
        shift: shift,
        by: sara,
        countedCash: Money(20000 + taken),
      );

      expect(closed.balances, isTrue);
      expect(closed.variance.minor, 0);
      expect(await shifts().current(), isNull, reason: 'the shift is no longer open');
    });

    test('a short drawer is recorded, not refused', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money(20000));
      final taken = await sell(shift, priceMinor: 10000);
      final expected = 20000 + taken;

      // Refusing to close on a variance would leave the till unusable and the
      // discrepancy unrecorded — the opposite of what anybody wants at 1am.
      final closed = await shifts().close(
        shift: shift,
        by: sara,
        countedCash: Money(expected - 500),
      );

      expect(closed.balances, isFalse);
      expect(closed.variance.minor, -500, reason: 'five pounds short');

      final stored = await db.query(
        pg.config,
        'SELECT counted_cash_minor, expected_cash_minor, variance_minor, closed_by '
        'FROM pos_shifts WHERE id = @id',
        parameters: {'id': shift.id},
      );
      expect(stored.first[0], expected - 500);
      expect(stored.first[1], expected);
      expect(stored.first[2], -500);
      expect(stored.first[3], sara.id);
    });

    test('an over drawer is a positive variance', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money.zero);
      final taken = await sell(shift, priceMinor: 10000);

      final closed =
          await shifts().close(shift: shift, by: sara, countedCash: Money(taken + 250));
      expect(closed.variance.minor, 250);
    });

    test('whoever counts the drawer signs for it, not whoever opened', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money.zero);

      // A manager cashing up at the end of the night is the normal case.
      await shifts().close(shift: shift, by: omar, countedCash: Money.zero);

      final stored = await db.query(
        pg.config,
        'SELECT opened_by, closed_by FROM pos_shifts WHERE id = @id',
        parameters: {'id': shift.id},
      );
      expect(stored.first[0], sara.id);
      expect(stored.first[1], omar.id);
    });

    test('a second cash-up cannot overwrite the first', () async {
      final shift = await shifts().open(by: sara, openingFloat: Money.zero);
      await shifts().close(shift: shift, by: sara, countedCash: Money(10000));

      await expectLater(
        shifts().close(shift: shift, by: omar, countedCash: Money(999)),
        throwsA(isA<StateError>()),
      );

      final stored = await db.query(
        pg.config,
        'SELECT counted_cash_minor FROM pos_shifts WHERE id = @id',
        parameters: {'id': shift.id},
      );
      expect(stored.first[0], 10000, reason: 'the first count stands');
    });

    test('closing frees the terminal for the next shift', () async {
      final first = await shifts().open(by: sara, openingFloat: Money.zero);
      await shifts().close(shift: first, by: sara, countedCash: Money.zero);

      final second = await shifts().open(by: omar, openingFloat: Money(10000));
      expect(second.id, isNot(first.id));
      expect(second.openedByName, 'Omar T.');
    });
  });

  test('a sale is stamped with the shift that was open when it was rung up', () async {
    final shift = await shifts().open(by: sara, openingFloat: Money.zero);
    await sell(shift, priceMinor: 10000);

    final rows = await db.query(pg.config, 'SELECT shift_id FROM pos_orders');
    expect(rows.first[0], shift.id);
  });
}
