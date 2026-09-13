@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_business_day_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_parked_tickets.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

import 'pg_fixture.dart';

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
  late int restaurantId;
  late int branchId;
  late int tableId;

  late PosStaff nour;

  const terminal = '7f8c3a52-0000-4000-8000-000000000001';

  setUp(() async {
    pg = await PgFixture.open('parked_tickets');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('parked', 'Parked') "
      'RETURNING id',
    )).first[0]! as int;

    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    tableId = (await db.query(
      pg.config,
      'INSERT INTO pos_dining_tables (restaurant_id, branch_id, label, seats) '
      "VALUES (@r, @b, 'T12', 4) RETURNING id",
      parameters: {'r': restaurantId, 'b': branchId},
    )).first[0]! as int;

    nour = PosStaff(
      id: (await db.query(
        pg.config,
        'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, '
        "  pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', 'nour', 's', 'h') "
        'RETURNING id',
        parameters: {'r': restaurantId, 'b': branchId},
      )).first[0]! as int,
      name: 'Nour Adel',
    );

    store = PostgresParkedTickets(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
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
    await store.save(_ticket(id));
    final again = TicketEngine.addLine(_ticket(id), _burger).ticket!;
    await store.save(again);

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
    await store.save(
      _ticket(
        '33333333-3333-4333-8333-333333333333',
        tableId: tableId,
        type: OrderType.dineIn,
      ),
    );

    // The unique index does the refusing, not the Dart. One row, holding the
    // ticket that arrived last.
    expect(await rowCount(), 1);
    final loaded = await store.load(_catalog);
    expect(loaded.onTables[tableId]!.id, '33333333-3333-4333-8333-333333333333');
    expect(loaded.held, isEmpty);
  });

  test('a row that names neither a table nor a branch is refused', () async {
    // The one thing this table must never hold: a parked ticket no till would
    // hydrate and no day close would count.
    await expectLater(
      db.query(
        pg.config,
        'INSERT INTO pos_parked_tickets (restaurant_id, client_transaction_id, '
        "  payload) VALUES (@r, gen_random_uuid(), '{}'::jsonb)",
        parameters: {'r': restaurantId},
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
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1')",
      parameters: {'t': terminal, 'r': restaurantId, 'b': branchId},
    );
    final days = PostgresBusinessDayRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        restaurantId: restaurantId,
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
    // A restaurant with a seated table when the update installs. The migration
    // has to loosen the key **and** backfill the branch off the table, or that
    // table's ticket stops being counted by the day close it used to block.
    await db.query(
      pg.config,
      'INSERT INTO pos_parked_tickets (restaurant_id, table_id, '
      "  client_transaction_id, payload) VALUES (@r, @t, @x::uuid, @p::jsonb)",
      parameters: {
        'r': restaurantId,
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
          'PRIMARY KEY (restaurant_id, table_id)',
      'DELETE FROM schema_migrations WHERE version = 32',
    ]) {
      await db.query(pg.config, statement);
    }

    expect(await PosMigrator(db).migrate(pg.config), contains(32));

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
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'TWO', 'Second') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    await PostgresParkedTickets(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: otherBranch,
    ).save(_ticket('44444444-4444-4444-8444-444444444444'));

    // Restaurant-scoped hydration would have handed this till the other shop's
    // ticket, with no table label to hint that it was not theirs.
    expect((await store.load(_catalog)).held, isEmpty);
  });
}
