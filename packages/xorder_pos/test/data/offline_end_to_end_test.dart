@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_floor_repository.dart';
import 'package:xorder_pos/data/postgres/money_config_codec.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// A business with no internet, from an empty machine to a priced ticket.
///
/// Every other test in this suite checks one seam. This one is the claim the
/// whole phase makes: **a business that cannot reach a dashboard can install
/// a till, build its menu, set its rates, lay out its floor and trade** — and
/// it starts from a database that does not exist yet, exactly as a real
/// install does.
///
/// The last assertion is the one that matters most. Before this work an
/// offline till priced from a built-in 12% / 14% and printed `deviceConfig` on
/// every slip, because nothing but the cloud seeder ever wrote
/// `pos_money_config`. A ticket here must price from the rates the business
/// actually chose.
void main() {
  // Read from the process environment, not a dart-define: every other suite
  // here goes through `PgFixture`, which reads `Platform.environment`. A test
  // that needed its own `--dart-define` would quietly skip under the command
  // the README documents, which is the one way a test can be worse than absent.
  final host = PgFixture.host;
  if (host == null) {
    test('offline end to end (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  final admin = DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: host,
    databasePort: PgFixture.port,
    databaseName: 'xorder_offline_e2e',
    databaseUser: PgFixture.user,
    // The local instance has no certificate, and only a private address is ever
    // allowed to skip verification — the same terms `PgFixture` runs on.
    allowInsecureLan: true,
    tenantSlug: 'islanded',
  );

  /// The owner the bootstrap creates holds every capability through the owner
  /// role; this stands in for them once they have signed in.
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'owner',
    capabilities: {
      PosCapability.catalogManage,
      PosCapability.settingsManage,
    },
  );

  Future<void> drop() async {
    final connection = await Connection.open(
      Endpoint(
        host: admin.databaseHost,
        port: admin.databasePort,
        database: 'postgres',
        username: admin.databaseUser,
        password: PgFixture.password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    try {
      await connection
          .execute('DROP DATABASE IF EXISTS "${admin.databaseName}"');
    } finally {
      await connection.close();
    }
  }

  setUp(drop);
  tearDown(drop);

  test('an islanded business installs, builds a menu and prices a ticket',
      () async {
    final credentials = MutablePosDbCredentials()..set(PgFixture.password);
    final database = PosDatabase(credentials: credentials);
    addTearDown(database.close);
    final bootstrap = LocalBootstrap(database);

    // ── 1. A machine with no database ─────────────────────────────────────
    expect(
      // The superuser's real password. It was '' — which only works on a
      // PostgreSQL that trusts every client, and fails on one that checks.
      await LocalBootstrap.createDatabase(
        admin,
        PgFixture.password,
        admin.databaseName,
      ),
      isTrue,
    );
    expect(await bootstrap.migrate(admin), isNotEmpty);

    final businessId = await bootstrap.seedBusiness(
      admin,
      slug: admin.tenantSlug!,
      name: 'The Islanded Cafe',
    );
    final branchId = await bootstrap.seedBranch(
      admin,
      businessId: businessId,
      name: 'Main',
      code: 'MAIN',
    );
    final roles = await bootstrap.seedSystemRoles(admin, businessId);
    expect(
      await bootstrap.seedOwner(
        admin,
        businessId: businessId,
        branchId: branchId,
        roleId: roles.ids[SystemRoles.ownerCode]!,
        name: 'Amer M.',
        username: 'owner',
        pin: '4321',
      ),
      isA<OwnerCreated>(),
      reason: 'somebody has to be able to sign in',
    );

    final authoring = PostgresCatalogAdminRepository(
      database: database,
      config: admin,
      businessId: businessId,
      branchId: branchId,
    );

    // ── 2. The owner builds the menu ──────────────────────────────────────
    final drinks = await authoring.saveCategory(
      const Category(id: 0, nameEn: 'Drinks', slug: 'drinks'),
      by: owner,
    );
    final coffee = await authoring.saveProduct(
      Product(
        id: 0,
        categoryId: drinks.value!.id,
        nameEn: 'Flat White',
        price: const Money(6000),
      ),
      by: owner,
    );
    expect(coffee.value, isNotNull);

    // ── 3. Sets the rates, which nothing could do before ──────────────────
    await authoring.saveMoneyConfig(
      const TaxConfig(serviceBp: 1000, vatBp: 1400),
      by: owner,
    );

    // ── 4. Lays out the floor ─────────────────────────────────────────────
    expect(
      (await authoring.saveTable(
        const DiningTable(id: 0, label: 'T1', seats: 2),
        by: owner,
      ))
          .value,
      isNotNull,
    );

    // ── 5. What the till now sees ─────────────────────────────────────────
    // Read through the repositories the SALE screen uses, not by inspecting
    // rows: the question is whether a cashier can sell this.
    final catalog =
        await PostgresCatalogRepository(database: database, config: admin)
            .load();
    expect(catalog.categories.single.nameEn, 'Drinks');
    expect(catalog.products.single.nameEn, 'Flat White');

    final floor = await PostgresFloorRepository(
      database: database,
      config: admin,
      businessId: businessId,
      branchId: branchId,
    ).liveFloor();
    expect(floor.single.label, 'T1');

    // ── 6. And a ticket prices from the business's own rates ────────────
    final stored = await database.query(
      admin,
      'SELECT payload FROM pos_money_config WHERE business_id = @r',
      parameters: {'r': businessId},
    );
    final tax = MoneyConfigCodec.toTaxConfig(
      (stored.first[0]! as Map).cast<String, Object?>(),
    );

    expect(tax.serviceBp, 1000);
    expect(tax.vatBp, 1400);
    // The assertion this whole phase exists for: no longer the built-in
    // default the receipt had to disclose.
    expect(
      tax.source,
      TaxSource.server,
      reason: 'the rates are the business\'s own, not the app\'s',
    );

    // The engine is pure, so the ticket can be priced here without a widget
    // tree — which is the point of it being pure.
    final ticket = Ticket(
      id: 'e2e',
      orderType: OrderType.dineIn,
      taxConfig: tax,
      lines: [TicketLine(product: catalog.products.single, quantity: 2)],
    );

    // 2 x 60.00 = 120.00; service 10% = 12.00; VAT 14% of 132.00 = 18.48.
    final totals = ticket.totals;
    expect(totals.subtotal.minor, 12000);
    expect(totals.service.minor, 1200);
    expect(totals.vat.minor, 1848);
    expect(totals.total.minor, 15048);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
