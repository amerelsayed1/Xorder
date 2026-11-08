@Tags(['integration'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/dining_table.dart';
import 'package:shared_module/domain/models/ticket.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// XORD-044, through the real provider graph: two tills on one branch database.
///
/// Each till is its own [ProviderContainer] with its own floor in memory, both
/// bound to the same PostgreSQL — which is exactly a business with a counter
/// till and a second till by the terrace. Before the fix the second till's
/// floor never changed after boot, and parking on a table it believed free
/// replaced the first till's check on that table.
void main() {
  if (PgFixture.host == null) {
    test('two tills, one floor (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late DiningTable t3;

  setUp(() async {
    pg = await PgFixture.open('floor_two_tills');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('floor', 'Floor') "
      'RETURNING id',
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;
    final tableId = (await db.query(
      pg.config,
      'INSERT INTO pos_dining_tables (business_id, branch_id, label, seats) '
      "VALUES (@r, @b, 'T3', 4) RETURNING id",
      parameters: {'r': businessId, 'b': branchId},
    )).first[0]! as int;
    t3 = DiningTable(id: tableId, label: 'T3', seats: 4);
  });

  tearDown(() => pg.close());

  Future<ProviderContainer> till(String terminalId) async {
    final container = ProviderContainer(
      overrides: [
        posDatabaseProvider.overrideWithValue(db),
        posDbCredentialsProvider
            .overrideWithValue(InMemoryPosDbCredentials(PgFixture.password)),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      ],
    );
    addTearDown(container.dispose);
    container.read(deploymentProvider.notifier).apply(pg.config);
    container.read(terminalProfileProvider.notifier).apply(TerminalProfile(
          businessId: businessId,
          branchId: branchId,
          branchCode: 'MAIN',
          branchName: 'Main',
          terminalName: 'Till $terminalId',
          terminalId: terminalId,
          provisioned: true,
        ));
    // Build the floor and let its boot hydration finish.
    container.read(openTicketsProvider);
    await container.read(catalogProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return container;
  }

  Future<Product> anyProduct(ProviderContainer c) async =>
      (await c.read(catalogProvider.future)).products.first;

  /// Seat [table] on [c]'s screen, ring up [count] of a product, and return
  /// the live ticket.
  Future<Ticket> ringUp(ProviderContainer c, DiningTable table, int count) async {
    final tickets = c.read(ticketProvider.notifier);
    tickets.attachTable(table);
    tickets.addProduct(await anyProduct(c), quantity: count);
    return c.read(ticketProvider);
  }

  Future<int> rowsOnT3() async => (await db.query(
        pg.config,
        'SELECT count(*) FROM pos_parked_tickets WHERE table_id = @t',
        parameters: {'t': t3.id},
      )).first[0]! as int;

  test('a till whose floor still shows the table free cannot replace its check',
      () async {
    final a = await till('7f8c3a52-0000-4000-8000-0000000000a1');
    final b = await till('7f8c3a52-0000-4000-8000-0000000000b2');

    final first = await ringUp(a, t3, 2);
    expect(await a.read(openTicketsProvider.notifier).park(first),
        ParkOutcome.parked);

    // B booted before A seated T3 and has not refreshed: T3 looks free there.
    expect(b.read(openTicketsProvider.notifier).at(t3.id), isNull);
    final second = await ringUp(b, t3, 1);
    expect(await b.read(openTicketsProvider.notifier).park(second),
        ParkOutcome.changedElsewhere);

    // The stored check is still A's, lines and all.
    expect(await rowsOnT3(), 1);
    final stored = await db.query(
      pg.config,
      'SELECT client_transaction_id::text FROM pos_parked_tickets '
      'WHERE table_id = @t',
      parameters: {'t': t3.id},
    );
    expect(stored.single[0], first.id);

    // And the refusal asked B's floor to catch up.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(b.read(openTicketsProvider.notifier).at(t3.id)?.id, first.id);
  });

  test('a stale copy of the same check cannot overwrite a newer one', () async {
    final a = await till('7f8c3a52-0000-4000-8000-0000000000a1');
    final first = await ringUp(a, t3, 1);
    expect(await a.read(openTicketsProvider.notifier).park(first),
        ParkOutcome.parked);

    // B boots now and sees T3 with A's check; both open it.
    final b = await till('7f8c3a52-0000-4000-8000-0000000000b2');
    final onB = b.read(openTicketsProvider.notifier).at(t3.id)!;
    expect(onB.id, first.id);

    // A adds a round and parks: the row moves on.
    a.read(ticketProvider.notifier).adopt(first);
    a.read(ticketProvider.notifier).addProduct(await anyProduct(a));
    expect(
      await a.read(openTicketsProvider.notifier).park(a.read(ticketProvider)),
      ParkOutcome.parked,
    );

    // B, still holding the older copy, adds something and parks.
    b.read(ticketProvider.notifier).adopt(onB);
    b.read(ticketProvider.notifier).addProduct(await anyProduct(b));
    expect(
      await b.read(openTicketsProvider.notifier).park(b.read(ticketProvider)),
      ParkOutcome.changedElsewhere,
    );

    await b.read(openTicketsProvider.notifier).refresh();
    expect(
      b.read(openTicketsProvider.notifier).at(t3.id)!.lines.single.quantity,
      2,
      reason: "A's newer check, not B's stale one",
    );
  });

  test('another till sees a seated table without a restart', () async {
    final a = await till('7f8c3a52-0000-4000-8000-0000000000a1');
    final b = await till('7f8c3a52-0000-4000-8000-0000000000b2');
    expect(b.read(openTicketsProvider.notifier).at(t3.id), isNull);

    final first = await ringUp(a, t3, 1);
    await a.read(openTicketsProvider.notifier).park(first);

    // No call from the test: the till's own periodic refresh picks it up.
    await Future<void>.delayed(
      OpenTicketsController.refreshEvery + const Duration(seconds: 2),
    );
    expect(b.read(openTicketsProvider.notifier).at(t3.id)?.id, first.id);

    // And a settlement on A frees the table on B the same way.
    await a.read(openTicketsProvider.notifier).settle(first);
    await b.read(openTicketsProvider.notifier).refresh();
    expect(b.read(openTicketsProvider.notifier).at(t3.id), isNull);
  });

  test('two tills cannot overwrite the same held ticket (XORD-046)', () async {
    final a = await till('7f8c3a52-0000-4000-8000-0000000000a1');
    final b = await till('7f8c3a52-0000-4000-8000-0000000000b2');

    final tickets = a.read(ticketProvider.notifier);
    tickets.setOrderType(OrderType.takeaway);
    tickets.addProduct(await anyProduct(a));
    final takeaway = a.read(ticketProvider);
    expect(await a.read(openTicketsProvider.notifier).park(takeaway),
        ParkOutcome.parked);

    await b.read(openTicketsProvider.notifier).refresh();
    final onB = b.read(openTicketsProvider).held.single;
    expect(onB.id, takeaway.id);

    // Both resume it; A adds an item and puts it down first.
    a.read(ticketProvider.notifier).adopt(takeaway);
    a.read(ticketProvider.notifier).addProduct(await anyProduct(a));
    expect(
      await a.read(openTicketsProvider.notifier).park(a.read(ticketProvider)),
      ParkOutcome.parked,
    );

    b.read(ticketProvider.notifier).adopt(onB);
    b.read(ticketProvider.notifier).addProduct(await anyProduct(b));
    b.read(ticketProvider.notifier).addProduct(await anyProduct(b));
    expect(
      await b.read(openTicketsProvider.notifier).park(b.read(ticketProvider)),
      ParkOutcome.changedElsewhere,
    );

    await b.read(openTicketsProvider.notifier).refresh();
    expect(
      b.read(openTicketsProvider).held.single.lines.single.quantity,
      2,
      reason: "A's copy, not B's",
    );
  });
}
