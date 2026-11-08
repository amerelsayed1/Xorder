import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/backup/backup_service.dart';
import 'package:shared_module/data/config/secret_store.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/postgres_admin_repositories.dart';
import 'package:shared_module/data/postgres/postgres_backup_repository.dart';
import 'package:shared_module/domain/models/backup.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/data/sqlite/sqlite_database.dart';
import 'package:xorder_pos_cloud/data/local/cloud_datastore.dart';
import 'package:xorder_pos_test_support/fakes.dart' show InMemorySecretStore;

/// A cloud till keeps its data in an encrypted SQLite file
/// (pos-cloud-single-till-sqlite, stage 5). No PostgreSQL is involved.
void main() {
  const config = DeploymentConfig(mode: DeploymentMode.cloud);
  late Directory dir;
  late InMemorySecretStore secrets;
  late KeyedSecretStore keys;
  late SqliteDatabase database;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_cloud_store_');
    secrets = InMemorySecretStore();
    keys = KeyedSecretStore(secrets, 'pos_cloud_data_key');
    database = SqliteDatabase(
      path: '${dir.path}/$cloudDataFileName',
      key: keys.read,
    );
  });
  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  group('setup prepares the file', () {
    test('a first run makes a key and the whole schema; a second changes '
        'nothing', () async {
      final store = CloudDatastore(database: database, keys: keys);

      final first = await store.prepare(config);
      expect(first.created, isTrue);
      expect(first.migrations, greaterThan(60));
      expect(await keys.read(), matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(File('${dir.path}/$cloudDataFileName').existsSync(), isTrue);

      final again = await store.prepare(config);
      expect(again.created, isFalse);
      expect(again.migrations, 0);
    });

    test('the defaults a cloud till needs are seeded into the file', () async {
      await CloudDatastore(database: database, keys: keys).prepare(config);
      final business = await LocalBootstrap(
        database,
      ).seedBusiness(config, slug: 'cafe-nile', name: 'Cafe Nile');

      await cloudDefaultsSeeder(database)(config, '', business);

      final reasons = await database.query(
        config,
        'SELECT count(*) FROM pos_reason_codes WHERE business_id = @b',
        parameters: {'b': business},
      );
      expect(reasons.single[0], greaterThan(0));
      final orderTypes = await database.query(
        config,
        'SELECT count(*) FROM pos_order_types WHERE business_id = @b',
        parameters: {'b': business},
      );
      expect(orderTypes.single[0], greaterThan(0));
    });
  });

  test('the day-close backup is a verified, encrypted copy of the file',
      () async {
    await CloudDatastore(database: database, keys: keys).prepare(config);
    final boot = LocalBootstrap(database);
    final business = await boot.seedBusiness(
      config,
      slug: 'cafe-nile',
      name: 'Cafe Nile',
    );
    final branch = await boot.seedBranch(
      config,
      businessId: business,
      name: 'Maadi',
      code: 'MAADI',
    );
    final roles = await boot.seedSystemRoles(config, business);
    await boot.seedOwner(
      config,
      businessId: business,
      branchId: branch,
      roleId: roles.ids['owner']!,
      name: 'Nour',
      username: 'nour',
      pin: '4829',
    );
    final ownerId = (await database.query(
      config,
      "SELECT id FROM pos_users WHERE username = 'nour'",
    )).single[0]! as int;

    final backups = '${dir.path}/backups';
    final service = BackupService(
      database: database,
      config: config.copyWith(databaseName: 'xorder_pos_cloud'),
      businessId: business,
      branchId: branch,
      directory: backups,
      backups: PostgresBackupRepository(
        database: database,
        config: config,
        businessId: business,
        branchId: branch,
      ),
      audit: PostgresAuditRepository(
        database: database,
        config: config,
        businessId: business,
        branchId: branch,
      ),
      snapshot: cloudSnapshot(database, keys),
    );

    final record = await service._takeForTest(
      PosStaff(id: ownerId, name: 'Nour'),
    );
    expect(record.outcome, BackupOutcome.verified, reason: '${record.detail}');
    expect(record.filePath, endsWith('.db'));
    expect(File(record.filePath).existsSync(), isTrue);
    // Encrypted like the original: not a plain SQLite file.
    final header = await File(record.filePath).openRead(0, 15).first;
    expect(String.fromCharCodes(header), isNot('SQLite format 3'));
  });
}

extension on BackupService {
  /// A day-close copy, as `DayCloseDialog` takes one.
  Future<BackupRecord> _takeForTest(PosStaff by) async {
    final result = await take(by: by, trigger: BackupTrigger.dayClose);
    return result.value!;
  }
}
