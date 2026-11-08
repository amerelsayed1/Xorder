@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_order_history_repository.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Reading orders back out — migration 11 and the history repository.
///
/// The interesting claims are not "the SELECT returns rows". They are the ones
/// a wrong query would get subtly wrong and nobody would notice until an
/// auditor did: the branch scope, the date window's boundaries, the joins that
/// must not drop rows, and the fact that every number comes back exactly as it
/// was written.
void main() {
  if (PgFixture.host == null) {
    test('order history (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int nourId;
  late int samiId;
  late int reasonId;
  late PostgresOrderHistoryRepository repository;

  Future<int> insertOrder({
    required String invoice,
    required DateTime occurredAt,
    int? branch,
    String status = 'PAID',
    String orderType = 'dine_in',
    int subtotal = 10000,
    int discount = 0,
    int service = 0,
    int vat = 0,
    int? total,
    String? tableLabel,
    int? guests,
    int? servedBy,
    int? voidedBy,
    String? voidNote,
  }) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, table_label, guest_count, '
      '  currency, exponent, subtotal_minor, discount_minor, service_minor, '
      '  vat_minor, total_minor, occurred_at, status, served_by, voided_by, '
      '  voided_at, void_reason_id, void_note) '
      'VALUES (gen_random_uuid(), @r, @b, gen_random_uuid(), @invoice, @type, '
      '  @table, @guests, \'EGP\', 2, @sub, @disc, @svc, @vat, @total, '
      '  @at::timestamptz, @status, @served, @voidedBy, '
      '  @voidedAt::timestamptz, @reason, @note) RETURNING id',
      parameters: {
        'r': businessId,
        'b': branch ?? branchId,
        'invoice': invoice,
        'type': orderType,
        'table': tableLabel,
        'guests': guests,
        'sub': subtotal,
        'disc': discount,
        'svc': service,
        'vat': vat,
        'total': total ?? subtotal,
        'at': occurredAt.toUtc(),
        'status': status,
        'served': servedBy,
        'voidedBy': voidedBy,
        // Worked out here rather than in a CASE over the same bind parameter:
        // PostgreSQL deduces one type per parameter, and `@at` used as both a
        // timestamp and a CASE branch is "inconsistent types deduced".
        'voidedAt': voidedBy == null ? null : occurredAt.toUtc(),
        'reason': voidedBy == null ? null : reasonId,
        'note': voidNote,
      },
    );
    return rows.first[0] as int;
  }

  Future<int> insertLine(
    int orderId, {
    String lineKey = 'L1',
    String name = 'Koshari',
    int quantity = 2,
    int unitPrice = 5000,
    int refunded = 0,
    int? voidedBy,
    String? note,
    String? modifiers,
  }) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_order_lines (order_id, line_key, name_snapshot, quantity, '
      '  unit_price_minor, line_total_minor, stage, note, modifier_summary, '
      '  refunded_quantity, voided_by, voided_at) '
      "VALUES (@o, @key, @name, @qty, @unit, @tot, 'sent', @note, @mods, @ref, "
      '  @voidedBy, @voidedAt::timestamptz) RETURNING id',
      parameters: {
        'o': orderId,
        'key': lineKey,
        'name': name,
        'qty': quantity,
        'unit': unitPrice,
        'tot': unitPrice * quantity,
        'note': note,
        'mods': modifiers,
        'ref': refunded,
        'voidedBy': voidedBy,
        'voidedAt': voidedBy == null ? null : DateTime.utc(2026, 9, 7, 12),
      },
    );
    return rows.first[0] as int;
  }

  setUp(() async {
    pg = await PgFixture.open('order_history');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_businesses (slug, name) "
                  "VALUES ('hist', 'History') RETURNING id",
                ))
                .first[0]
            as int;

    branchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (business_id, code, name) "
                  "VALUES (@r, 'HST', 'Main') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;

    otherBranchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (business_id, code, name) "
                  "VALUES (@r, 'HS2', 'Second') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;

    Future<int> staff(String name, String username) async => (await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, @n, @u, 'salt', 'hash') RETURNING id",
      parameters: {
        'r': businessId,
        'b': branchId,
        'n': name,
        'u': username,
      },
    )).first[0] as int;

    nourId = await staff('Nour Adel', 'nour');
    samiId = await staff('Sami Farid', 'sami');

    reasonId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_reason_codes (business_id, scope, code, '
                  "  name_en, name_ar) VALUES (@r, 'void', 'wrong_order', "
                  "  'Wrong order', 'طلب خاطئ') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;

    repository = PostgresOrderHistoryRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  group('migration 11', () {
    test('served_by exists and is nullable', () async {
      // Nullable matters: every order written before this migration has no
      // seller, and a NOT NULL would have made the migration itself impossible
      // to apply to a branch that had ever traded.
      final id = await insertOrder(
        invoice: 'INV-1',
        occurredAt: DateTime(2026, 9, 7, 12),
      );
      final rows = await db.query(
        pg.config,
        'SELECT served_by FROM pos_orders WHERE id = @id',
        parameters: {'id': id},
      );
      expect(rows.first[0], isNull);
    });

    test('served_by will not accept a staff id that does not exist', () async {
      await expectLater(
        insertOrder(
          invoice: 'INV-2',
          occurredAt: DateTime(2026, 9, 7, 12),
          servedBy: 999999,
        ),
        throwsA(anything),
      );
    });

    test('deleting the seller is refused, not cascaded', () async {
      // The whole point of recording who sold something is that it survives
      // them leaving. ON DELETE CASCADE here would delete the sale.
      await insertOrder(
        invoice: 'INV-3',
        occurredAt: DateTime(2026, 9, 7, 12),
        servedBy: nourId,
      );
      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_users WHERE id = @id',
          parameters: {'id': nourId},
        ),
        throwsA(anything),
      );
    });
  });

  group('search', () {
    test('returns newest first', () async {
      await insertOrder(
        invoice: 'INV-10',
        occurredAt: DateTime(2026, 9, 7, 10),
      );
      await insertOrder(
        invoice: 'INV-12',
        occurredAt: DateTime(2026, 9, 7, 12),
      );
      await insertOrder(
        invoice: 'INV-11',
        occurredAt: DateTime(2026, 9, 7, 11),
      );

      final orders = await repository.search(const OrderHistoryQuery());
      expect(orders.map((o) => o.invoiceNumber), [
        'INV-12',
        'INV-11',
        'INV-10',
      ]);
    });

    test('never returns another branch, even in the same business', () async {
      await insertOrder(invoice: 'MINE', occurredAt: DateTime(2026, 9, 7, 12));
      await insertOrder(
        invoice: 'THEIRS',
        occurredAt: DateTime(2026, 9, 7, 13),
        branch: otherBranchId,
      );

      final orders = await repository.search(const OrderHistoryQuery());
      expect(orders.map((o) => o.invoiceNumber), ['MINE']);
    });

    test('from is inclusive and to is exclusive', () async {
      // The boundary that decides whether a sale at exactly midnight belongs to
      // the day that ended or the day that started. Half-open, so consecutive
      // windows tile without overlapping — an order counted in two days is an
      // order double-counted in a report.
      await insertOrder(
        invoice: 'START',
        occurredAt: DateTime(2026, 9, 7),
      );
      await insertOrder(invoice: 'END', occurredAt: DateTime(2026, 9, 8));

      final orders = await repository.search(
        OrderHistoryQuery(from: DateTime(2026, 9, 7), to: DateTime(2026, 9, 8)),
      );
      expect(orders.map((o) => o.invoiceNumber), ['START']);
    });

    test('filters by status', () async {
      await insertOrder(invoice: 'PAID-1', occurredAt: DateTime(2026, 9, 7, 9));
      await insertOrder(
        invoice: 'VOID-1',
        occurredAt: DateTime(2026, 9, 7, 10),
        status: 'VOIDED',
        voidedBy: samiId,
      );

      final voided = await repository.search(
        const OrderHistoryQuery(statuses: {OrderStatus.voided}),
      );
      expect(voided.map((o) => o.invoiceNumber), ['VOID-1']);
      expect(voided.single.status, OrderStatus.voided);
    });

    test('filters by several statuses at once', () async {
      await insertOrder(invoice: 'P', occurredAt: DateTime(2026, 9, 7, 9));
      await insertOrder(
        invoice: 'V',
        occurredAt: DateTime(2026, 9, 7, 10),
        status: 'VOIDED',
        voidedBy: samiId,
      );
      await insertOrder(
        invoice: 'R',
        occurredAt: DateTime(2026, 9, 7, 11),
        status: 'REFUNDED',
      );

      final orders = await repository.search(
        const OrderHistoryQuery(
          statuses: {OrderStatus.voided, OrderStatus.refunded},
        ),
      );
      expect(orders.map((o) => o.invoiceNumber), ['R', 'V']);
    });

    test('filters by order type', () async {
      await insertOrder(invoice: 'D', occurredAt: DateTime(2026, 9, 7, 9));
      await insertOrder(
        invoice: 'T',
        occurredAt: DateTime(2026, 9, 7, 10),
        orderType: 'takeaway',
      );

      final orders = await repository.search(
        const OrderHistoryQuery(orderTypes: {OrderType.takeaway}),
      );
      expect(orders.map((o) => o.invoiceNumber), ['T']);
    });

    test('filters by who sold it', () async {
      await insertOrder(
        invoice: 'NOUR',
        occurredAt: DateTime(2026, 9, 7, 9),
        servedBy: nourId,
      );
      await insertOrder(
        invoice: 'SAMI',
        occurredAt: DateTime(2026, 9, 7, 10),
        servedBy: samiId,
      );
      await insertOrder(
        invoice: 'NOBODY',
        occurredAt: DateTime(2026, 9, 7, 11),
      );

      final orders = await repository.search(
        OrderHistoryQuery(servedByStaffId: nourId),
      );
      expect(orders.map((o) => o.invoiceNumber), ['NOUR']);
      expect(orders.single.servedByName, 'Nour Adel');
      expect(orders.single.servedByStaffId, nourId);
    });

    test('search matches the tail of an invoice number', () async {
      // What somebody reads off a receipt in their hand. A prefix match would
      // fail on exactly the input they have.
      await insertOrder(
        invoice: 'HST-2026-000481',
        occurredAt: DateTime(2026, 9, 7, 9),
      );
      await insertOrder(
        invoice: 'HST-2026-000482',
        occurredAt: DateTime(2026, 9, 7, 10),
      );

      final orders = await repository.search(
        const OrderHistoryQuery(search: '481'),
      );
      expect(orders.map((o) => o.invoiceNumber), ['HST-2026-000481']);
    });

    test('search matches a table label too', () async {
      await insertOrder(
        invoice: 'A',
        occurredAt: DateTime(2026, 9, 7, 9),
        tableLabel: 'T12',
      );
      await insertOrder(invoice: 'B', occurredAt: DateTime(2026, 9, 7, 10));

      final orders = await repository.search(
        const OrderHistoryQuery(search: 't12'),
      );
      expect(orders.map((o) => o.invoiceNumber), ['A']);
    });

    test('the limit is a hard ceiling', () async {
      for (var i = 0; i < 8; i++) {
        await insertOrder(
          invoice: 'INV-$i',
          occurredAt: DateTime(2026, 9, 7, 9, i),
        );
      }
      final orders = await repository.search(
        const OrderHistoryQuery(limit: 3),
      );
      expect(orders, hasLength(3));
      // The newest three, not an arbitrary three.
      expect(orders.map((o) => o.invoiceNumber), ['INV-7', 'INV-6', 'INV-5']);
    });

    test('an order whose seller was never recorded still appears', () async {
      // The join is LEFT for exactly this. An INNER join would make every
      // order written before migration 11 vanish from history.
      await insertOrder(invoice: 'OLD', occurredAt: DateTime(2026, 9, 7, 9));

      final orders = await repository.search(const OrderHistoryQuery());
      expect(orders.single.invoiceNumber, 'OLD');
      expect(orders.single.servedByName, isNull);
    });

    test('every money column comes back exactly as written', () async {
      await insertOrder(
        invoice: 'MONEY',
        occurredAt: DateTime(2026, 9, 7, 9),
        subtotal: 66640,
        discount: 6664,
        service: 5998,
        vat: 9330,
        total: 75304,
      );

      final order = (await repository.search(const OrderHistoryQuery())).single;
      expect(order.subtotal.minor, 66640);
      expect(order.discount.minor, 6664);
      expect(order.service.minor, 5998);
      expect(order.vat.minor, 9330);
      expect(order.total.minor, 75304);
      // Read, never recomputed. The point of the record is that today's tax
      // configuration cannot change what a customer already paid.
      expect(order.total.currency, 'EGP');
      expect(order.total.exponent, 2);
    });

    test('a voided order carries who, why and the note', () async {
      await insertOrder(
        invoice: 'VOID',
        occurredAt: DateTime(2026, 9, 7, 9),
        status: 'VOIDED',
        voidedBy: samiId,
        voidNote: 'Customer left',
      );

      final order = (await repository.search(const OrderHistoryQuery())).single;
      expect(order.isVoided, isTrue);
      expect(order.voidedByName, 'Sami Farid');
      expect(order.voidReason, 'Wrong order');
      expect(order.voidReasonAr, 'طلب خاطئ');
      expect(order.voidNote, 'Customer left');
      expect(order.voidedAt, isNotNull);
    });
  });

  group('byInvoiceNumber', () {
    test('finds the one order', () async {
      await insertOrder(
        invoice: 'HST-2026-000481',
        occurredAt: DateTime(2026, 9, 7, 9),
      );
      final order = await repository.byInvoiceNumber('HST-2026-000481');
      expect(order, isNotNull);
      expect(order!.invoiceNumber, 'HST-2026-000481');
    });

    test('is exact, not a substring match', () async {
      // A refund is issued against *the* order on the receipt in somebody's
      // hand. "Did you mean one of these four" is not a question to ask while
      // money is being given back.
      await insertOrder(
        invoice: 'HST-2026-000481',
        occurredAt: DateTime(2026, 9, 7, 9),
      );
      expect(await repository.byInvoiceNumber('481'), isNull);
    });

    test('surrounding whitespace is forgiven', () async {
      await insertOrder(invoice: 'INV-9', occurredAt: DateTime(2026, 9, 7, 9));
      expect(await repository.byInvoiceNumber('  INV-9 '), isNotNull);
    });

    test('another branch is not found', () async {
      await insertOrder(
        invoice: 'THEIRS',
        occurredAt: DateTime(2026, 9, 7, 9),
        branch: otherBranchId,
      );
      expect(await repository.byInvoiceNumber('THEIRS'), isNull);
    });
  });

  group('detail', () {
    test('null for an id that names nothing', () async {
      expect(await repository.detail(999999), isNull);
    });

    test('null for another branch, not the order', () async {
      final id = await insertOrder(
        invoice: 'THEIRS',
        occurredAt: DateTime(2026, 9, 7, 9),
        branch: otherBranchId,
      );
      expect(await repository.detail(id), isNull);
    });

    test('carries lines in insertion order with their snapshots', () async {
      final id = await insertOrder(
        invoice: 'INV-D',
        occurredAt: DateTime(2026, 9, 7, 9),
        servedBy: nourId,
      );
      await insertLine(id, lineKey: 'L1', name: 'Koshari', quantity: 2);
      await insertLine(
        id,
        lineKey: 'L2',
        name: 'Mint tea',
        quantity: 1,
        unitPrice: 2500,
        modifiers: 'No sugar',
        note: 'Extra hot',
      );

      final detail = await repository.detail(id);
      expect(detail!.lines.map((l) => l.name), ['Koshari', 'Mint tea']);
      expect(detail.lines.first.lineTotal.minor, 10000);
      expect(detail.lines.last.modifierSummary, 'No sugar');
      expect(detail.lines.last.note, 'Extra hot');
      expect(detail.order.servedByName, 'Nour Adel');
    });

    test('a voided line keeps its place and names who voided it', () async {
      // It does not vanish. A voided line that disappeared would leave a
      // kitchen docket referring to food nobody can account for.
      final id = await insertOrder(
        invoice: 'INV-V',
        occurredAt: DateTime(2026, 9, 7, 9),
      );
      await insertLine(id, lineKey: 'L1');
      await insertLine(id, lineKey: 'L2', name: 'Soup', voidedBy: samiId);

      final detail = await repository.detail(id);
      expect(detail!.lines, hasLength(2));
      final voided = detail.lines.last;
      expect(voided.isVoided, isTrue);
      expect(voided.voidedByName, 'Sami Farid');
      expect(voided.refundableQuantity, 0);
      expect(detail.chargedLines.map((l) => l.name), ['Koshari']);
    });

    test('refunded_quantity comes through and reduces what is left', () async {
      final id = await insertOrder(
        invoice: 'INV-R',
        occurredAt: DateTime(2026, 9, 7, 9),
      );
      await insertLine(id, quantity: 3, refunded: 1);

      final detail = await repository.detail(id);
      expect(detail!.lines.single.refundedQuantity, 1);
      expect(detail.lines.single.refundableQuantity, 2);
    });

    test('payments come back with their labels and references', () async {
      final id = await insertOrder(
        invoice: 'INV-P',
        occurredAt: DateTime(2026, 9, 7, 9),
      );
      await db.query(
        pg.config,
        'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
        "  amount_minor, reference) VALUES (@o, 1, 'Cash', 6000, NULL), "
        "  (@o, 2, 'Card', 4000, '4821')",
        parameters: {'o': id},
      );

      final detail = await repository.detail(id);
      expect(detail!.payments.map((p) => p.label), ['Cash', 'Card']);
      expect(detail.payments.first.amount.minor, 6000);
      expect(detail.payments.last.reference, '4821');
    });

    test('an order with no payment is not an error', () async {
      // A voided order is exactly this: real totals, no money taken.
      final id = await insertOrder(
        invoice: 'INV-NP',
        occurredAt: DateTime(2026, 9, 7, 9),
        status: 'VOIDED',
        voidedBy: samiId,
      );
      final detail = await repository.detail(id);
      expect(detail!.payments, isEmpty);
    });

    test('the tax breakdown comes back by rate, as it was written', () async {
      // What a reprint prints its VAT rate from. Stored rates, not a rate
      // worked back out of `vat_minor`.
      final id = await insertOrder(
        invoice: 'INV-TAX',
        occurredAt: DateTime(2026, 9, 7, 9),
        subtotal: 11500,
        vat: 1400,
        total: 12900,
      );
      await db.query(
        pg.config,
        'INSERT INTO pos_order_taxes (order_id, name_snapshot, rate_bp, '
        "  base_minor, amount_minor) VALUES (@o, 'VAT', 1400, 10000, 1400), "
        "  (@o, 'Zero-rated', 0, 1500, 0)",
        parameters: {'o': id},
      );

      final detail = await repository.detail(id);
      expect(detail!.taxLines.map((t) => t.rateBp), [1400, 0]);
      expect(detail.taxLines.first.amount.minor, 1400);
      expect(detail.taxLines.last.base.minor, 1500);
      expect(detail.taxLines.last.name, 'Zero-rated');
    });

    test('an order with no breakdown reads as none, not as an error', () async {
      final id = await insertOrder(
        invoice: 'INV-NOTAX',
        occurredAt: DateTime(2026, 9, 7, 9),
      );
      final detail = await repository.detail(id);
      expect(detail!.taxLines, isEmpty);
    });

    test('discounts name both the applier and the approver', () async {
      final id = await insertOrder(
        invoice: 'INV-DISC',
        occurredAt: DateTime(2026, 9, 7, 9),
        subtotal: 10000,
        discount: 1500,
      );
      final lineId = await insertLine(id, lineKey: 'L1');
      await db.query(
        pg.config,
        'INSERT INTO pos_order_discounts (order_id, order_line_id, '
        '  name_snapshot, kind, value_bp, amount_minor, applied_by, '
        '  approved_by_id) '
        "VALUES (@o, @l, 'Staff meal', 'percentage', 1000, 1000, @nour, @sami), "
        "  (@o, NULL, 'Manager comp', 'fixed', NULL, 500, @nour, NULL)",
        parameters: {'o': id, 'l': lineId, 'nour': nourId, 'sami': samiId},
      );

      final detail = await repository.detail(id);
      expect(detail!.discounts, hasLength(2));

      final line = detail.discounts.first;
      expect(line.name, 'Staff meal');
      expect(line.amount.minor, 1000);
      // The line key, not the row id: the pane renders a line discount inside
      // its line, and it matches on the key the ticket used.
      expect(line.lineKey, 'L1');
      expect(line.appliedByName, 'Nour Adel');
      expect(line.approvedByName, 'Sami Farid');

      final order = detail.discounts.last;
      // Null line key means the whole order. That distinction is load-bearing
      // on screen as well as in the ledger.
      expect(order.lineKey, isNull);
      expect(order.approvedByName, isNull);
    });
  });
}
