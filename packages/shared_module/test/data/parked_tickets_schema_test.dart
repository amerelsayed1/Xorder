@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_business_day_repository.dart';
import 'package:shared_module/data/postgres/postgres_orders_repository.dart';
import 'package:shared_module/data/postgres/postgres_parked_tickets.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

const _burger = Product(
  id: 101,
  categoryId: 11,
  nameEn: 'Classic Burger',
  price: Money(9500),
);

final _catalog = Catalog(
  categories: const [Category(id: 11, nameEn: 'Burgers')],
  products: const [_burger],
  modifierGroups: const [],
  syncedAt: DateTime.utc(2026, 9, 9),
);

Ticket _ticket(String id, {int? tableId, OrderType type = OrderType.takeaway}) {
  var ticket = Ticket(id: id, orderType: type);
  if (tableId != null) {
    ticket = TicketEngine.attachTable(ticket, tableId, 'T$tableId', guests: 2);
  }
  return TicketEngine.addLine(ticket, _burger).ticket!;
}

/// A ticket with no table, parked (§ migration 32).
///
/// The point of doing this against a real server: until migration 32 the table
/// declared `table_id NOT NULL` inside its primary key, so the interesting
/// assertions are the ones only PostgreSQL can make — that a held row is
/// *allowed*, that a second one is allowed beside it, that a table still holds
/// at most one ticket, and that a held ticket blocks a day close. Every one of
/// those was a Dart-level assumption before.
void main() {
  if (PgFixture.host == null) {
    test('parked tickets (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresParkedTickets store;
  late int businessId;
  late int branchId;
  late int tableId;

  late PosStaff nour;

  const terminal = '7f8c3a52-0000-4000-8000-000000000001';

  setUp(() async {
    pg = await PgFixture.open('parked_tickets');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    // Orders first: the payment cases below leave some, and a sale pins its
    // business (the shared test database also carries other suites' sales).
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('parked', 'Parked') "
      'RETURNING id',
    )).first[0]! as int;

    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    tableId = (await db.query(
      pg.config,
      'INSERT INTO pos_dining_tables (business_id, branch_id, label, seats) '
      "VALUES (@r, @b, 'T12', 4) RETURNING id",
      parameters: {'r': businessId, 'b': branchId},
    )).first[0]! as int;

    nour = PosStaff(
      id: (await db.query(
        pg.config,
        'INSERT INTO pos_users (business_id, branch_id, name, username, '
        "  pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', 'nour', 's', 'h') "
        'RETURNING id',
        parameters: {'r': businessId, 'b': branchId},
      )).first[0]! as int,
      name: 'Nour Adel',
    );

    store = PostgresParkedTickets(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  Future<int> rowCount() async =>
      (await db.query(pg.config, 'SELECT count(*) FROM pos_parked_tickets'))
              .first[0]!
          as int;

  test('a ticket with no table is stored, and comes back held', () async {
    await store.save(_ticket('11111111-1111-4111-8111-111111111111'));

    final loaded = await store.load(_catalog);
    expect(loaded.onTables, isEmpty);
    expect(loaded.held, hasLength(1));
    expect(loaded.held.single.id, '11111111-1111-4111-8111-111111111111');
    expect(loaded.held.single.orderType, OrderType.takeaway);
    expect(loaded.held.single.lines.single.product.id, 101);
  });

  test('two held tickets sit side by side', () async {
    // The old primary key made this impossible: with `table_id` in the key and
    // NOT NULL, there was no room for a second ticket that had no table — and
    // a counter serving two walk-ins at once is a Tuesday, not an edge case.
    await store.save(_ticket('11111111-1111-4111-8111-111111111111'));
    await store.save(_ticket('22222222-2222-4222-8222-222222222222'));

    expect((await store.load(_catalog)).held, hasLength(2));
  });

  test('parking the same held ticket twice updates one row', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    final v0 = await store.save(_ticket(id));
    final again = TicketEngine.addLine(_ticket(id), _burger).ticket!;
    await store.save(again, expectedVersion: v0);

    expect(await rowCount(), 1);
    expect((await store.load(_catalog)).held.single.lines.single.quantity, 2);
  });

  test('a table still holds at most one ticket', () async {
    await store.save(
      _ticket(
        '11111111-1111-4111-8111-111111111111',
        tableId: tableId,
        type: OrderType.dineIn,
      ),
    );
    // A second ticket on the same table is refused, not swapped in. Until
    // XORD-044 the ticket that arrived last silently replaced the first.
    await expectLater(
      store.save(
        _ticket(
          '33333333-3333-4333-8333-333333333333',
          tableId: tableId,
          type: OrderType.dineIn,
        ),
      ),
      throwsA(isA<ParkedTicketChanged>()),
    );

    expect(await rowCount(), 1);
    final loaded = await store.load(_catalog);
    expect(loaded.onTables[tableId]!.id, '11111111-1111-4111-8111-111111111111');
    expect(loaded.held, isEmpty);
  });

  // XORD-044: the table's check is a compare-and-swap on its version.
  group('two tills on one table', () {
    const first = '11111111-1111-4111-8111-111111111111';
    late PostgresParkedTickets other;

    setUp(() {
      // A second till: same branch, its own store, its own idea of the floor.
      other = PostgresParkedTickets(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branchId,
      );
    });

    Ticket seated(String id, {int extra = 0}) {
      var ticket = _ticket(id, tableId: tableId, type: OrderType.dineIn);
      for (var i = 0; i < extra; i++) {
        ticket = TicketEngine.addLine(ticket, _burger).ticket!;
      }
      return ticket;
    }

    Future<int> quantityStored() async =>
        (await store.load(_catalog)).onTables[tableId]!.lines.single.quantity;

    test('a save over the version it read moves the version on', () async {
      final v0 = await store.save(seated(first));
      final v1 = await store.save(seated(first, extra: 1), expectedVersion: v0);
      expect(v1, v0 + 1);
      expect((await other.refresh(_catalog)).versions[tableId], v1);
    });

    test('a stale version is refused and the newer check is kept', () async {
      final v0 = await store.save(seated(first));
      // Both tills hold v0; this one saves first.
      await store.save(seated(first, extra: 1), expectedVersion: v0);

      await expectLater(
        other.save(seated(first, extra: 3), expectedVersion: v0),
        throwsA(isA<ParkedTicketChanged>()),
      );
      expect(await quantityStored(), 2);
    });

    test('a check cleared on another till is not brought back', () async {
      final v0 = await store.save(seated(first));
      await other.remove(tableId: tableId, transactionId: first);

      await expectLater(
        store.save(seated(first, extra: 1), expectedVersion: v0),
        throwsA(isA<ParkedTicketChanged>()),
      );
      expect(await rowCount(), 0);
    });

    test("clearing a table never deletes another ticket's check", () async {
      await store.save(seated(first));
      // Another till lets go of a different ticket it thought was on this
      // table, holding no version for the row actually there.
      await other.remove(
        tableId: tableId,
        transactionId: '33333333-3333-4333-8333-333333333333',
      );
      expect(await rowCount(), 1);
      expect((await store.load(_catalog)).onTables[tableId]!.id, first);
    });

    // XORD-045: paying from a copy of the check that is no longer the table's.
    group('paying it', () {
      late PostgresOrdersRepository orders;

      setUp(() async {
        await db.query(
          pg.config,
          'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
          "VALUES (@t::uuid, @r, @b, 'Counter 1')",
          parameters: {'t': terminal, 'r': businessId, 'b': branchId},
        );
        orders = PostgresOrdersRepository(
          database: db,
          config: pg.config,
          context: PosWriteContext(
            businessId: businessId,
            branchId: branchId,
            terminalId: terminal,
            branchCode: 'MAIN',
          ),
        );
      });

      Ticket paid(Ticket ticket) => TicketEngine.addTender(
        ticket,
        typeId: 1,
        label: 'Cash',
        countsAsCash: true,
      ).ticket!;

      Future<int> orderCount() async =>
          (await db.query(pg.config, 'SELECT count(*) FROM pos_orders'))
                  .first[0]!
              as int;

      test('the current check is paid and let go in one go', () async {
        final v0 = await store.save(seated(first));
        await orders.submit(paid(seated(first)), parkedVersion: v0);

        expect(await orderCount(), 1);
        expect(await rowCount(), 0, reason: 'cleared with the sale');
      });

      test('an outdated copy is refused and nothing is recorded', () async {
        final v0 = await store.save(seated(first));
        // The other till adds a round after this one read the check.
        await other.save(seated(first, extra: 1), expectedVersion: v0);

        await expectLater(
          orders.submit(paid(seated(first)), parkedVersion: v0),
          throwsA(isA<CheckChangedElsewhere>()),
        );
        expect(await orderCount(), 0);
        expect(await quantityStored(), 2, reason: "the other till's round");
      });

      test('a check voided or moved on another till is not paid', () async {
        final v0 = await store.save(seated(first));
        await other.remove(tableId: tableId, transactionId: first);

        await expectLater(
          orders.submit(paid(seated(first)), parkedVersion: v0),
          throwsA(isA<CheckChangedElsewhere>()),
        );
        expect(await orderCount(), 0);
      });

      test('a ticket rung up and paid without parking is not refused', () async {
        await orders.submit(paid(seated(first)));
        expect(await orderCount(), 1);
      });

      test('a round parked after the payment is refused, not lost', () async {
        final v0 = await store.save(seated(first));
        await orders.submit(paid(seated(first)), parkedVersion: v0);

        await expectLater(
          other.save(seated(first, extra: 1), expectedVersion: v0),
          throwsA(isA<ParkedTicketChanged>()),
        );
        expect(await rowCount(), 0, reason: 'no paid check comes back');
      });

      // Voiding goes through the same guard (XORD-046 follow-up).
      PosStaff supervisor() => PosStaff(
        id: nour.id,
        name: nour.name,
        role: const PosRole(
          id: 1,
          code: SystemRoles.supervisorCode,
          nameEn: 'Supervisor',
          capabilities: SystemRoles.supervisor,
        ),
      );

      test('voiding the current check records it and lets the table go',
          () async {
        final v0 = await store.save(seated(first));
        await orders.voidOrder(
          seated(first),
          by: supervisor(),
          parkedVersion: v0,
        );
        expect(await orderCount(), 1);
        expect(await rowCount(), 0);
      });

      test('voiding an outdated copy is refused and nothing is recorded',
          () async {
        final v0 = await store.save(seated(first));
        await other.save(seated(first, extra: 1), expectedVersion: v0);

        await expectLater(
          orders.voidOrder(seated(first), by: supervisor(), parkedVersion: v0),
          throwsA(isA<CheckChangedElsewhere>()),
        );
        expect(await orderCount(), 0);
        expect(await quantityStored(), 2, reason: "the other till's round");
      });

      test('clearing an outdated copy leaves the newer check', () async {
        // A ticket cleared before anything was sent writes no order; it only
        // lets go of its parked row — and must not let go of a newer one.
        final v0 = await store.save(seated(first));
        await other.save(seated(first, extra: 1), expectedVersion: v0);

        await store.remove(
          tableId: tableId,
          transactionId: first,
          expectedVersion: v0,
        );
        expect(await quantityStored(), 2);
      });

      test('paying the same sale again replays it, version or not', () async {
        final v0 = await store.save(seated(first));
        final ticket = paid(seated(first));
        final once = await orders.submit(ticket, parkedVersion: v0);
        // The retry after a lost reply: the row is gone and the version old.
        final again = await orders.submit(ticket, parkedVersion: v0);

        expect(again.serverId, once.serverId);
        expect(await orderCount(), 1);
      });
    });

    test('the other till reads what this one seated', () async {
      expect((await other.refresh(_catalog)).onTables, isEmpty);
      await store.save(seated(first));
      final seen = await other.refresh(_catalog);
      expect(seen.onTables[tableId]!.id, first);
      expect(seen.versions[tableId], isNotNull);
    });
  });

  // XORD-046: a held ticket is shown to every till on the branch, so it gets
  // the same compare-and-swap as a table's check.
  group('two tills on one held ticket', () {
    const id = '22222222-2222-4222-8222-222222222222';
    late PostgresParkedTickets other;

    setUp(() {
      other = PostgresParkedTickets(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branchId,
      );
    });

    Ticket held({int extra = 0}) {
      var ticket = _ticket(id);
      for (var i = 0; i < extra; i++) {
        ticket = TicketEngine.addLine(ticket, _burger).ticket!;
      }
      return ticket;
    }

    Future<int> quantityHeld() async =>
        (await store.load(_catalog)).held.single.lines.single.quantity;

    test('both read it; the second to save an old copy is refused', () async {
      final v0 = await store.save(held());
      expect((await other.refresh(_catalog)).heldVersions[id], v0);

      await store.save(held(extra: 1), expectedVersion: v0);
      await expectLater(
        other.save(held(extra: 3), expectedVersion: v0),
        throwsA(isA<ParkedTicketChanged>()),
      );
      expect(await quantityHeld(), 2, reason: 'the first save is kept');
      expect(await rowCount(), 1);
    });

    test('a till that never saw it cannot park over it', () async {
      await store.save(held());
      await expectLater(
        other.save(held(extra: 1)),
        throwsA(isA<ParkedTicketChanged>()),
      );
      expect(await quantityHeld(), 1);
    });

    test('a held ticket paid or voided elsewhere is not brought back', () async {
      final v0 = await store.save(held());
      await other.remove(transactionId: id);
      await expectLater(
        store.save(held(extra: 1), expectedVersion: v0),
        throwsA(isA<ParkedTicketChanged>()),
      );
      expect(await rowCount(), 0);
    });

    group('paying it', () {
      late PostgresOrdersRepository orders;

      setUp(() async {
        await db.query(
          pg.config,
          'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
          "VALUES (@t::uuid, @r, @b, 'Counter 1')",
          parameters: {'t': terminal, 'r': businessId, 'b': branchId},
        );
        orders = PostgresOrdersRepository(
          database: db,
          config: pg.config,
          context: PosWriteContext(
            businessId: businessId,
            branchId: branchId,
            terminalId: terminal,
            branchCode: 'MAIN',
          ),
        );
      });

      Ticket paid(Ticket ticket) => TicketEngine.addTender(
        ticket,
        typeId: 1,
        label: 'Cash',
        countsAsCash: true,
      ).ticket!;

      Future<int> orderCount() async =>
          (await db.query(pg.config, 'SELECT count(*) FROM pos_orders'))
                  .first[0]!
              as int;

      test('the current copy is paid and let go', () async {
        final v0 = await store.save(held());
        await orders.submit(paid(held()), parkedVersion: v0);
        expect(await orderCount(), 1);
        expect(await rowCount(), 0);
      });

      test('an outdated copy is refused and nothing is recorded', () async {
        final v0 = await store.save(held());
        await other.save(held(extra: 1), expectedVersion: v0);

        await expectLater(
          orders.submit(paid(held()), parkedVersion: v0),
          throwsA(isA<CheckChangedElsewhere>()),
        );
        expect(await orderCount(), 0);
        expect(await quantityHeld(), 2);
      });

      test('a takeaway never put down is paid as before', () async {
        await orders.submit(paid(held()));
        expect(await orderCount(), 1);
      });
    });
  });

  test('a row that names neither a table nor a branch is refused', () async {
    // The one thing this table must never hold: a parked ticket no till would
    // hydrate and no day close would count.
    await expectLater(
      db.query(
        pg.config,
        'INSERT INTO pos_parked_tickets (business_id, client_transaction_id, '
        "  payload) VALUES (@r, gen_random_uuid(), '{}'::jsonb)",
        parameters: {'r': businessId},
      ),
      throwsA(anything),
    );
  });

  test('settling a held ticket removes its row', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await store.save(_ticket(id));
    await store.remove(transactionId: id);

    expect(await rowCount(), 0);
  });

  test('a held ticket blocks the day close', () async {
    // The reason `branch_id` exists on this table at all. The blocker count used
    // to reach the branch through `pos_dining_tables`, so a ticket with no table
    // was invisible to it — an unpaid sale the day close would have closed over.
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1')",
      parameters: {'t': terminal, 'r': businessId, 'b': branchId},
    );
    final days = PostgresBusinessDayRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        businessId: businessId,
        branchId: branchId,
        terminalId: terminal,
        branchCode: 'MAIN',
      ),
    );
    await days.open(date: DateTime(2026, 9, 9), by: nour);

    expect((await days.check()).blockers, isEmpty);

    await store.save(_ticket('11111111-1111-4111-8111-111111111111'));
    final check = await days.check();
    expect(
      check.blockers.map((b) => b.kind),
      contains(DayBlockerKind.parkedTicket),
    );
    expect(check.blockers.single.count, 1);
  });

  test('the upgrade keeps the tables that were already parked', () async {
    // A business with a seated table when the update installs. The migration
    // has to loosen the key **and** backfill the branch off the table, or that
    // table's ticket stops being counted by the day close it used to block.
    await db.query(
      pg.config,
      'INSERT INTO pos_parked_tickets (business_id, table_id, '
      "  client_transaction_id, payload) VALUES (@r, @t, @x::uuid, @p::jsonb)",
      parameters: {
        'r': businessId,
        't': tableId,
        'x': '55555555-5555-4555-8555-555555555555',
        'p': '{"client_transaction_id":"55555555-5555-4555-8555-555555555555"}',
      },
    );

    // Put the schema back the way version 7 left it, then let the migrator do
    // the upgrade for real. Rewinding rather than trusting the first run means
    // this is exercised every time the suite runs, not only on a fresh machine.
    for (final statement in [
      'ALTER TABLE pos_parked_tickets '
          'DROP CONSTRAINT IF EXISTS pos_parked_tickets_locatable',
      'DROP INDEX IF EXISTS pos_parked_tickets_table_key',
      'DROP INDEX IF EXISTS pos_parked_tickets_held_key',
      'ALTER TABLE pos_parked_tickets DROP COLUMN IF EXISTS branch_id',
      'ALTER TABLE pos_parked_tickets ALTER COLUMN table_id SET NOT NULL',
      'ALTER TABLE pos_parked_tickets ADD CONSTRAINT pos_parked_tickets_pkey '
          'PRIMARY KEY (business_id, table_id)',
    ]) {
      await db.query(pg.config, statement);
    }

    expect(await pg.replay(32), contains(32));

    final rows = await db.query(
      pg.config,
      'SELECT table_id, branch_id FROM pos_parked_tickets',
    );
    expect(rows.single[0], tableId);
    expect(rows.single[1], branchId, reason: 'backfilled from its table');

    // And the loosened shape is in place: a ticket with no table now fits.
    await store.save(_ticket('66666666-6666-4666-8666-666666666666'));
    expect((await store.load(_catalog)).held, hasLength(1));
  });

  test('another branch\'s held ticket is not this till\'s to hydrate', () async {
    final otherBranch = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'TWO', 'Second') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    await PostgresParkedTickets(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: otherBranch,
    ).save(_ticket('44444444-4444-4444-8444-444444444444'));

    // Business-scoped hydration would have handed this till the other shop's
    // ticket, with no table label to hint that it was not theirs.
    expect((await store.load(_catalog)).held, isEmpty);
  });
}
