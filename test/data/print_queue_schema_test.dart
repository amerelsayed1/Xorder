@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart'
    show PosWriteContext;
import 'package:xorder_pos/data/postgres/postgres_print_queue_repository.dart';

import 'pg_fixture.dart';

/// Receipts the printer would not take (§ ship blocker 1).
///
/// The queue exists because *Print & new* promised one and there was none:
/// nothing printed, nothing queued, and the customer found out. Two claims
/// carry the weight here — a queued job comes back with its bytes **intact**,
/// because a receipt rebuilt tomorrow would be a different slip; and a job that
/// has printed can never print again, which is checked through the repository
/// and again by going round it in raw SQL.
void main() {
  if (PgFixture.host == null) {
    test('the print queue (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresPrintQueueRepository queue;
  late int businessId;
  late int branchId;

  const terminal = 'till-1';

  /// A short job that is recognisably itself. Real ones are 40KB of raster.
  Uint8List job(int mark) =>
      Uint8List.fromList([0x1B, 0x40, mark, 0x1D, 0x56, 0x42, 0x00]);

  setUp(() async {
    pg = await PgFixture.open('print_queue');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('print-queue', 'Print') "
      'RETURNING id',
    )).first[0]! as int;

    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'PQ', 'Print') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    queue = PostgresPrintQueueRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        businessId: businessId,
        branchId: branchId,
        terminalId: terminal,
        branchCode: 'PQ',
      ),
    );
  });

  tearDown(() => pg.close());

  group('what is owed', () {
    test('comes back as the exact bytes that were queued', () async {
      // Not a note to rebuild the receipt later. A slip re-rendered tomorrow
      // would carry tomorrow's receipt profile and tomorrow's language, which
      // is not the document the customer was promised.
      await queue.enqueue(
        printerName: '10.0.0.9:9100',
        bytes: job(0x41),
        isReprint: false,
        invoiceNumber: 'HST-000481',
      );

      final pending = await queue.pending();
      expect(pending, hasLength(1));
      expect(pending.single.bytes, job(0x41));
      expect(pending.single.printerName, '10.0.0.9:9100');
      expect(pending.single.invoiceNumber, 'HST-000481');
      expect(pending.single.attempts, 0);
    });

    test('is in the order the sales happened', () async {
      for (final mark in [0x41, 0x42, 0x43]) {
        await queue.enqueue(
          printerName: 'p',
          bytes: job(mark),
          isReprint: false,
        );
      }

      final pending = await queue.pending();
      expect(
        pending.map((j) => j.bytes[2]),
        [0x41, 0x42, 0x43],
        reason: 'a customer handed the slip above theirs holds the wrong total',
      );
    });

    test('is capped, so a till that was off all night does not spool', () async {
      for (var i = 0; i < 9; i++) {
        await queue.enqueue(printerName: 'p', bytes: job(i), isReprint: false);
      }

      // It catches up a few at a time over the next few sales rather than
      // holding the counter while forty receipts print.
      expect(await queue.pending(limit: 3), hasLength(3));
    });

    test('belongs to the till that took the money', () async {
      await queue.enqueue(printerName: 'p', bytes: job(1), isReprint: false);

      final other = PostgresPrintQueueRepository(
        database: db,
        config: pg.config,
        context: PosWriteContext(
          businessId: businessId,
          branchId: branchId,
          terminalId: 'till-2',
          branchCode: 'PQ',
        ),
      );

      // The customer is standing at one counter. A second till catching up the
      // first's paper hands a cashier receipts for sales they never made.
      expect(await other.pending(), isEmpty);
    });
  });

  group('a receipt prints once', () {
    test('and then never appears in the queue again', () async {
      final id = await queue.enqueue(
        printerName: 'p',
        bytes: job(1),
        isReprint: false,
      );

      await queue.markPrinted(id);
      expect(await queue.pending(), isEmpty);

      final row = await db.query(
        pg.config,
        'SELECT status, printed_at, attempts FROM pos_print_jobs WHERE id = @id',
        parameters: {'id': id},
      );
      expect(row.first[0], 'printed');
      expect(row.first[1], isNotNull, reason: 'a printed job says when');
      expect(row.first[2], 1);
    });

    test('and marking it printed twice changes nothing', () async {
      final id = await queue.enqueue(
        printerName: 'p',
        bytes: job(1),
        isReprint: false,
      );
      await queue.markPrinted(id);

      final first = (await db.query(
        pg.config,
        'SELECT printed_at FROM pos_print_jobs WHERE id = @id',
        parameters: {'id': id},
      )).first[0];

      // The repository guards on `status = 'pending'`, so the second call
      // matches no row rather than raising. Two drains racing — the same till
      // relaunched, a second window — is a Tuesday, not a fault.
      await queue.markPrinted(id);

      final second = (await db.query(
        pg.config,
        'SELECT printed_at, attempts FROM pos_print_jobs WHERE id = @id',
        parameters: {'id': id},
      )).first;
      expect(second[0], first);
      expect(second[1], 1);
    });

    test('and a failed attempt keeps it, counted', () async {
      final id = await queue.enqueue(
        printerName: 'p',
        bytes: job(1),
        isReprint: false,
      );

      await queue.markAttempted(id, error: 'The printer did not answer.');
      await queue.markAttempted(id, error: 'The printer did not answer.');

      final pending = await queue.pending();
      expect(pending.single.attempts, 2);
      expect(pending.single.bytes, job(1), reason: 'the job is untouched');
    });

    test('and raw SQL cannot put it back in the queue', () async {
      // The rule enforced through the repository above holds only while the
      // repository is the one writer. The second writer is not hypothetical: a
      // support engineer with psql, or a migration somebody hand-runs. A
      // printed job returned to 'pending' is a second copy of one sale's
      // receipt, which is how a refund gets claimed twice.
      final id = await queue.enqueue(
        printerName: 'p',
        bytes: job(1),
        isReprint: false,
      );
      await queue.markPrinted(id);

      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_print_jobs SET status = 'pending' WHERE id = @id",
          parameters: {'id': id},
        ),
        throwsA(
          predicate(
            (error) =>
                '$error'.contains('already printed') &&
                '$error'.contains('issue a reprint'),
            'says what has happened and what to do instead',
          ),
        ),
      );
    });

    test('and a job cannot claim to have printed at no particular time',
        () async {
      // The CHECK, not the trigger: a row inserted straight as 'printed' never
      // passes through the UPDATE that would stamp the time.
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_print_jobs (business_id, branch_id, terminal_id, '
          "  printer_name, payload, status) "
          "VALUES (@r, @b, @t, 'p', '\\x1b40'::bytea, 'printed')",
          parameters: {'r': businessId, 'b': branchId, 't': terminal},
        ),
        throwsA(
          predicate(
            (error) => '$error'.contains('pos_print_jobs_printed_has_time'),
            'the CHECK constraint refuses it',
          ),
        ),
      );
    });

    test('and a status nobody has heard of is refused', () async {
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_print_jobs (business_id, branch_id, terminal_id, '
          "  printer_name, payload, status) "
          "VALUES (@r, @b, @t, 'p', '\\x1b40'::bytea, 'maybe')",
          parameters: {'r': businessId, 'b': branchId, 't': terminal},
        ),
        throwsA(anything),
      );
    });
  });
}
