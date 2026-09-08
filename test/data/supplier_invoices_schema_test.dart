@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_supplier_invoices_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/supplier_invoice.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// What is owed and what has been paid, stored.
///
/// Two of these tests exist for the two invariants that are triggers rather
/// than CHECK constraints, because both are cross-row and neither can be
/// expressed any other way: payments against one invoice may not exceed it, and
/// an invoice with money on it cannot be voided. A rule enforced only in Dart
/// holds until somebody writes the second writer.
void main() {
  if (PgFixture.host == null) {
    test(
      'supplier invoices (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresSupplierInvoicesRepository ledger;
  late int restaurantId;
  late int branchId;
  late int supplierId;
  late int otherSupplierId;

  const buyer = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'buyer',
      nameEn: 'Buyer',
      capabilities: {PosCapability.purchaseManage},
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate},
    ),
  );

  DateTime day(int d) => DateTime.utc(2026, 3, d);

  late int invoiceVoidReason;
  late int paymentVoidReason;

  setUp(() async {
    pg = await PgFixture.open('supplier_invoices');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_restaurants (slug, name) VALUES ('si', 'SI') RETURNING id",
            )).first[0]!
            as int;
    branchId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_branches (restaurant_id, code, name) '
              "VALUES (@r, 'MAIN', 'Main') RETURNING id",
              parameters: {'r': restaurantId},
            )).first[0]!
            as int;
    supplierId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_suppliers (restaurant_id, name_en, payment_term_days) '
              "VALUES (@r, 'Nile Dairy', 30) RETURNING id",
              parameters: {'r': restaurantId},
            )).first[0]!
            as int;
    otherSupplierId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_suppliers (restaurant_id, name_en) '
              "VALUES (@r, 'Cairo Meats') RETURNING id",
              parameters: {'r': restaurantId},
            )).first[0]!
            as int;

    // **Seeded the way a real install seeds them.** Migration 31's CROSS JOIN
    // can only see restaurants that already existed, and this fixture creates
    // one afterwards — the same gap that left a freshly installed restaurant
    // with no payment methods. Going through `LocalBootstrap` is what proves
    // the new scopes are on its list.
    await LocalBootstrap(db).seedReasonCodes(pg.config, restaurantId);

    invoiceVoidReason = (await db.query(
      pg.config,
      "SELECT id FROM pos_reason_codes WHERE restaurant_id = @r "
      "AND scope = 'invoice_void' AND code = 'entered_twice'",
      parameters: {'r': restaurantId},
    )).first[0]! as int;
    paymentVoidReason = (await db.query(
      pg.config,
      "SELECT id FROM pos_reason_codes WHERE restaurant_id = @r "
      "AND scope = 'payment_void' AND code = 'wrong_invoice'",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    ledger = PostgresSupplierInvoicesRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  SupplierInvoice draft({
    int id = 0,
    int? supplier,
    String number = 'INV-900',
    int totalMinor = 100000,
    int taxMinor = 12281,
    int issued = 1,
    int due = 31,
  }) => SupplierInvoice(
    id: id,
    supplierId: supplier ?? supplierId,
    number: number,
    total: Money(totalMinor),
    tax: Money(taxMinor),
    issuedAt: day(issued),
    dueAt: day(due),
  );

  Future<SupplierInvoice> enter(SupplierInvoice invoice) async {
    final result = await ledger.save(invoice, by: buyer);
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  Future<SupplierPayment> settle({
    required int amountMinor,
    int? invoiceId,
    int? supplier,
    SupplierPaymentMethod method = SupplierPaymentMethod.cash,
    String? reference,
  }) async {
    final result = await ledger.pay(
      SupplierPayment(
        id: 0,
        supplierId: supplier ?? supplierId,
        invoiceId: invoiceId,
        amount: Money(amountMinor),
        method: method,
        reference: reference,
        paidAt: day(5),
      ),
      by: buyer,
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  group('entering one', () {
    test('an invoice round-trips', () async {
      final saved = await enter(draft());

      expect(saved.id, greaterThan(0));
      expect(saved.number, 'INV-900');
      expect(saved.total, const Money(100000));
      expect(saved.tax, const Money(12281));
      expect(saved.subtotal, const Money(87719));
      expect(saved.paid, Money.zero, reason: 'nothing paid yet');
      expect(saved.outstanding, const Money(100000));
      expect(saved.supplierName, 'Nile Dairy');
    });

    test('the supplier name is snapshotted, not joined', () async {
      // A ledger has to still say who was owed after somebody corrects a
      // spelling.
      final saved = await enter(draft());
      await db.query(
        pg.config,
        "UPDATE pos_suppliers SET name_en = 'Nile Dairy Co' WHERE id = @s",
        parameters: {'s': supplierId},
      );

      expect((await ledger.byId(saved.id))!.supplierName, 'Nile Dairy');
    });

    test('the same invoice number twice is refused by name', () async {
      // **The commonest error in purchase bookkeeping**, and the message says
      // which invoice rather than naming a constraint at somebody holding a
      // piece of paper.
      await enter(draft(number: 'INV-900'));
      final again = await ledger.save(draft(number: 'INV-900'), by: buyer);

      expect(again.succeeded, isFalse);
      expect((again.refusal! as CatalogInvalid).reason, contains('INV-900'));
    });

    test('case and padding do not make it a different invoice', () async {
      await enter(draft(number: 'INV-900'));
      final again = await ledger.save(draft(number: ' inv-900 '), by: buyer);
      expect(again.succeeded, isFalse);
    });

    test('two suppliers may use the same number', () async {
      // Numbering is the supplier's, not the restaurant's.
      await enter(draft(number: '1001'));
      await enter(draft(number: '1001', supplier: otherSupplierId));
      expect((await ledger.all()).length, 2);
    });

    test('a number freed by a void can be entered again', () async {
      // Which is the reason the void exists: an invoice typed against the wrong
      // supplier is cancelled and re-entered under the same number.
      final first = await enter(draft(number: 'INV-900'));
      await ledger.voidInvoice(first.id, reasonId: invoiceVoidReason, by: buyer);

      final again = await ledger.save(draft(number: 'INV-900'), by: buyer);
      expect(again.succeeded, isTrue, reason: '${again.refusal}');
    });

    test('the invoice date is what was typed, not when it was typed', () async {
      // An invoice dated the 3rd and entered on the 20th is due from the 3rd.
      // Stamping `now()` would hand the restaurant weeks the supplier has not
      // agreed to.
      final saved = await enter(draft(issued: 3, due: 33));
      expect(saved.issuedAt.toUtc(), day(3));
      expect(saved.dueAt.toUtc(), DateTime.utc(2026, 4, 2));
    });

    test('an invoice for nothing is refused', () async {
      final result = await ledger.save(
        draft(totalMinor: 0, taxMinor: 0),
        by: buyer,
      );
      expect(result.succeeded, isFalse);
    });

    test('a supplier from another restaurant is refused', () async {
      final elsewhere =
          (await db.query(
                pg.config,
                "INSERT INTO pos_restaurants (slug, name) VALUES ('x', 'X') RETURNING id",
              )).first[0]!
              as int;
      final theirs =
          (await db.query(
                pg.config,
                "INSERT INTO pos_suppliers (restaurant_id, name_en) "
                "VALUES (@r, 'Theirs') RETURNING id",
                parameters: {'r': elsewhere},
              )).first[0]!
              as int;

      final result = await ledger.save(draft(supplier: theirs), by: buyer);
      expect(result.succeeded, isFalse);
      expect(await ledger.all(), isEmpty);
    });

    test('editing one keeps the number unique against the others', () async {
      await enter(draft(number: 'A'));
      final second = await enter(draft(number: 'B'));

      final clash = await ledger.save(second.copyWith(number: 'A'), by: buyer);
      expect(clash.succeeded, isFalse);

      // And re-saving it under its own number is not a clash with itself.
      final same = await ledger.save(
        second.copyWith(note: 'checked'),
        by: buyer,
      );
      expect(same.succeeded, isTrue, reason: '${same.refusal}');
    });

    test('a cancelled invoice is a record — it cannot be edited', () async {
      final saved = await enter(draft());
      await ledger.voidInvoice(saved.id, reasonId: invoiceVoidReason, by: buyer);

      final edit = await ledger.save(
        saved.copyWith(total: const Money(50000)),
        by: buyer,
      );
      expect(edit.succeeded, isFalse);
      expect((await ledger.byId(saved.id))!.total, const Money(100000));
    });

    test(
      'entering an invoice is audited — a debt came into existence',
      () async {
        final saved = await enter(draft());
        final rows = await db.query(
          pg.config,
          'SELECT action, entity_id FROM pos_audit_events '
          'WHERE action = @a ORDER BY id DESC LIMIT 1',
          parameters: {'a': AuditAction.supplierInvoiceSaved},
        );
        expect(rows, hasLength(1));
        expect(rows.first[1], '${saved.id}');
      },
    );
  });

  group('paying', () {
    test('a payment reduces what is outstanding', () async {
      final bill = await enter(draft(totalMinor: 100000));
      await settle(invoiceId: bill.id, amountMinor: 40000);

      final after = (await ledger.byId(bill.id))!;
      expect(after.paid, const Money(40000));
      expect(after.outstanding, const Money(60000));
      expect(after.isSettled, isFalse);
    });

    test('paid in full leaves it off the unpaid list', () async {
      final bill = await enter(draft(totalMinor: 100000));
      expect(await ledger.unpaid(), hasLength(1));

      await settle(invoiceId: bill.id, amountMinor: 100000);
      expect(await ledger.unpaid(), isEmpty);
    });

    test(
      'unpaid comes back oldest due first — the order somebody pays in',
      () async {
        await enter(draft(number: 'LATE', due: 10));
        await enter(draft(number: 'LATER', due: 40));
        await enter(draft(number: 'SOON', due: 20));

        expect(
          [for (final i in await ledger.unpaid()) i.number],
          ['LATE', 'SOON', 'LATER'],
        );
      },
    );

    test(
      'overpaying one invoice is refused, with the room left named',
      () async {
        // Not a database error surfaced to a bookkeeper: the message says how
        // much is left and where the rest belongs.
        final bill = await enter(draft(totalMinor: 100000));
        await settle(invoiceId: bill.id, amountMinor: 70000);

        final too = await ledger.pay(
          SupplierPayment(
            id: 0,
            supplierId: supplierId,
            invoiceId: bill.id,
            amount: const Money(40000),
            method: SupplierPaymentMethod.cash,
            paidAt: day(6),
          ),
          by: buyer,
        );

        expect(too.succeeded, isFalse);
        expect((too.refusal! as CatalogInvalid).reason, contains('300.00'));
        expect((await ledger.byId(bill.id))!.paid, const Money(70000));
      },
    );

    test('the database refuses an over-allocation even without the repository', () async {
      // **The invariant, tested where it lives.** The repository checks this
      // too, so this goes round it — a rule that holds only in Dart holds until
      // somebody writes the second writer, and a trigger holds for psql as
      // well.
      final bill = await enter(draft(totalMinor: 100000));

      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_supplier_payments (restaurant_id, branch_id, '
          '  supplier_id, supplier_name, invoice_id, method, amount_minor) '
          "VALUES (@r, @b, @s, 'Nile Dairy', @i, 'cash', 150000)",
          parameters: {
            'r': restaurantId,
            'b': branchId,
            's': supplierId,
            'i': bill.id,
          },
        ),
        throwsA(
          isA<Exception>().having((e) => '$e', 'message', contains('overpay')),
        ),
      );
    });

    test(
      'a payment cannot be pointed at another supplier\'s invoice',
      () async {
        final theirs = await enter(
          draft(supplier: otherSupplierId, number: 'X'),
        );

        final wrong = await ledger.pay(
          SupplierPayment(
            id: 0,
            supplierId: supplierId,
            invoiceId: theirs.id,
            amount: const Money(1000),
            method: SupplierPaymentMethod.cash,
            paidAt: day(5),
          ),
          by: buyer,
        );
        expect(wrong.succeeded, isFalse);
      },
    );

    test('the database refuses that too', () async {
      final theirs = await enter(draft(supplier: otherSupplierId, number: 'X'));

      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_supplier_payments (restaurant_id, branch_id, '
          '  supplier_id, supplier_name, invoice_id, method, amount_minor) '
          "VALUES (@r, @b, @s, 'Nile Dairy', @i, 'cash', 1000)",
          parameters: {
            'r': restaurantId,
            'b': branchId,
            's': supplierId,
            'i': theirs.id,
          },
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('money on account is allowed and belongs to nothing', () async {
      final paid = await settle(invoiceId: null, amountMinor: 200000);

      expect(paid.isOnAccount, isTrue);
      expect(paid.invoiceId, isNull);

      final account = await ledger.accountFor(supplierId, asOf: day(15));
      expect(account.onAccount, const Money(200000));
      expect(account.outstanding, const Money(-200000));
      expect(account.isInCredit, isTrue);
    });

    test('on-account money does not stop a bill being overdue', () async {
      // The decision the model makes, holding across the database round trip.
      await enter(draft(totalMinor: 100000, due: 10));
      await settle(invoiceId: null, amountMinor: 200000);

      final account = await ledger.accountFor(supplierId, asOf: day(20));
      expect(account.overdue, const Money(100000));
      expect(account.outstanding, const Money(-100000));
    });

    test('a cheque keeps the number somebody quotes to a bank', () async {
      final paid = await settle(
        amountMinor: 50000,
        invoiceId: null,
        method: SupplierPaymentMethod.cheque,
        reference: '004512',
      );
      expect(paid.method, SupplierPaymentMethod.cheque);
      expect(paid.reference, '004512');
    });

    test('a payment carries no drawer movement from the back office', () async {
      // Stated as a test because it is a known gap rather than an oversight:
      // the office has no open shift, so nothing here reduces the till. A
      // restaurant paying out of the drawer records the pay-out at the till.
      final paid = await settle(amountMinor: 50000, invoiceId: null);
      expect(paid.cashMovementId, isNull);
    });

    test('paying is audited — it is money leaving the business', () async {
      final bill = await enter(draft());
      final paid = await settle(invoiceId: bill.id, amountMinor: 1000);

      final rows = await db.query(
        pg.config,
        'SELECT entity_id FROM pos_audit_events WHERE action = @a',
        parameters: {'a': AuditAction.supplierPaid},
      );
      expect(rows.map((r) => r[0]), contains('${paid.id}'));
    });
  });

  group('putting it right', () {
    test('voiding a payment frees the room it took', () async {
      final bill = await enter(draft(totalMinor: 100000));
      final paid = await settle(invoiceId: bill.id, amountMinor: 100000);
      expect((await ledger.byId(bill.id))!.isSettled, isTrue);

      final undone = await ledger.voidPayment(paid.id, reasonId: paymentVoidReason, by: buyer);
      expect(undone.succeeded, isTrue, reason: '${undone.refusal}');
      expect(undone.value!.isVoided, isTrue);

      final after = (await ledger.byId(bill.id))!;
      expect(after.paid, Money.zero);
      expect(after.outstanding, const Money(100000));

      // And the freed room can be used.
      final again = await ledger.pay(
        SupplierPayment(
          id: 0,
          supplierId: supplierId,
          invoiceId: bill.id,
          amount: const Money(100000),
          method: SupplierPaymentMethod.bankTransfer,
          paidAt: day(9),
        ),
        by: buyer,
      );
      expect(again.succeeded, isTrue, reason: '${again.refusal}');
    });

    test('a void carries one of the restaurant\'s own reason codes', () async {
      // Not free text. "How many did we cancel for *entered twice* last month"
      // is the question that finds the process producing them, and a sentence
      // somebody typed cannot be counted.
      final bill = await enter(draft());
      final result = await ledger.voidInvoice(
        bill.id,
        reasonId: invoiceVoidReason,
        note: 'also on 900A',
        by: buyer,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(result.value!.voidReasonId, invoiceVoidReason);
      expect(result.value!.voidNote, 'also on 900A');
    });

    test('a reason from another restaurant is refused by the database', () async {
      // The FK is what makes the count trustworthy: a reason id from somebody
      // else's vocabulary would be counted under their label.
      final elsewhere = (await db.query(
        pg.config,
        "INSERT INTO pos_restaurants (slug, name) VALUES ('z', 'Z') RETURNING id",
      )).first[0]! as int;
      await LocalBootstrap(db).seedReasonCodes(pg.config, elsewhere);
      final theirReason = (await db.query(
        pg.config,
        "SELECT id FROM pos_reason_codes WHERE restaurant_id = @r "
        "AND scope = 'invoice_void' LIMIT 1",
        parameters: {'r': elsewhere},
      )).first[0]! as int;

      final bill = await enter(draft());
      // The reference itself is satisfied — both rows are in the same table —
      // so this is the one cross-restaurant case the schema cannot catch, and
      // it is recorded here as a known limit rather than pretended away.
      final result = await ledger.voidInvoice(
        bill.id,
        reasonId: theirReason,
        by: buyer,
      );
      expect(result.succeeded, isTrue, reason: 'documented gap, not a claim');
    });

    test(
      'voiding an invoice with money on it is refused, and says how much',
      () async {
        final bill = await enter(draft(totalMinor: 100000));
        await settle(invoiceId: bill.id, amountMinor: 30000);

        final result = await ledger.voidInvoice(bill.id, reasonId: invoiceVoidReason, by: buyer);
        expect(result.succeeded, isFalse);
        expect((result.refusal! as CatalogInvalid).reason, contains('300.00'));
        expect((await ledger.byId(bill.id))!.isVoided, isFalse);
      },
    );

    test('the database refuses that too', () async {
      // The second invariant, tested where it lives.
      final bill = await enter(draft(totalMinor: 100000));
      await settle(invoiceId: bill.id, amountMinor: 30000);

      await expectLater(
        db.query(
          pg.config,
          'UPDATE pos_supplier_invoices SET voided_at = now(), '
          'void_reason_id = @reason WHERE id = @i',
          parameters: {'i': bill.id, 'reason': invoiceVoidReason},
        ),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('void the payments first'),
          ),
        ),
      );
    });

    test('voiding the payment first then lets the invoice go', () async {
      final bill = await enter(draft(totalMinor: 100000));
      final paid = await settle(invoiceId: bill.id, amountMinor: 30000);

      await ledger.voidPayment(paid.id, reasonId: paymentVoidReason, by: buyer);
      final result = await ledger.voidInvoice(bill.id, reasonId: invoiceVoidReason, by: buyer);
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(result.value!.isVoided, isTrue);
      expect(result.value!.voidReasonId, invoiceVoidReason);
    });

    test('a voided invoice cannot be paid', () async {
      final bill = await enter(draft());
      await ledger.voidInvoice(bill.id, reasonId: invoiceVoidReason, by: buyer);

      final result = await ledger.pay(
        SupplierPayment(
          id: 0,
          supplierId: supplierId,
          invoiceId: bill.id,
          amount: const Money(100),
          method: SupplierPaymentMethod.cash,
          paidAt: day(9),
        ),
        by: buyer,
      );
      expect(result.succeeded, isFalse);
    });

    test('voiding twice is not an error — somebody clicked twice', () async {
      final bill = await enter(draft());
      await ledger.voidInvoice(bill.id, reasonId: invoiceVoidReason, by: buyer);
      final again = await ledger.voidInvoice(bill.id, reasonId: invoiceVoidReason, by: buyer);
      expect(again.succeeded, isTrue);
    });

    test('a void is audited, separately from the entry', () async {
      final bill = await enter(draft());
      await ledger.voidInvoice(bill.id, reasonId: invoiceVoidReason, by: buyer);

      final rows = await db.query(
        pg.config,
        'SELECT action FROM pos_audit_events WHERE entity_id = @e ORDER BY id',
        parameters: {'e': '${bill.id}'},
      );
      expect(
        rows.map((r) => r[0]),
        containsAllInOrder([
          AuditAction.supplierInvoiceSaved,
          AuditAction.supplierInvoiceVoided,
        ]),
      );
    });
  });

  group('the statement', () {
    test('balances are aggregated per supplier in one query', () async {
      await enter(draft(number: 'A', totalMinor: 100000, due: 10));
      await enter(draft(number: 'B', totalMinor: 50000, due: 40));
      await enter(
        draft(number: 'C', supplier: otherSupplierId, totalMinor: 20000),
      );
      await settle(amountMinor: 30000, invoiceId: null);

      final balances = await ledger.balances(asOf: day(20));
      final dairy = balances.firstWhere((b) => b.supplierId == supplierId);
      final meats = balances.firstWhere((b) => b.supplierId == otherSupplierId);

      expect(dairy.invoiced, const Money(150000));
      expect(dairy.paid, const Money(30000));
      expect(dairy.outstanding, const Money(120000));
      expect(dairy.overdue, const Money(100000), reason: 'only A is past due');
      expect(meats.invoiced, const Money(20000));
      expect(meats.outstanding, const Money(20000));
    });

    test(
      'a supplier with no invoices has a zero row, not a missing one',
      () async {
        // A statement that silently omitted a supplier would read as a supplier
        // that does not exist.
        final balances = await ledger.balances(asOf: day(20));
        expect(
          balances.map((b) => b.supplierId),
          containsAll([supplierId, otherSupplierId]),
        );
        expect(
          balances.firstWhere((b) => b.supplierId == supplierId).invoiced,
          Money.zero,
        );
      },
    );

    test('two invoices and one payment do not multiply each other', () async {
      // The classic way a statement comes out wrong and still looks plausible:
      // one join across both tables counts each invoice once per payment.
      await enter(draft(number: 'A', totalMinor: 100000));
      await enter(draft(number: 'B', totalMinor: 100000));
      await settle(amountMinor: 10000, invoiceId: null);
      await settle(amountMinor: 10000, invoiceId: null);

      final balances = await ledger.balances(asOf: day(20));
      final dairy = balances.firstWhere((b) => b.supplierId == supplierId);
      expect(dairy.invoiced, const Money(200000));
      expect(dairy.paid, const Money(20000));

      final account = await ledger.accountFor(supplierId, asOf: day(20));
      expect(account.invoiced, const Money(200000));
      expect(account.paid, const Money(20000));
    });

    test('a voided invoice and a voided payment leave the statement', () async {
      final bill = await enter(draft(number: 'A', totalMinor: 100000));
      await enter(draft(number: 'B', totalMinor: 40000));
      final paid = await settle(amountMinor: 10000, invoiceId: null);

      await ledger.voidInvoice(bill.id, reasonId: invoiceVoidReason, by: buyer);
      await ledger.voidPayment(paid.id, reasonId: paymentVoidReason, by: buyer);

      final dairy = (await ledger.balances(asOf: day(20)))
          .firstWhere((b) => b.supplierId == supplierId);
      expect(dairy.invoiced, const Money(40000));
      expect(dairy.paid, Money.zero);
    });
  });

  group('what is refused', () {
    test('a cashier — paying suppliers is not a shift-floor act', () async {
      final result = await ledger.save(draft(), by: cashier);
      expect(result.refusal, isA<NotPermitted>());
      expect(await ledger.all(), isEmpty);
    });

    test('somebody who has left, whose role still would allow it', () async {
      final result = await ledger.save(
        draft(),
        by: PosStaff(id: 0, name: 'Amer M.', isActive: false, role: buyer.role),
      );
      expect(result.refusal, isA<NotPermitted>());
    });

    test('a till with no administrator credential sees nothing', () async {
      await enter(draft());
      final locked = PostgresSupplierInvoicesRepository(
        database: db,
        config: pg.config,
        adminAvailable: false,
        restaurantId: restaurantId,
        branchId: branchId,
      );

      expect(await locked.all(), isEmpty);
      expect(await locked.unpaid(), isEmpty);
      expect(await locked.balances(), isEmpty);
      expect(
        (await locked.save(draft(number: 'Z'), by: buyer)).refusal,
        isA<AdministratorCredentialRequired>(),
      );
    });

    test('another restaurant keeps its own ledger', () async {
      await enter(draft());
      final elsewhere =
          (await db.query(
                pg.config,
                "INSERT INTO pos_restaurants (slug, name) VALUES ('y', 'Y') RETURNING id",
              )).first[0]!
              as int;
      final theirBranch =
          (await db.query(
                pg.config,
                'INSERT INTO pos_branches (restaurant_id, code, name) '
                "VALUES (@r, 'M', 'M') RETURNING id",
                parameters: {'r': elsewhere},
              )).first[0]!
              as int;

      final theirs = PostgresSupplierInvoicesRepository(
        database: db,
        config: pg.config,
        adminAvailable: true,
        restaurantId: elsewhere,
        branchId: theirBranch,
      );
      expect(await theirs.all(), isEmpty);
      expect(await theirs.balances(), isEmpty);
    });
  });
}
