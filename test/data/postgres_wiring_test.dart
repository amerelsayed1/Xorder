@Tags(['integration'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/unconfigured/unconfigured_repositories.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';

import 'pg_fixture.dart';

/// End-to-end through the **real provider graph**.
///
/// The unit tests cover the SQL and the widget tests cover the UI, but neither
/// exercises the seam between them: whether `ordersRepositoryProvider` actually
/// resolves to Postgres once a terminal is provisioned, and whether a ticket
/// built by `TicketEngine` — rather than hand-assembled in a test — survives the
/// trip. That seam is where a swap-point bug would hide.
void main() {
  if (PgFixture.host == null) {
    test('provider wiring (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase database;
  late DeploymentConfig branchConfig;

  setUp(() async {
    pg = await PgFixture.open('wiring');
    database = pg.database;
    branchConfig = pg.config;
    await PosMigrator(database).migrate(branchConfig);
    await pg.truncate();
  });

  tearDown(() => pg.close());

  ProviderContainer containerFor({required bool provisioned}) {
    final container = ProviderContainer(
      overrides: [
        posDatabaseProvider.overrideWithValue(database),
        posDbCredentialsProvider
            .overrideWithValue(InMemoryPosDbCredentials(PgFixture.password)),
        // The menu is not what this suite is about — the orders swap point is.
        // Bind the fake catalogue explicitly rather than seeding a restaurant
        // into the wiring database just to have something priced to sell.
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      ],
    );
    addTearDown(container.dispose);

    container.read(deploymentProvider.notifier).apply(branchConfig);
    if (provisioned) {
      container.read(terminalProfileProvider.notifier).apply(const TerminalProfile(
            restaurantId: 1,
            branchId: 13,
            branchCode: 'MAADI',
            branchName: 'Maadi',
            terminalName: 'Counter 1',
            terminalId: '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
            provisioned: true,
          ));
    }
    return container;
  }

  test('an unprovisioned terminal cannot take money, and says so', () {
    final container = containerFor(provisioned: false);
    // Falling back rather than throwing at construction is deliberate: a
    // terminal mid-setup has no database yet, and a provider that threw would
    // take the app down before the wizard could fix it. What it falls back to
    // matters just as much — this used to be a fake that accepted the sale and
    // reported it queued, which printed "QUEUED OFFLINE" on a receipt for a
    // sale written nowhere at all.
    expect(container.read(ordersRepositoryProvider), isA<UnconfiguredOrdersRepository>());
  });

  test('a provisioned terminal on a branch server gets Postgres', () {
    final container = containerFor(provisioned: true);
    expect(container.read(ordersRepositoryProvider), isA<PostgresOrdersRepository>());
  });

  test('a cloud terminal never gets Postgres, however complete its profile', () {
    final container = containerFor(provisioned: true);
    container.read(deploymentProvider.notifier).apply(
          const DeploymentConfig(mode: DeploymentMode.cloud, baseUrl: 'https://xorder.io'),
        );
    // Cloud has no branch box on the LAN. Handing it a Postgres repository would
    // point it at a host that does not exist — and until an ApiOrdersRepository
    // exists there is nothing else for it to write to, so it refuses.
    expect(container.read(ordersRepositoryProvider), isA<UnconfiguredOrdersRepository>());
  });

  test('a ticket built by the engine lands in Postgres with the engine\'s own totals', () async {
    final container = containerFor(provisioned: true);
    final catalog = await container.read(catalogProvider.future);
    final product = catalog.products.first;

    // Drive the real controller rather than constructing a Ticket by hand, so
    // the money the database receives is the money TicketEngine computed.
    final ticketController = container.read(ticketProvider.notifier);
    ticketController.addProduct(product, quantity: 3);
    container.read(ticketProvider.notifier).addTender(typeId: 1, label: 'Cash');

    final ticket = container.read(ticketProvider);
    final expectedTotal = ticket.totals.total.minor;
    expect(expectedTotal, greaterThan(0), reason: 'the fixture must actually cost something');

    final result = await container.read(ordersRepositoryProvider).submit(ticket);
    expect(result.invoiceNumber, 'MAADI-2026-000001');

    final stored = await database.query(
      branchConfig,
      'SELECT total_minor, currency, exponent, terminal_id, order_type FROM pos_orders',
    );
    expect(stored.length, 1);
    expect(stored.first[0], expectedTotal, reason: 'the till and the ledger must agree exactly');
    expect(stored.first[1], ticket.currency);
    expect(stored.first[2], ticket.exponent);
    expect(stored.first[3].toString(), '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10');
    expect(stored.first[4], ticket.orderType.wire);
  });

  test('the sale after a clear is a new sale, not a replay', () async {
    final container = containerFor(provisioned: true);
    final catalog = await container.read(catalogProvider.future);
    final controller = container.read(ticketProvider.notifier);
    final repository = container.read(ordersRepositoryProvider);

    controller.addProduct(catalog.products.first);
    controller.addTender(typeId: 1, label: 'Cash');
    final first = await repository.submit(container.read(ticketProvider));

    // `reset` mints a fresh client_transaction_id. If it did not, the unique
    // index would silently swallow the second sale and the till would take money
    // for an order that was never recorded.
    controller.reset();
    controller.addProduct(catalog.products.first);
    controller.addTender(typeId: 1, label: 'Cash');
    final second = await repository.submit(container.read(ticketProvider));

    expect(second.serverId, isNot(first.serverId));
    expect(second.invoiceNumber, 'MAADI-2026-000002');

    final count = await database.query(branchConfig, 'SELECT count(*) FROM pos_orders');
    expect(count.first[0], 2);
  });

  group('the wizard Test connection button, against a real database', () {
    ProviderContainer wizardContainer() {
      // Deliberately NOT the fixture's database: that one is hardwired to the
      // correct password, which would mask exactly the failures this group is
      // supposed to catch. Build one that reads the wizard's own credential
      // store, as production does.
      final container = ProviderContainer();
      // `posDatabaseProvider` closes its own pool via ref.onDispose, so
      // disposing the container is enough.
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);
      controller.setMode(DeploymentMode.branchServer);
      controller.setBaseUrl(branchConfig.baseUrl!);
      controller.setUpstreamUrl('https://xorder.io');
      controller.setVerifyTls(false);
      controller.setDatabaseName(branchConfig.databaseName);
      controller.setDatabaseUser(branchConfig.databaseUser);
      controller.setDatabasePort(branchConfig.databasePort.toString());
      return container;
    }

    test('reports success with the right credential', () async {
      final container = wizardContainer();
      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword(PgFixture.password);

      expect(await controller.testConnection(), isTrue);
      expect(container.read(setupProvider).error, isNull);
      expect(container.read(setupProvider).busy, isFalse);
    });

    test('a wrong password is reported as a password problem, not a network one', () async {
      // The distinction is the entire point of the button. Sending an installer
      // to open a firewall port when the password is wrong wastes a site visit.
      final container = wizardContainer();
      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword('definitely-not-it');

      expect(await controller.testConnection(), isFalse);
      expect(container.read(setupProvider).error, contains('username or password'));
      expect(container.read(setupProvider).busy, isFalse);
    });

    test('a wrong port is reported as nothing listening', () async {
      final container = wizardContainer();
      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword(PgFixture.password);
      controller.setDatabasePort('55998');

      expect(await controller.testConnection(), isFalse);
      expect(container.read(setupProvider).error, contains('Nothing answered on port 55998'));
    });

    test('a wrong database name is reported as the database, not the credential', () async {
      final container = wizardContainer();
      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword(PgFixture.password);
      controller.setDatabaseName('no_such_database');

      expect(await controller.testConnection(), isFalse);
      expect(container.read(setupProvider).error, contains('no_such_database'));
    });

    test('a failed test does not leave a stale credential behind', () async {
      final container = wizardContainer();
      final controller = container.read(setupProvider.notifier);

      controller.setDatabasePassword('wrong');
      await controller.testConnection();
      controller.setDatabasePassword(PgFixture.password);

      // The second attempt must use what the operator just typed, not what the
      // store kept from the first.
      expect(await controller.testConnection(), isTrue);
    });
  });
}
