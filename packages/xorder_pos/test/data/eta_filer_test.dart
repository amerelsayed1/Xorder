@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/eta/eta_filer.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_eta_queue_repository.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';
import 'package:xorder_pos/domain/services/eta_receipt.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Blockers 3 and 4: every sale and every refund this till recorded owes a
/// receipt, and nothing but a query decides which ones still do.
///
/// The acceptance, in the plan's words: settle with a blank profile → no row,
/// no alarm; complete the profile, run the reconciler → one row; run it twice
/// → still one row. A refund names its sale by uuid, and one whose sale is not
/// filed yet waits rather than pointing at nothing.
void main() {
  if (PgFixture.host == null) {
    test('eta filer (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const mine = '11111111-1111-4111-8111-111111111111';
  const theirs = '22222222-2222-4222-8222-222222222222';

  const complete = ReceiptProfile(
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
  const blank = ReceiptProfile(branchId: 1);
  const halfTyped = ReceiptProfile(branchId: 1, tradeName: 'Koshari');

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int staffId;
  late int cashTender;
  late PostgresEtaQueueRepository queue;
  late EtaFiler filer;
  var profile = blank;

  Future<Object?> one(String sql, [Map<String, Object?> p = const {}]) async =>
      (await db.query(pg.config, sql, parameters: p)).first[0];

  /// A sale as the till writes one: header, two lines and a voided one, the
  /// VAT per rate, and the cash that paid for it — one transaction.
  Future<int> sale({
    String invoice = 'INV-1',
    String status = 'PAID',
    String terminal = mine,
    DateTime? at,
  }) => db.runTx(pg.config, (tx) async {
    Future<Object?> ex(String sql, Map<String, Object?> p) async =>
        (await tx.execute(Sql.named(sql), parameters: p)).firstOrNull?[0];

    final order =
        await ex(
              'INSERT INTO pos_orders (client_transaction_id, business_id, '
              '  branch_id, terminal_id, invoice_number, order_type, currency, '
              '  exponent, subtotal_minor, discount_minor, service_minor, '
              '  vat_minor, total_minor, occurred_at, status) '
              'VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, '
              "  'takeaway', 'EGP', 2, 10000, 0, 0, 1400, 11400, @at, @status) "
              'RETURNING id',
              {
                'r': businessId,
                'b': branchId,
                't': terminal,
                'inv': invoice,
                'at': (at ?? DateTime.utc(2026, 9, 8, 13)),
                'status': status,
              },
            )
            as int;
    for (final (key, name, qty, unit, voided) in const [
      ('l1', 'Koshari', 2, 4000, false),
      ('l2', 'Mint tea', 1, 2000, false),
      ('l3', 'Voided dish', 1, 1500, true),
    ]) {
      await ex(
        'INSERT INTO pos_order_lines (order_id, line_key, name_snapshot, '
        '  quantity, unit_price_minor, line_total_minor, stage, voided_at, '
        '  voided_by) '
        "VALUES (@o, @k, @n, @q::int, @u::bigint, @q::int * @u::bigint, 'sent', "
        '  CASE WHEN @v THEN now() END, CASE WHEN @v THEN @by::bigint END)',
        {
          'o': order,
          'k': key,
          'n': name,
          'q': qty,
          'u': unit,
          'v': voided,
          'by': staffId,
        },
      );
    }
    await ex(
      'INSERT INTO pos_order_taxes (order_id, name_snapshot, rate_bp, '
      "  base_minor, amount_minor) VALUES (@o, 'VAT', 1400, 10000, 1400)",
      {'o': order},
    );
    await ex(
      'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
      "  amount_minor, counts_as_cash) VALUES (@o, @tt, 'Cash', 11400, true)",
      {'o': order, 'tt': cashTender},
    );
    return order;
  });

  /// One Koshari handed back, with its VAT, in cash. The database refuses a
  /// refund whose tender does not foot at commit, so all three rows go in one
  /// transaction.
  Future<int> refundOneKoshari(int orderId) => db.runTx(pg.config, (tx) async {
    final line =
        (await tx.execute(
              Sql.named(
                "SELECT id FROM pos_order_lines WHERE order_id = @o AND line_key = 'l1'",
              ),
              parameters: {'o': orderId},
            )).first[0]!
            as int;
    final refund =
        (await tx.execute(
              Sql.named(
                'INSERT INTO pos_refunds (client_refund_id, business_id, '
                '  branch_id, terminal_id, order_id, kind, subtotal_minor, '
                '  discount_minor, service_minor, vat_minor, total_minor, '
                '  refunded_by, occurred_at) '
                "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, 'partial', "
                "  4000, 0, 0, 560, 4560, @by, '2026-09-08T15:00:00Z') "
                'RETURNING id',
              ),
              parameters: {
                'r': businessId,
                'b': branchId,
                't': mine,
                'o': orderId,
                'by': staffId,
              },
            )).first[0]!
            as int;
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
        "  unit_price_minor, line_total_minor, name_snapshot) "
        "VALUES (@f, @l, 1, 4000, 4000, 'Koshari')",
      ),
      parameters: {'f': refund, 'l': line},
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
        "  amount_minor, counts_as_cash) VALUES (@f, @tt, 'Cash', 4560, true)",
      ),
      parameters: {'f': refund, 'tt': cashTender},
    );
    return refund;
  });

  Future<List<Map<String, Object?>>> receipts() async {
    final rows = await db.query(
      pg.config,
      'SELECT order_id, refund_id, receipt_type, receipt_number, uuid, '
      "  document->'header'->>'referenceOldUUID', "
      "  document->'header'->>'dateTimeIssued', document::text, device_serial "
      'FROM pos_eta_receipts WHERE branch_id = @b ORDER BY id',
      parameters: {'b': branchId},
    );
    return [
      for (final r in rows)
        {
          'order': r[0],
          'refund': r[1],
          'type': r[2],
          'number': r[3],
          'uuid': r[4],
          'references': r[5],
          'issued': r[6],
          'document': r[7],
          'device': r[8],
        },
    ];
  }

  setUp(() async {
    pg = await PgFixture.open('eta_filer');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_eta_receipts, pos_eta_chains, pos_refund_payments, '
      '  pos_refund_lines, pos_refunds, pos_order_payments, pos_order_taxes, '
      '  pos_order_lines, pos_orders RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        await one(
              "INSERT INTO pos_businesses (slug, name) "
              "VALUES ('eta-filer', 'ETA Filer') RETURNING id",
            )
            as int;
    branchId =
        await one(
              "INSERT INTO pos_branches (business_id, code, name) "
              "VALUES (@r, 'MAIN', 'Main') RETURNING id",
              {'r': businessId},
            )
            as int;
    staffId =
        await one(
              'INSERT INTO pos_users (business_id, branch_id, name, '
              "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', "
              "  'nour', 'salt', 'hash') RETURNING id",
              {'r': businessId, 'b': branchId},
            )
            as int;
    cashTender =
        await one(
              'INSERT INTO pos_tender_types (business_id, code, name_en, '
              "  kind, counts_as_cash) VALUES (@r, 'cash', 'Cash', 'cash', "
              '  true) RETURNING id',
              {'r': businessId},
            )
            as int;
    for (final (id, name) in const [(mine, 'Counter 1'), (theirs, 'Counter 2')]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
        'VALUES (@t::uuid, @r, @b, @n)',
        parameters: {'t': id, 'r': businessId, 'b': branchId, 'n': name},
      );
    }

    queue = PostgresEtaQueueRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
    profile = blank;
    filer = EtaFiler(
      database: db,
      config: pg.config,
      branchId: branchId,
      terminalId: mine,
      queue: queue,
      profile: () async => profile,
    );
  });

  tearDown(() => pg.close());

  group('the reconciler', () {
    test('a business that is not filing: nothing queued, nothing said',
        () async {
      await sale();

      final report = await filer.reconcile();

      expect(await receipts(), isEmpty);
      expect(report.problem, isNull, reason: 'an alarm always on is unread');
    });

    test('a half-typed profile: nothing queued, and it says so', () async {
      profile = halfTyped;
      await sale();

      final report = await filer.reconcile();

      expect(await receipts(), isEmpty);
      expect(report.problem, isA<ProfileIncomplete>());
    });

    test('completed later, it catches up — once', () async {
      // Rung up while the profile was blank; that sale is still owed.
      final order = await sale();
      await filer.reconcile();
      expect(await receipts(), isEmpty);

      profile = complete;
      final first = await filer.reconcile();
      final second = await filer.reconcile();

      expect(first.salesFiled, 1);
      expect(second.salesFiled, 0);
      final filed = await receipts();
      expect(filed, hasLength(1));
      expect(filed.single['order'], order);
      expect(filed.single['type'], EtaReceiptType.sale);
      expect(filed.single['device'], mine);
    });

    test('the receipt is the sale as it was recorded, not as it is filed',
        () async {
      profile = complete;
      await sale(at: DateTime.utc(2026, 9, 8, 13, 5));

      await filer.reconcile();

      final receipt = (await receipts()).single;
      expect(receipt['number'], 'INV-1');
      // Tuesday's sale caught up on Thursday is a Tuesday receipt.
      expect(receipt['issued'], startsWith('2026-09-08T13:05:00'));
      final document = receipt['document']! as String;
      expect(document, contains('Koshari'));
      expect(document, contains('Mint tea'));
      expect(
        document,
        isNot(contains('Voided dish')),
        reason: 'on the slip, off the filing: nobody was charged for it',
      );
    });

    test("only settled sales, and only this till's", () async {
      profile = complete;
      await sale(invoice: 'INV-OPEN', status: 'OPEN');
      await sale(invoice: 'INV-OTHER-TILL', terminal: theirs);
      final ours = await sale(invoice: 'INV-OURS');

      final report = await filer.reconcile();

      expect(report.salesFiled, 1);
      expect([for (final r in await receipts()) r['order']], [ours]);
    });

    test('oldest first, so the chain runs in the order they were sold',
        () async {
      profile = complete;
      await sale(invoice: 'INV-LATER', at: DateTime.utc(2026, 9, 8, 15));
      await sale(invoice: 'INV-EARLIER', at: DateTime.utc(2026, 9, 8, 11));

      await filer.reconcile();

      expect([for (final r in await receipts()) r['number']], [
        'INV-EARLIER',
        'INV-LATER',
      ]);
    });
  });

  group('one receipt per sale', () {
    test('filed at settlement and by the reconciler at once: one receipt',
        () async {
      profile = complete;
      final order = await sale();

      final answers = await Future.wait([
        filer.fileOrder(order),
        filer.fileOrder(order),
        filer.reconcile().then((r) => r.problem),
      ]);

      expect(await receipts(), hasLength(1));
      expect(answers, everyElement(isNull), reason: 'filed is not a failure');
    });

    test('and the database is what says so, not the filer', () async {
      // The uuid index cannot: the same sale queued twice is two documents,
      // because each names a different predecessor. Migration 38's index is
      // on the sale itself.
      profile = complete;
      final order = await sale();
      await filer.fileOrder(order);

      await expectLater(
        queue.enqueue(
          orderId: order,
          deviceSerial: mine,
          receiptNumber: 'INV-1',
          receiptType: EtaReceiptType.sale,
          issuedAt: DateTime.utc(2026, 9, 8, 13),
          build: (previous) => EtaReceiptBuilder.build(
            EtaReceiptInput(
              profile: complete,
              receiptNumber: 'INV-1',
              issuedAt: DateTime.utc(2026, 9, 8, 13),
              deviceSerialNumber: mine,
              items: const [],
              totalSales: Money.zero,
              netAmount: Money.zero,
              totalAmount: Money.zero,
              taxTotals: const [],
              paymentMethod: 'C',
              previousUuid: previous,
            ),
          ),
        ),
        throwsA(isA<PosDbException>()),
      );
    });
  });

  group('refunds', () {
    test('a refund waits for its sale, then names it', () async {
      final order = await sale();
      final refund = await refundOneKoshari(order);
      profile = complete;

      // The sale has no receipt: a refund pointing at nothing is the dangling
      // reference the authority rejects.
      expect(await filer.fileRefund(refund), isA<RefundAwaitingSale>());
      expect(await receipts(), isEmpty);

      final report = await filer.reconcile();

      expect(report.salesFiled, 1);
      expect(report.refundsFiled, 1);
      final [saleReceipt, refundReceipt] = await receipts();
      expect(refundReceipt['refund'], refund);
      expect(refundReceipt['type'], EtaReceiptType.refund);
      expect(refundReceipt['references'], saleReceipt['uuid']);
      expect(refundReceipt['number'], 'INV-1-R$refund');
      expect(refundReceipt['issued'], startsWith('2026-09-08T15:00:00'));
    });

    test('the refund files what went back, not the whole sale', () async {
      profile = complete;
      final order = await sale();
      await filer.reconcile();
      final refund = await refundOneKoshari(order);

      expect(await filer.fileRefund(refund), isNull);

      final document = (await receipts()).last['document']! as String;
      expect(document, contains('Koshari'));
      expect(document, isNot(contains('Mint tea')));
    });

    test('a refund is filed once, however often it is asked', () async {
      profile = complete;
      final order = await sale();
      await filer.reconcile();
      final refund = await refundOneKoshari(order);

      await Future.wait([filer.fileRefund(refund), filer.reconcile()]);
      await filer.reconcile();

      expect(
        (await receipts()).where((r) => r['refund'] == refund),
        hasLength(1),
      );
    });
  });
}
