@Tags(['integration'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/services/syncing_orders_repository.dart';
import 'package:xorder_pos_cloud/wiring.dart';
import 'package:xorder_pos_test_support/pg_fixture.dart';

/// The cloud app's half of `postgres_wiring_test.dart` (pos-split-apps stage 3).
///
/// The shared package binds no sync loop, so there a cloud terminal's orders
/// repository is bare PostgreSQL. The cloud app binds one through
/// [cloudOverrides], and every settled sale must then poke the drain: the
/// repository comes back wrapped in [SyncingOrdersRepository]. Same database,
/// same write — PostgreSQL first, an outbox claim in the same transaction —
/// with "sold" and "synced" seconds apart instead of a timer apart.
void main() {
  if (PgFixture.host == null) {
    test('cloud orders wiring (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase database;
  late DeploymentConfig branchConfig;

  setUp(() async {
    pg = await PgFixture.open('cloud_wiring');
    database = pg.database;
    branchConfig = pg.config;
    await PosMigrator(database).migrate(branchConfig);
    await pg.truncate();
  });

  tearDown(() => pg.close());

  test('a cloud till wraps its orders so every sale pokes the drain', () {
    final container = ProviderContainer(
      overrides: [
        appModeProvider.overrideWithValue(DeploymentMode.cloud),
        // E-receipts off, so nothing sits over the sync kicker.
        etaFilingEnabledProvider.overrideWithValue(false),
        posDatabaseProvider.overrideWithValue(database),
        posDbCredentialsProvider
            .overrideWithValue(InMemoryPosDbCredentials(PgFixture.password)),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        ...cloudOverrides(),
      ],
    );
    addTearDown(container.dispose);

    container.read(deploymentProvider.notifier).apply(
          branchConfig.copyWith(
            mode: DeploymentMode.cloud,
            baseUrl: 'https://xorder.io',
            // Nobody presses "sync now" in a test, and nothing should start a
            // pass on its own against a platform that is not there.
            syncPolicy: SyncPolicy.manual,
          ),
        );
    container.read(terminalProfileProvider.notifier).apply(const TerminalProfile(
          businessId: 1,
          branchId: 13,
          branchCode: 'MAADI',
          branchName: 'Maadi',
          terminalName: 'Counter 1',
          terminalId: '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
          provisioned: true,
        ));

    expect(container.read(cloudSyncProvider), isNotNull,
        reason: 'the cloud app binds a sync loop for a provisioned cloud till');
    expect(
      container.read(ordersRepositoryProvider),
      isA<SyncingOrdersRepository>(),
    );
  });
}
