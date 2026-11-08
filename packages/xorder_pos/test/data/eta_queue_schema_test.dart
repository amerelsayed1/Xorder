@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_eta_queue_repository.dart';
import 'package:xorder_pos/domain/models/eta_submission.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/eta_receipt.dart';
import 'package:xorder_pos/domain/services/eta_serialization.dart';

import 'pg_fixture.dart';

/// The queue of receipts owed to Egypt's tax authority.
///
/// The chain is what makes this worth testing against a real server. Each
/// receipt names the uuid of the one before it from the same device, and a
/// gap in that chain is exactly what the authority is looking for — so the
/// read of the head and the write of the new one have to be one transaction,
/// and two devices in one branch have to be two independent chains.
void main() {
  if (PgFixture.host == null) {
    test('eta queue (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresEtaQueueRepository queue;
  late int branchId;
  late int orderId;
  late int businessId;

  const slug = 'eta-queue-test';

  const profile = ReceiptProfile(
    branchId: 1,
    tradeName: 'Koshari Abou Tarek',
    registrationNumber: '123456789',
    activityCode: '5610',
    branchCode: 'B1',
    address: BranchAddress(
      governate: 'Cairo',
      regionCity: 'Downtown',
      street: 'Champollion',
      buildingNumber: '16',
    ),
  );

  setUp(() async {
    pg = await PgFixture.open('eta_queue');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    final business = await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES (@slug, 'ETA Test') "
      'RETURNING id',
      parameters: {'slug': slug},
    );
    businessId = business.first[0]! as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    );
    branchId = branch.first[0]! as int;

    const terminal = '11111111-1111-4111-8111-111111111111';
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1')",
      parameters: {'t': terminal, 'r': businessId, 'b': branchId},
    );

    final order = await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, service_minor, vat_minor, total_minor, occurred_at) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, 'INV-1', 'takeaway', "
      "  'EGP', 2, 4500, 0, 630, 5130, now()) RETURNING id",
      parameters: {'r': businessId, 'b': branchId, 't': terminal},
    );
    orderId = order.first[0]! as int;

    queue = PostgresEtaQueueRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  EtaObject build(String previousUuid, {String number = 'INV-1', DateTime? at}) =>
      EtaReceiptBuilder.build(
        EtaReceiptInput(
          profile: profile,
          receiptNumber: number,
          issuedAt: at ?? DateTime.utc(2026, 9, 8, 13),
          deviceSerialNumber: 'TILL-1',
          items: const [
            EtaItem(
              description: 'Koshari',
              quantity: 1,
              unitPrice: Money(4500),
              totalSale: Money(4500),
              total: Money(5130),
              taxes: [
                TaxLine(
                  name: 'VAT',
                  rateBp: 1400,
                  base: Money(4500),
                  amount: Money(630),
                ),
              ],
            ),
          ],
          totalSales: const Money(4500),
          netAmount: const Money(4500),
          totalAmount: const Money(5130),
          taxTotals: const [
            TaxLine(
              name: 'VAT',
              rateBp: 1400,
              base: Money(4500),
              amount: Money(630),
            ),
          ],
          paymentMethod: 'C',
          previousUuid: previousUuid,
        ),
      );

  /// Another sale to file. One receipt per sale is the database's rule since
  /// migration 38, so a chain of receipts is a chain of sales.
  Future<int> newOrder(String number) async {
    final order = await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, service_minor, vat_minor, total_minor, occurred_at) '
      "VALUES (gen_random_uuid(), @r, @b, '11111111-1111-4111-8111-111111111111', "
      "  @n, 'takeaway', 'EGP', 2, 4500, 0, 630, 5130, now()) RETURNING id",
      parameters: {'r': businessId, 'b': branchId, 'n': number},
    );
    return order.first[0]! as int;
  }

  Future<EtaEnqueued> enqueue({
    String number = 'INV-1',
    String device = 'TILL-1',
    DateTime? at,
  }) async => queue.enqueue(
    orderId: number == 'INV-1' ? orderId : await newOrder(number),
    deviceSerial: device,
    receiptNumber: number,
    receiptType: 's',
    issuedAt: at ?? DateTime.utc(2026, 9, 8, 13),
    build: (previous) => build(previous, number: number, at: at),
  );

  group('the chain', () {
    test('the first receipt from a device has no predecessor', () async {
      final first = await enqueue();
      expect(first.previousUuid, isEmpty);
      expect(first.uuid, hasLength(64));
    });

    test('the second names the first', () async {
      final first = await enqueue();
      final second = await enqueue(number: 'INV-2');
      expect(second.previousUuid, first.uuid);
    });

    test('two devices in one branch have two independent chains', () async {
      // A shared chain would make every receipt from till two claim a
      // predecessor issued by till one, which is a gap the authority reads as
      // a missing document.
      final a1 = await enqueue(number: 'A-1');
      final b1 = await enqueue(number: 'B-1', device: 'TILL-2');
      expect(b1.previousUuid, isEmpty, reason: 'its own first');

      final a2 = await enqueue(number: 'A-2');
      expect(a2.previousUuid, a1.uuid);
      expect(a2.previousUuid, isNot(b1.uuid));
    });

    test('the head that is stored is the one the next receipt reads', () async {
      await enqueue();
      final second = await enqueue(number: 'INV-2');

      final rows = await db.query(
        pg.config,
        'SELECT last_uuid FROM pos_eta_chains WHERE device_serial = @d',
        parameters: {'d': 'TILL-1'},
      );
      expect(rows.first[0], second.uuid);
    });
  });

  group('what is stored', () {
    test('the canonical text is kept, not recomputed later', () async {
      // A rejection two days later is investigated against what was actually
      // hashed. Rebuilding it today would serialise a menu that has changed.
      final queued = await enqueue();
      final canonical = await queue.canonicalFor(queued.id);

      expect(canonical, EtaSerializer.canonical(queued.document));
      expect(canonical, contains('"RECEIPTNUMBER""INV-1"'));
    });

    test('the document is stored as the JSON that will be sent', () async {
      final queued = await enqueue();
      final rows = await db.query(
        pg.config,
        "SELECT document->'header'->>'uuid' FROM pos_eta_receipts "
        'WHERE id = @id',
        parameters: {'id': queued.id},
      );
      expect(rows.first[0], queued.uuid);
    });

    test('the same document cannot be queued twice', () async {
      // The uuid is a fingerprint, so a duplicate is the same document twice
      // and never two sales.
      await enqueue();
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_eta_receipts (business_id, branch_id, order_id, '
          'device_serial, uuid, receipt_number, receipt_type, document, '
          'canonical, issued_at) SELECT business_id, branch_id, order_id, '
          'device_serial, uuid, receipt_number, receipt_type, document, '
          'canonical, issued_at FROM pos_eta_receipts LIMIT 1',
        ),
        throwsA(isA<Object>()),
      );
    });

    test('an unknown status is refused by the database', () async {
      await enqueue();
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_eta_receipts SET status = 'cleared'",
        ),
        throwsA(isA<Object>()),
      );
    });
  });

  group('progress', () {
    test('a new receipt is pending and outstanding', () async {
      await enqueue();
      final outstanding = await queue.outstanding();
      expect(outstanding.single.status, EtaStatus.pending);
    });

    test('signing moves it on without sending it', () async {
      final queued = await enqueue();
      await queue.markSigned(queued.id, 'c2lnbmF0dXJl');

      final outstanding = await queue.outstanding();
      expect(outstanding.single.status, EtaStatus.signed);
      expect(outstanding.single.submittedAt, isNull);
    });

    test('acceptance takes it out of the queue', () async {
      final queued = await enqueue();
      await queue.markAccepted(queued.id, submissionUuid: 'SUB-1', longId: 'L1');

      expect(await queue.outstanding(), isEmpty);
      final summary = await queue.summary(now: DateTime.utc(2026, 9, 8, 14));
      expect(summary.isClear, isTrue);
    });

    test('a rejection stays outstanding and keeps its reason', () async {
      final queued = await enqueue();
      await queue.markRejected(queued.id, 'Invalid activity code');

      final outstanding = await queue.outstanding();
      expect(outstanding.single.status, EtaStatus.rejected);
      expect(outstanding.single.errorMessage, 'Invalid activity code');
    });

    test('a dropped line counts an attempt without becoming a verdict',
        () async {
      // Moving a signed receipt to `rejected` because the line was down would
      // put a person in front of a problem no person can fix.
      final queued = await enqueue();
      await queue.markSigned(queued.id, 'sig');
      await queue.markAttempted(queued.id, 'Connection reset');

      final outstanding = await queue.outstanding();
      expect(outstanding.single.status, EtaStatus.signed);
      expect(outstanding.single.attempts, 1);
      expect(outstanding.single.errorMessage, 'Connection reset');
    });

    test('signing an already-signed receipt does not re-sign it', () async {
      // The guard is in the WHERE clause: a second seal over the same document
      // would be a second document as far as the authority is concerned.
      final queued = await enqueue();
      await queue.markSigned(queued.id, 'first');
      await queue.markSigned(queued.id, 'second');

      final rows = await db.query(
        pg.config,
        'SELECT signature FROM pos_eta_receipts WHERE id = @id',
        parameters: {'id': queued.id},
      );
      expect(rows.first[0], 'first');
    });
  });

  group('the summary', () {
    test('counts what is outstanding and names the oldest', () async {
      await enqueue(number: 'INV-1', at: DateTime.utc(2026, 9, 8, 9));
      await enqueue(number: 'INV-2', at: DateTime.utc(2026, 9, 8, 11));

      final summary = await queue.summary(now: DateTime.utc(2026, 9, 8, 12));
      expect(summary.outstanding, 2);
      expect(summary.oldest, DateTime.utc(2026, 9, 8, 9));
      expect(summary.isUrgent, isFalse);
    });

    test('a receipt past twenty-four hours is late', () async {
      await enqueue(at: DateTime.utc(2026, 9, 7, 9));

      final summary = await queue.summary(now: DateTime.utc(2026, 9, 8, 12));
      expect(summary.late, 1);
      expect(summary.isUrgent, isTrue);
    });

    test('an accepted receipt is not late however old', () async {
      final queued = await enqueue(at: DateTime.utc(2026, 8, 1));
      await queue.markAccepted(queued.id, submissionUuid: 'SUB-1');

      final summary = await queue.summary(now: DateTime.utc(2026, 9, 8));
      expect(summary.late, 0);
      expect(summary.isClear, isTrue);
    });

    test('the deadline is measured against the clock passed in', () async {
      // Not SQL's `now()`: the screen and the query must agree about which
      // receipts are late, and two clocks would not.
      await enqueue(at: DateTime.utc(2026, 9, 8, 9));

      expect(
        (await queue.summary(now: DateTime.utc(2026, 9, 8, 10))).late,
        0,
      );
      expect(
        (await queue.summary(now: DateTime.utc(2026, 9, 9, 10))).late,
        1,
      );
    });

    test('a rejection is urgent even inside the window', () async {
      final queued = await enqueue(at: DateTime.utc(2026, 9, 8, 11));
      await queue.markRejected(queued.id, 'Invalid rin');

      final summary = await queue.summary(now: DateTime.utc(2026, 9, 8, 12));
      expect(summary.rejected, 1);
      expect(summary.late, 0);
      expect(summary.isUrgent, isTrue);
    });

    test('an empty branch is clear', () async {
      expect(
        (await queue.summary(now: DateTime.utc(2026, 9, 8))).isClear,
        isTrue,
      );
    });
  });
}
