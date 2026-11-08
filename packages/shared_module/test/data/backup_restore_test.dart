@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/backup/backup_service.dart';
import 'package:shared_module/data/backup/pg_archive.dart';
import 'package:shared_module/data/backup/pg_tools.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_admin_repositories.dart';
import 'package:shared_module/data/postgres/postgres_backup_repository.dart';
import 'package:shared_module/domain/models/backup.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// Ship blocker 11 — backup and restore, against a real PostgreSQL.
///
/// **A dump nobody has restored is not a backup, so this suite restores one.**
/// It writes rows, takes a copy, changes the rows, puts the copy back and
/// asserts the originals are there — which is the only test that would have
/// caught a `pg_restore` invocation that ran cleanly and replaced nothing.
/// Mocking `Process.run` would have proved that we call a binary, which is not
/// the claim anybody cares about.
///
/// The guards get the same treatment. Restoring mid-service is unrecoverable
/// and the person doing it does not find out until the drawer fails to
/// reconcile, so the refusal is asserted through the service **and** the rows it
/// reads are put there in raw SQL, going round every Dart path that might be
/// keeping the invariant by accident.
void main() {
  if (PgFixture.host == null) {
    test('backup and restore (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late BackupService service;
  late PostgresBackupRepository backups;
  late PostgresAuditRepository audit;
  late Directory folder;
  late int businessId;
  late int branchId;
  late int staffId;
  PgToolset? tools;

  const terminal = '44444444-4444-4444-8444-444444444444';

  /// A well-shaped checksum for the rows this suite writes by hand. The column
  /// has a CHECK on the shape, so an obviously fake one still has to look like
  /// a SHA-256.
  const sixtyFourHex =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  const owner = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'owner',
      nameEn: 'Owner',
      // The whole point of `Authorization.check` over `capabilities.contains`:
      // this is held through the role and not as a direct grant.
      capabilities: {PosCapability.backupManage, PosCapability.staffManage},
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate, PosCapability.dayClose},
    ),
  );

  /// The fixture's own account, as both the reader and the restorer. The
  /// accounts a real install uses — a `pg_read_all_data` reader and a database
  /// owner that is not a superuser — are `pg_archive_restore_test.dart`'s job.
  BackupConnection connectionTo(DeploymentConfig config) => BackupConnection(
    host: PgFixture.host!,
    port: PgFixture.port,
    database: config.databaseName,
    user: PgFixture.user,
    password: PgFixture.password,
    verifyTls: false,
  );

  BackupService serviceWith({
    DeploymentConfig? config,
    PgToolset? toolset,
    String? directory,
    int keep = 14,
  }) => BackupService(
    database: db,
    config: config ?? pg.config,
    businessId: businessId,
    branchId: branchId,
    directory: directory ?? folder.path,
    backups: backups,
    audit: audit,
    toolset: toolset ?? tools,
    reader: connectionTo(config ?? pg.config),
    restorer: connectionTo(config ?? pg.config),
    keep: keep,
    quiesce: () => db.close(),
  );

  Future<int> openDay({bool closed = false}) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_business_days (business_id, branch_id, business_date, '
      '  opened_by, closed_at, closed_by) '
      'VALUES (@r, @b, @d::date, @by, '
      '  CASE WHEN @closed::boolean THEN now() ELSE NULL END, '
      // `pos_business_days_closed_is_complete`: a closing time with nobody's
      // name on it is not a close anybody can be asked about.
      '  CASE WHEN @closed::boolean THEN @by::bigint ELSE NULL END) RETURNING id',
      parameters: {
        'r': businessId,
        'b': branchId,
        'd': '2026-09-09',
        'by': staffId,
        'closed': closed,
      },
    );
    return rows.first[0]! as int;
  }

  /// A shift row, open or closed.
  ///
  /// The whole close has to be written at once: `pos_shifts_closed_is_complete`
  /// refuses a closing time with no count, because half a cash-up is not a
  /// state anybody can act on.
  Future<int> openShift({bool closed = false}) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_shifts (business_id, branch_id, terminal_id, '
      '  opened_by, opening_float_minor, closed_at, closed_by, '
      '  counted_cash_minor, expected_cash_minor, variance_minor) '
      'VALUES (@r, @b, @t::uuid, @by, 20000, '
      '  CASE WHEN @closed::boolean THEN now() ELSE NULL END, '
      '  CASE WHEN @closed::boolean THEN @by::bigint ELSE NULL END, '
      '  CASE WHEN @closed::boolean THEN 20000 ELSE NULL END, '
      '  CASE WHEN @closed::boolean THEN 20000 ELSE NULL END, '
      '  CASE WHEN @closed::boolean THEN 0 ELSE NULL END) RETURNING id',
      parameters: {
        'r': businessId,
        'b': branchId,
        't': terminal,
        'by': staffId,
        'closed': closed,
      },
    );
    return rows.first[0]! as int;
  }

  Future<void> order(String invoice, {int total = 1000}) => db.query(
    pg.config,
    'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
    '  terminal_id, invoice_number, order_type, currency, exponent, '
    '  subtotal_minor, service_minor, vat_minor, total_minor, occurred_at) '
    "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @invoice, 'dine_in', 'EGP', "
    '  2, @total, 0, 0, @total, now())',
    parameters: {
      'r': businessId,
      'b': branchId,
      't': terminal,
      'invoice': invoice,
      'total': total,
    },
  );

  /// A sale still owed to the platform — an order and its `pos_outbox` row.
  ///
  /// Raw SQL, like the shifts and days above, so the guard is reading the
  /// queue itself and not anything the drain keeps in memory about it.
  Future<void> owedSale(
    String invoice, {
    bool held = false,
    bool delivered = false,
  }) async {
    await order(invoice);
    await db.query(
      pg.config,
      'INSERT INTO pos_outbox (order_id, client_transaction_id, business_id, '
      '  branch_id, delivered_at, quarantined_at, quarantine_code) '
      'SELECT id, client_transaction_id, business_id, branch_id, '
      '  CASE WHEN @delivered::boolean THEN now() ELSE NULL END, '
      '  CASE WHEN @held::boolean THEN now() ELSE NULL END, '
      "  CASE WHEN @held::boolean THEN 'MENU_ITEM_NOT_FOUND' ELSE NULL END "
      'FROM pos_orders WHERE business_id = @r AND invoice_number = @invoice',
      parameters: {
        'r': businessId,
        'invoice': invoice,
        'held': held,
        'delivered': delivered,
      },
    );
  }

  /// A cash movement still owed to the platform, on the second queue. A
  /// guard that read only `pos_outbox` would miss every refund and shift
  /// close the till had not sent.
  Future<void> owedEvent({bool held = false}) => db.query(
    pg.config,
    'INSERT INTO pos_sync_outbox (business_id, branch_id, event_type, '
    '  source_id, client_transaction_id, quarantined_at, quarantine_code) '
    "VALUES (@r, @b, 'cash_movement', 1, gen_random_uuid(), "
    '  CASE WHEN @held::boolean THEN now() ELSE NULL END, '
    "  CASE WHEN @held::boolean THEN 'REJECTED' ELSE NULL END)",
    parameters: {'r': businessId, 'b': branchId, 'held': held},
  );

  /// The safety copies a restore has taken, in this suite's folder.
  List<File> safetyCopies() => [
    for (final entry in folder.listSync())
      if (entry is File &&
          entry.uri.pathSegments.last.startsWith(
            BackupService.preRestorePrefix,
          ) &&
          entry.path.endsWith('.dump'))
        entry,
  ];

  /// This business's invoices, in order.
  ///
  /// Scoped, because a restore puts the WHOLE database back — including the
  /// rows earlier tests in this suite left behind under their own business
  /// ids. `pos_orders` has no foreign key to `pos_businesses`, deliberately,
  /// so `DELETE FROM pos_businesses` in setUp does not take them with it.
  Future<List<String>> invoices() async {
    final rows = await db.query(
      pg.config,
      'SELECT invoice_number FROM pos_orders WHERE business_id = @r '
      'ORDER BY invoice_number',
      parameters: {'r': businessId},
    );
    return [for (final row in rows) row[0]! as String];
  }

  setUpAll(() async => tools = await PgTools.locate());

  setUp(() async {
    pg = await PgFixture.open('backup_restore');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    // `pos_businesses` goes; `pos_audit_events` cannot, because the ledger
    // refuses DELETE and TRUNCATE from every connection — which is the whole
    // point of it. Each run therefore takes a NEW business id, and every
    // repository here is scoped to it, so the ledger assertions below see only
    // this test's rows.
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_businesses (slug, name) "
              "VALUES ('bk', 'Backup Grill') RETURNING id",
            )).first[0]!
            as int;
    branchId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_branches (business_id, code, name) "
              "VALUES (@r, 'BK1', 'Main') RETURNING id",
              parameters: {'r': businessId},
            )).first[0]!
            as int;
    staffId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_users (business_id, branch_id, name, '
              "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Amer M.', "
              "  'amer', 'salt', 'hash') RETURNING id",
              parameters: {'r': businessId, 'b': branchId},
            )).first[0]!
            as int;
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1') ON CONFLICT (id) DO NOTHING",
      parameters: {'t': terminal, 'r': businessId, 'b': branchId},
    );

    backups = PostgresBackupRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
      terminalId: terminal,
    );
    audit = PostgresAuditRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
      terminalId: terminal,
    );

    folder = Directory.systemTemp.createTempSync('xorder-backup');
    service = serviceWith();
  });

  tearDown(() async {
    await pg.close();
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  group('finding the tools', () {
    test('pg_dump and pg_restore are on this machine', () {
      // Not an assertion about the product — an assertion about the box this
      // suite is running on, so that a failure below reads as "the backup is
      // broken" rather than "PostgreSQL is not installed".
      expect(
        tools,
        isNotNull,
        reason: 'install the PostgreSQL client tools to run this suite',
      );
      expect(tools!.majorVersion, isNotNull);
    });

    test('the search list names real directories, not just PATH', () {
      expect(PgTools.searchPath(), isNotEmpty);
    });
  });

  group('taking one', () {
    test('a copy is written, checksummed and verified', () async {
      final result = await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');

      final record = result.value!;
      expect(
        record.outcome,
        BackupOutcome.verified,
        reason: record.detail ?? '',
      );
      expect(record.failure, isNull);
      expect(File(record.filePath).existsSync(), isTrue);
      expect(record.sizeBytes, greaterThan(0));
      // 64 lower-case hex characters, which is also what the CHECK constraint
      // insists on — so a checksum that came back in another shape would have
      // failed the INSERT rather than reaching here.
      expect(record.checksum, matches(RegExp(r'^[0-9a-f]{64}$')));
      // Every table the migrations create, near enough. The point is that the
      // dump is the whole schema and not a hand-picked subset.
      expect(record.tablesFound, greaterThan(30));
    });

    test('the tables it verifies are the ones a business cannot trade '
        'without', () async {
      final record = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;

      final listed = await Process.run(tools!.pgRestore, [
        '--list',
        record.filePath,
      ]);
      final tables = BackupService.tablesIn('${listed.stdout}');
      for (final essential in BackupService.essentialTables) {
        expect(tables, contains(essential));
      }
    });

    test('it is recorded, and the ledger says who took it', () async {
      await service.take(by: owner, trigger: BackupTrigger.manual);

      final stored = await backups.recent();
      expect(stored, hasLength(1));
      expect(stored.single.takenByName, 'Amer M.');
      expect(stored.single.trigger, BackupTrigger.manual);

      final ledger = await audit.recent(
        entityType: AuditAction.entityBackup,
      );
      expect(ledger.single.action, AuditAction.backupTaken);
      expect(ledger.single.after!['outcome'], 'verified');
    });

    test('a manual copy needs backup.manage', () async {
      final result = await service.take(
        by: cashier,
        trigger: BackupTrigger.manual,
      );

      expect(result.succeeded, isFalse);
      expect(result.refusal, isA<NotPermitted>());
      expect(await backups.recent(), isEmpty, reason: 'nothing was attempted');
    });

    test('the automatic copy at day close does not', () async {
      // Deliberate, and the reason is in `BackupService.take`: `backup.manage`
      // is the owner's alone and `day.close` is every manager's, so demanding
      // the first would mean the only nights with a copy are the nights the
      // owner happened to be closing.
      final result = await service.take(
        by: cashier,
        trigger: BackupTrigger.dayClose,
      );

      expect(result.succeeded, isTrue);
      expect(result.value!.outcome, BackupOutcome.verified);
      expect((await backups.recent()).single.trigger, BackupTrigger.dayClose);
    });

    test('a dump that will not run is recorded as a failure, not as silence',
        () async {
      final broken = serviceWith(
        config: pg.config.copyWith(databaseName: 'xorder_pos_no_such_database'),
      );

      final record = (await broken.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;

      expect(record.outcome, BackupOutcome.failed);
      expect(record.failure, BackupFailure.dumpRefused);
      // PostgreSQL's own words, kept so a technician has something to act on.
      expect(record.detail, contains('does not exist'));
      // And nothing left on disk that looks like a backup.
      expect(File(record.filePath).existsSync(), isFalse);
      expect((await backups.recent()).single.outcome, BackupOutcome.failed);
    });

    test('a file that cannot be read back is not a backup', () async {
      // `pg_dump` does not understand `--list` and exits non-zero, which makes
      // it a portable stand-in for a `pg_restore` that cannot read the archive
      // — the real-world case being a dump that ran out of disk halfway and
      // left a plausible-looking file of plausible-looking size.
      final blind = serviceWith(
        toolset: PgToolset(
          pgDump: tools!.pgDump,
          pgRestore: tools!.pgDump,
          version: tools!.version,
        ),
      );

      final record = (await blind.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;

      expect(record.outcome, BackupOutcome.unverified);
      expect(record.failure, BackupFailure.archiveUnreadable);
      expect(
        record.isRestorable,
        isFalse,
        reason: 'the list must not offer a restore from this',
      );
      // How big it was is recorded; the file itself is not kept. A readable
      // name and a plausible size on a file nothing can restore from is exactly
      // what somebody reaches for in a panic.
      expect(record.sizeBytes, greaterThan(0));
      expect(File(record.filePath).existsSync(), isFalse);
      expect(File('${record.filePath}.part').existsSync(), isFalse);
    });

    test('with no tools at all it says so rather than doing nothing', () async {
      final bare = BackupService(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branchId,
        directory: folder.path,
        backups: backups,
        audit: audit,
      );

      final record = (await bare.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;

      expect(record.outcome, BackupOutcome.failed);
      expect(record.failure, BackupFailure.toolsMissing);
    });
  });

  group('the record of it', () {
    Future<void> raw(String sql, [Map<String, Object?> parameters = const {}]) =>
        db.query(pg.config, sql, parameters: parameters);

    Future<void> insertRaw({
      String outcome = 'verified',
      String file = '/tmp/one.dump',
      String? checksum = sixtyFourHex,
      int size = 10,
      int tables = 40,
      String? failure,
    }) => raw(
      'INSERT INTO pos_backups (business_id, taken_by_name, trigger_kind, '
      '  outcome, file_path, size_bytes, checksum, tables_found, failure) '
      "VALUES (@r, 'Amer M.', 'manual', @outcome, @file, @size, @checksum, "
      '  @tables, @failure)',
      {
        'r': businessId,
        'outcome': outcome,
        'file': file,
        'size': size,
        'checksum': checksum,
        'tables': tables,
        'failure': failure,
      },
    );

    test('a verified row with nothing behind it is refused', () async {
      // Straight at the database, going round the service entirely. Without
      // this the row would read on screen as the backup that saves the
      // business, and there would be no file.
      await expectLater(
        insertRaw(checksum: null, size: 0, tables: 0),
        throwsA(anything),
      );
    });

    test('a failure with no reason, and a success with one, are both refused',
        () async {
      await expectLater(
        insertRaw(outcome: 'failed', failure: null, checksum: null, size: 0),
        throwsA(anything),
      );
      await expectLater(
        insertRaw(failure: 'dump_refused'),
        throwsA(anything),
      );
    });

    test('two rows cannot claim the same file', () async {
      await insertRaw(file: '/tmp/same.dump');
      await expectLater(insertRaw(file: '/tmp/same.dump'), throwsA(anything));
    });

    test('but two failures against the same unwritable path can', () async {
      // Nothing was written either time, so there is no file for the rows to
      // disagree about.
      await insertRaw(
        outcome: 'failed',
        file: '/nope/x.dump',
        failure: 'destination_unwritable',
        checksum: null,
        size: 0,
        tables: 0,
      );
      await insertRaw(
        outcome: 'failed',
        file: '/nope/x.dump',
        failure: 'destination_unwritable',
        checksum: null,
        size: 0,
        tables: 0,
      );
      expect(await backups.recent(), hasLength(2));
    });

    test('it is append-only, even from an administrator connection', () async {
      // The human rule this protects: a row reading "last night could not be
      // verified" is uncomfortable, and the shortest way to make it go away is
      // one UPDATE — after which the business believes it has a copy it does
      // not have.
      await insertRaw(outcome: 'unverified', failure: 'archive_unreadable');

      await expectLater(
        raw("UPDATE pos_backups SET outcome = 'verified'"),
        throwsA(anything),
      );
      await expectLater(raw('DELETE FROM pos_backups'), throwsA(anything));
      await expectLater(raw('TRUNCATE pos_backups'), throwsA(anything));

      expect((await backups.recent()).single.outcome, BackupOutcome.unverified);
    });
  });

  group('what a restore would cost', () {
    test('it counts the orders taken since, and what they came to', () async {
      final record = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;

      await order('INV-1', total: 12500);
      await order('INV-2', total: 4000);

      final check = await service.checkRestore(record);
      expect(check.ordersSince, 2);
      // Minor units throughout — 165.00, not 165.0 and never a double.
      expect(check.valueSince.minor, 16500);
      expect(check.lastOrderAt, isNotNull);
      expect(check.isPermitted, isTrue);
    });

    test('orders taken before it are not counted', () async {
      await order('INV-OLD');
      final record = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;

      final check = await service.checkRestore(record);
      expect(check.ordersSince, 0);
      expect(check.valueSince.minor, 0);
    });
  });

  group('the restore guards', () {
    late BackupRecord copy;

    setUp(() async {
      copy = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
    });

    test('an open shift blocks it', () async {
      // Written in raw SQL, so the guard is reading the database rather than
      // anything Dart put in front of it.
      await openShift();

      final check = await service.checkRestore(copy);
      expect(check.isPermitted, isFalse);
      expect(
        check.blockers.map((b) => b.kind),
        contains(RestoreBlockerKind.openShift),
      );

      // And the service refuses even when the caller ignores the check —
      // restoring mid-service is unrecoverable, and nobody finds out until the
      // drawer fails to reconcile hours later.
      await expectLater(
        service.restore(copy, by: owner),
        throwsA(isA<RestoreRefused>()),
      );
    });

    test('an open business day blocks it', () async {
      await openDay();

      final check = await service.checkRestore(copy);
      expect(check.isPermitted, isFalse);
      expect(
        check.blockers.single.kind,
        RestoreBlockerKind.openBusinessDay,
      );
      await expectLater(
        service.restore(copy, by: owner),
        throwsA(isA<RestoreRefused>()),
      );
    });

    test('a closed shift and a closed day do not', () async {
      await openShift(closed: true);
      await openDay(closed: true);

      expect((await service.checkRestore(copy)).isPermitted, isTrue);
    });

    test('on a cloud till, a sale not yet sent blocks it', () async {
      // Scenario D3: an older file put back over an evening that never went
      // up. The rows that would have carried it are among the rows the restore
      // drops, and the platform never hears about that money.
      final cloud = serviceWith(
        config: pg.config.copyWith(mode: DeploymentMode.cloud),
      );
      await owedSale('INV-UNSENT');
      await owedEvent();

      final check = await cloud.checkRestore(copy);
      expect(check.isPermitted, isFalse);
      // Both queues, in one count: a refund that never went up is as lost as
      // a sale.
      expect(check.pendingSync, 2);
      expect(check.blockers.single.kind, RestoreBlockerKind.pendingSync);
      expect(check.blockers.single.count, 2);

      await expectLater(
        cloud.restore(copy, by: owner),
        throwsA(isA<RestoreRefused>()),
      );
      // Refused before the safety copy, not after it: a restore that was never
      // going to run should not cost a full dump to find that out.
      expect(safetyCopies(), isEmpty);
      expect(await invoices(), ['INV-UNSENT']);
    });

    test('offline, the same queue is a warning and not a blocker', () async {
      // An offline till never drains, so a row here is a leftover from a past
      // life as a cloud till — refusing on it would be a lock-out nothing on
      // the machine could ever clear.
      await owedSale('INV-LEFTOVER');

      final check = await service.checkRestore(copy);
      expect(check.isPermitted, isTrue);
      expect(check.blockers, isEmpty);
      expect(check.pendingSync, 1, reason: 'said, even though it does not stop');
    });

    test('a row the platform refused warns in both modes and blocks in neither',
        () async {
      await owedSale('INV-REFUSED', held: true);
      await owedEvent(held: true);
      // Delivered is neither pending nor held — it is already the platform's.
      await owedSale('INV-SENT', delivered: true);

      final cloud = serviceWith(
        config: pg.config.copyWith(mode: DeploymentMode.cloud),
      );
      for (final guard in [service, cloud]) {
        final check = await guard.checkRestore(copy);
        expect(check.isPermitted, isTrue, reason: guard.config.mode.name);
        expect(check.heldSync, 2, reason: guard.config.mode.name);
        expect(check.pendingSync, 0, reason: guard.config.mode.name);
      }
    });

    test('a copy that failed verification cannot be restored from', () async {
      // The pane never offers the button on such a row; this is the second
      // line. Restoring from a file `pg_restore` already said it could not read
      // would leave the business with neither the old database nor a new one.
      final unreadable = BackupRecord(
        takenAt: copy.takenAt,
        takenByName: 'Amer M.',
        trigger: BackupTrigger.manual,
        outcome: BackupOutcome.unverified,
        filePath: copy.filePath,
        sizeBytes: copy.sizeBytes,
        checksum: copy.checksum,
        failure: BackupFailure.archiveUnreadable,
      );

      await expectLater(
        service.restore(unreadable, by: owner),
        throwsA(isA<StateError>()),
      );
    });

    test('nor one whose file has been replaced since it was verified',
        () async {
      // The checksum's whole job. A folder somebody copied to a USB stick
      // halfway, or a file overwritten by another install, is a different file
      // from the one that was verified.
      File(copy.filePath).writeAsBytesSync(const [1, 2, 3], flush: true);

      await expectLater(
        service.restore(copy, by: owner),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not the one this record describes'),
          ),
        ),
      );
    });

    test('and a restore needs backup.manage whatever the state', () async {
      final result = await service.restore(copy, by: cashier);
      expect(result.succeeded, isFalse);
      expect(result.refusal, isA<NotPermitted>());
    });
  });

  group('putting one back', () {
    test('the rows that were there when the copy was taken are there again',
        () async {
      await order('INV-BEFORE');
      final copy = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
      expect(copy.outcome, BackupOutcome.verified, reason: copy.detail ?? '');

      // The evening that is about to be thrown away.
      await order('INV-AFTER-1');
      await order('INV-AFTER-2');
      await db.query(
        pg.config,
        "UPDATE pos_businesses SET name = 'Renamed After The Backup' "
        'WHERE id = @r',
        parameters: {'r': businessId},
      );
      expect(await invoices(), ['INV-AFTER-1', 'INV-AFTER-2', 'INV-BEFORE']);

      final check = await service.checkRestore(copy);
      expect(check.ordersSince, 2);

      final result = await service.restore(copy, by: owner);
      expect(result.succeeded, isTrue, reason: '${result.refusal}');

      // The whole claim: the rows are back, and the two that were not in the
      // copy are gone.
      expect(await invoices(), ['INV-BEFORE']);
      final name = await db.query(
        pg.config,
        'SELECT name FROM pos_businesses WHERE id = @r',
        parameters: {'r': businessId},
      );
      expect(name.first[0], 'Backup Grill');
    });

    test('the ledger records it — in the database that replaced this one',
        () async {
      final copy = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
      await order('INV-LOST');

      await service.restore(copy, by: owner);

      // Written AFTER the restore, deliberately: a row written before would be
      // inside the rows `pg_restore --clean` drops, and the only trace of the
      // most destructive act in the product would be destroyed by the act
      // itself. See `BackupService.restore` for what that costs.
      final ledger = await audit.recent(entityType: AuditAction.entityBackup);
      final restored = ledger.firstWhere(
        (entry) => entry.action == AuditAction.backupRestored,
      );
      expect(restored.actorName, 'Amer M.');
      expect(restored.before!['orders_discarded'], 1);
      expect(restored.after!['restored_from'], copy.filePath);

      // And the `backup.taken` row that the copy itself wrote is gone, because
      // it was written after the dump was read. That is not a bug — it is the
      // shape of the problem, and the file on disk is what still answers "what
      // did this database used to be".
      expect(
        ledger.where((e) => e.action == AuditAction.backupTaken),
        isEmpty,
      );
    });
  });

  group('the copy a restore takes first', () {
    test('it is on disk afterwards, and putting it back undoes the restore',
        () async {
      await order('INV-BEFORE');
      final copy = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
      await order('INV-AFTER');

      final result = await service.restore(copy, by: owner);
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(await invoices(), ['INV-BEFORE']);

      final kept = safetyCopies();
      expect(kept, hasLength(1));

      // The ledger row is the one record of it that survives: the
      // `pos_backups` row the copy wrote went with the database it described.
      final ledger = await audit.recent(entityType: AuditAction.entityBackup);
      final restored = ledger.firstWhere(
        (entry) => entry.action == AuditAction.backupRestored,
      );
      expect(restored.after!['pre_restore_snapshot'], kept.single.path);

      // And it is a way back, not a file with a reassuring name. Named for
      // the second it was taken in, so the next safety copy must not land in
      // the same one and overwrite it.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final undo = await service.describeFile(kept.single, by: owner);
      expect((await service.restore(undo, by: owner)).succeeded, isTrue);
      expect(await invoices(), ['INV-AFTER', 'INV-BEFORE']);
    });

    test('when it cannot be taken, nothing is restored', () async {
      await order('INV-BEFORE');
      final copy = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
      await order('INV-AFTER');

      // A folder that cannot be created, because a file is in the way. Not a
      // permissions trick: those do nothing to a suite running as root.
      final inTheWay = File('${folder.path}/in-the-way')..writeAsStringSync('');
      final cornered = serviceWith(directory: '${inTheWay.path}/backups');

      await expectLater(
        cornered.restore(copy, by: owner),
        throwsA(
          isA<RestoreSnapshotFailed>().having(
            (e) => e.attempt.failure,
            'failure',
            BackupFailure.destinationUnwritable,
          ),
        ),
      );

      // The whole claim: the evening is still here.
      expect(await invoices(), ['INV-AFTER', 'INV-BEFORE']);
      // And the attempt is on the record, in the database that was kept.
      final newest = (await backups.recent()).first;
      expect(newest.outcome, BackupOutcome.failed);
      expect(newest.failure, BackupFailure.destinationUnwritable);
      expect(
        (await audit.recent(entityType: AuditAction.entityBackup))
            .where((e) => e.action == AuditAction.backupRestored),
        isEmpty,
      );
    });
  });

  group('beyond this machine', () {
    test('a verified copy goes to a USB drive, and the copy is the same file',
        () async {
      final copy = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
      final drive = Directory.systemTemp.createTempSync('xorder-usb');
      addTearDown(() => drive.deleteSync(recursive: true));

      final copied = await service.copyTo(copy, drive.path);

      expect(copied.existsSync(), isTrue);
      expect(
        (await service.describeFile(copied, by: owner)).checksum,
        copy.checksum,
      );
      expect(
        drive.listSync().map((f) => f.path).where((p) => p.endsWith('.part')),
        isEmpty,
      );
    });

    test('only a backup is worth copying', () async {
      final drive = Directory.systemTemp.createTempSync('xorder-usb');
      addTearDown(() => drive.deleteSync(recursive: true));

      await expectLater(
        service.copyTo(
          BackupRecord(
            takenAt: DateTime.now(),
            takenByName: 'Amer M.',
            trigger: BackupTrigger.manual,
            outcome: BackupOutcome.unverified,
            filePath: '${folder.path}/nothing.dump',
            failure: BackupFailure.archiveUnreadable,
          ),
          drive.path,
        ),
        throwsA(isA<StateError>()),
      );
      expect(drive.listSync(), isEmpty);
    });

    test('a copy brought back on the drive restores, with no record of it here',
        () async {
      // The disaster case: the database that recorded this copy is the one
      // that is gone, so the file has to stand on its own.
      await order('INV-BEFORE');
      // A file only knows the second it was taken in, and is read as the START
      // of that second — so an order earlier in the same second would be
      // counted as lost. Over-counting is the safe direction for that warning;
      // the pause keeps this test about the restore rather than the rounding.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final copy = (await service.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
      final drive = Directory.systemTemp.createTempSync('xorder-usb');
      addTearDown(() => drive.deleteSync(recursive: true));
      final onTheDrive = await service.copyTo(copy, drive.path);
      await order('INV-AFTER');

      final described = await service.describeFile(onTheDrive, by: owner);
      expect(
        described.takenAt.difference(copy.takenAt).inSeconds.abs(),
        lessThan(1),
        reason: 'when it was taken is read off its name',
      );
      expect((await service.checkRestore(described)).ordersSince, 1);

      final result = await service.restore(described, by: owner);

      expect(result.succeeded, isTrue);
      expect(await invoices(), ['INV-BEFORE']);
    });

    test('the folder keeps the newest copies, not every copy ever taken',
        () async {
      final kept = serviceWith(keep: 1);
      final first = (await kept.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;
      // Named for the second they were taken in.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final second = (await kept.take(
        by: owner,
        trigger: BackupTrigger.manual,
      )).value!;

      expect(File(first.filePath).existsSync(), isFalse);
      expect(File(second.filePath).existsSync(), isTrue);
      expect(
        folder.listSync().where((f) => f.path.endsWith('.dump')),
        hasLength(1),
      );
    });
  });
}
