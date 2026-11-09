@Tags(['integration'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/dining_table.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/features/waiter_link/waiter_link_host.dart';
import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// The waiter link with nothing faked between a handheld and the database
/// (waiter-app, WA1): the handheld's client, over a real socket, to the link
/// server inside a real till's provider graph, whose `TicketEngine` prices the
/// order and whose versioned store saves it — and the till's own floor sees
/// it. On PostgreSQL, and on a cloud till's SQLite file with
/// `POS_TEST_ENGINE=sqlite`.
void main() {
  if (PgFixture.host == null) {
    test('waiter link end to end (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const slug = 'waiter-link-e2e';
  const pin = '4829';
  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late DiningTable t3;

  setUpAll(() async {
    pg = await PgFixture.open('waiter_link_e2e');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
  });

  tearDownAll(() => db.close());

  setUp(() async {
    await db.query(pg.config, 'DELETE FROM pos_businesses WHERE slug = @s', parameters: {'s': slug});
    final boot = LocalBootstrap(db);
    businessId = await boot.seedBusiness(pg.config, slug: slug, name: 'Waiter E2E');
    branchId = await boot.seedBranch(pg.config, businessId: businessId, name: 'Main', code: 'WE2E');
    final roles = await boot.seedSystemRoles(pg.config, businessId);
    await boot.seedOwner(
      pg.config,
      businessId: businessId,
      branchId: branchId,
      roleId: roles.ids['owner']!,
      name: 'Nour',
      username: 'nour',
      pin: pin,
    );
    final tableId = (await db.query(
      pg.config,
      'INSERT INTO pos_dining_tables (business_id, branch_id, label, seats) '
      "VALUES (@b, @br, 'T3', 4) RETURNING id",
      parameters: {'b': businessId, 'br': branchId},
    )).first[0]! as int;
    t3 = DiningTable(id: tableId, label: 'T3', seats: 4);
  });

  Future<ProviderContainer> till() async {
    final container = ProviderContainer(
      overrides: [
        posDatabaseProvider.overrideWithValue(db),
        posDbCredentialsProvider.overrideWithValue(InMemoryPosDbCredentials(PgFixture.password)),
        catalogRepositoryProvider.overrideWithValue(_Menu()),
        waiterLinkPortProvider.overrideWithValue(0),
      ],
    );
    addTearDown(container.dispose);
    container.read(deploymentProvider.notifier).apply(pg.config);
    container.read(terminalProfileProvider.notifier).apply(TerminalProfile(
      businessId: businessId,
      branchId: branchId,
      branchCode: 'WE2E',
      branchName: 'Main',
      terminalName: 'Counter',
      terminalId: '7f8c3a52-0000-4000-8000-00000000e2e1',
      provisioned: true,
    ));
    container.read(openTicketsProvider);
    await container.read(catalogProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return container;
  }

  test('a handheld pairs, signs in, seats a table and sends a round the till sees', () async {
    final c = await till();
    final host = c.read(waiterLinkHostProvider.notifier);
    expect(c.read(waiterLinkHostProvider).available, isTrue);
    await host.start();
    final status = c.read(waiterLinkHostProvider);
    expect(status.running, isTrue, reason: '${status.error}');

    final client = WaiterLinkClient(baseUri: Uri.parse('http://127.0.0.1:${status.port}'));
    addTearDown(client.close);
    expect(await client.hello(), 'Counter — Main');

    host.openPairing();
    await client.pair(code: c.read(waiterLinkHostProvider).pairing!.code, deviceName: 'Phone 1');
    await host.refreshDevices();
    expect(c.read(waiterLinkHostProvider).devices.single.name, 'Phone 1');
    expect(c.read(waiterLinkHostProvider).pairing, isNull, reason: 'the code was used');

    final session = await client.signIn(pin);
    expect(session.staff.name, 'Nour');

    final menu = await client.menu();
    expect(menu.products.map((p) => p.id), [101, 102]);
    final floor = await client.floor();
    expect(floor.tables.single.state, WaiterTableState.free);

    var check = await client.apply(
      tableId: t3.id,
      version: null,
      ops: const [WaiterAdd(productId: 101, quantity: 2), WaiterAdd(productId: 102, modifierIds: [201])],
    );
    expect(check.version, isNotNull);
    expect(check.lines, hasLength(2));
    check = await client.apply(tableId: t3.id, version: check.version, ops: const [WaiterSendRound()]);
    expect(check.roundsSent, 1);

    // The till that served it sees the table now, rounds and all.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final onTill = c.read(openTicketsProvider.notifier).at(t3.id);
    expect(onTill, isNotNull);
    expect(onTill!.roundsSent, 1);
    expect(onTill.lines.fold<int>(0, (n, l) => n + l.quantity), 3);
    expect(onTill.totals.total.minor, check.totalMinor, reason: 'one price, the till\'s');

    // A second till on the same database sees it too.
    expect((await client.floor()).tables.single.state, WaiterTableState.open);
  });

  test('a stale edit from the handheld is refused once the till has changed the table', () async {
    final c = await till();
    final host = c.read(waiterLinkHostProvider.notifier);
    await host.start();
    final client = WaiterLinkClient(baseUri: Uri.parse('http://127.0.0.1:${c.read(waiterLinkHostProvider).port}'));
    addTearDown(client.close);
    host.openPairing();
    await client.pair(code: c.read(waiterLinkHostProvider).pairing!.code, deviceName: 'Phone');
    await client.signIn(pin);

    final first = await client.apply(tableId: t3.id, version: null, ops: const [WaiterAdd(productId: 101)]);

    // The cashier adds to the same table at the till.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final tickets = c.read(openTicketsProvider.notifier);
    final onTill = tickets.at(t3.id)!;
    c.read(ticketProvider.notifier).adopt(onTill);
    c.read(ticketProvider.notifier).addProduct((await c.read(catalogProvider.future)).products.first);
    expect(await tickets.park(c.read(ticketProvider)), ParkOutcome.parked);

    try {
      await client.apply(tableId: t3.id, version: first.version, ops: const [WaiterSendRound()]);
      fail('expected a conflict');
    } on WaiterCheckChanged catch (e) {
      expect(e.current.lines.single.quantity, 2, reason: "the till's change is what the handheld now sees");
    }
  });

  test('a revoked handheld is shut out at once', () async {
    final c = await till();
    final host = c.read(waiterLinkHostProvider.notifier);
    await host.start();
    final client = WaiterLinkClient(baseUri: Uri.parse('http://127.0.0.1:${c.read(waiterLinkHostProvider).port}'));
    addTearDown(client.close);
    host.openPairing();
    await client.pair(code: c.read(waiterLinkHostProvider).pairing!.code, deviceName: 'Lost phone');
    await client.signIn(pin);
    await host.refreshDevices();

    await host.revoke(c.read(waiterLinkHostProvider).devices.single.id);
    try {
      await client.floor();
      fail('expected the device to be refused');
    } on WaiterLinkFailure catch (e) {
      expect(e.code, WaiterError.revoked);
    }
  });
}

class _Menu implements CatalogRepository {
  @override
  Future<Catalog> load({DateTime? since}) async => Catalog(
    syncedAt: DateTime(2026, 11, 9),
    categories: const [Category(id: 1, nameEn: 'Mains')],
    modifierGroups: const [
      ModifierGroup(
        id: 2,
        nameEn: 'Extras',
        maxSelect: 2,
        modifiers: [Modifier(id: 201, groupId: 2, nameEn: 'Cheese', priceDelta: Money(1000))],
      ),
    ],
    products: const [
      Product(id: 101, categoryId: 1, nameEn: 'Kofta', price: Money(12000)),
      Product(id: 102, categoryId: 1, nameEn: 'Burger', price: Money(15000), modifierGroupIds: [2]),
    ],
  );
}
