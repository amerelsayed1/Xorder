import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/sql/sql.dart';
import 'package:shared_module/data/sqlite/sqlite_database.dart';
import 'package:shared_module/data/sqlite/sqlite_migrator.dart';
import 'package:shared_module/data/sqlite/sqlite_schema.dart';

/// The cloud till's schema, applied to a real encrypted file
/// (pos-cloud-single-till-sqlite, stage 4).
void main() {
  const config = DeploymentConfig(mode: DeploymentMode.cloud);
  late Directory dir;
  late SqliteDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_sqlite_schema_');
    final key = newSqliteKey();
    db = SqliteDatabase(path: '${dir.path}/till.db', key: () async => key);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a new file takes the whole schema and the triggers', () async {
    final ran = await PosMigrator(db).migrate(config);
    // The generated baseline records every version up to the one it matches,
    // and each later migration then runs as its `sqliteUpgrades` entry.
    expect(ran, [for (final m in posMigrations) m.version]);
    final tables = await db.query(
      config,
      "SELECT count(*) FROM sqlite_master WHERE type = 'table' "
      "AND name LIKE 'pos_%'",
    );
    expect(tables.single[0], greaterThanOrEqualTo(60));
    final triggers = await db.query(
      config,
      "SELECT count(*) FROM sqlite_master WHERE type = 'trigger'",
    );
    expect(triggers.single[0], greaterThan(20));
  });

  test('running it again changes nothing', () async {
    await PosMigrator(db).migrate(config);
    expect(await PosMigrator(db).migrate(config), isEmpty);
  });

  test('every PostgreSQL migration after the baseline has a SQLite '
      'counterpart', () {
    // A new PostgreSQL migration on a table a cloud till keeps must be
    // mirrored in sqliteUpgrades (even as an empty list) or this fails.
    for (final m in posMigrations) {
      if (m.version <= sqliteSchemaMatchesMigration) continue;
      expect(
        sqliteUpgrades.containsKey(m.version),
        isTrue,
        reason: 'migration ${m.version} has no SQLite counterpart',
      );
    }
  });

  group('the rules the triggers keep', () {
    setUp(() => PosMigrator(db).migrate(config));

    test('a new business gets the standard units', () async {
      await db.runTx(config, (tx) async {
        await tx.execute(
          "INSERT INTO pos_businesses (slug, name) VALUES ('cafe-nile', 'Cafe Nile')",
        );
      });
      final business = (await db.query(
        config,
        'SELECT id FROM pos_businesses',
      )).single[0];
      // The new business got the standard units by trigger.
      final units = await db.query(
        config,
        'SELECT count(*) FROM pos_units WHERE business_id = @b',
        parameters: {'b': business},
      );
      expect(units.single[0], 7);
    });

    test('the shapes PostgreSQL checks with patterns are still refused',
        () async {
      await db.runTx(config, (tx) async {
        await tx.execute(
          "INSERT INTO pos_businesses (slug, name) VALUES ('shapes', 'Shapes')",
        );
      });
      Future<void> refused(String sql) => expectLater(
        db.runTx(config, (tx) => tx.execute(sql)),
        throwsA(isA<PosDbException>()),
      );
      // ^[a-z][a-z0-9_]{0,15}$ and ^[A-Z0-9]{1,6}$
      await refused("UPDATE pos_units SET code = 'Not A Code' WHERE code = 'kg'");
      await refused(
        "UPDATE pos_units SET eta_unit_type = 'TOOLONG' WHERE code = 'kg'",
      );
      // A good one still goes through.
      await db.runTx(
        config,
        (tx) => tx.execute(
          "UPDATE pos_units SET code = 'kilo_1' WHERE code = 'kg'",
        ),
      );
    });

    test('a refund cannot be written against an order that took nothing',
        () async {
      await expectLater(
        db.runTx(config, (tx) async {
          await tx.execute(
            Sql.named(
              'INSERT INTO pos_refunds (order_id, business_id, branch_id) '
              'VALUES (999, 1, 1)',
            ),
          );
        }),
        throwsA(isA<PosDbException>()),
      );
    });
  });
}
