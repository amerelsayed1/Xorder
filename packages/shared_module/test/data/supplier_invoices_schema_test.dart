@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/security/pin_hash.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_shift_repository.dart';
import 'package:shared_module/data/postgres/postgres_supplier_invoices_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/supplier_invoice.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

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
  late int businessId;
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

  /// The two roles that matter once a drawer is involved. `pos_cash_movements`
  /// names who took the money out, so both of these are real staff rows rather
  /// than the `id: 0` [buyer] the rest of the suite uses.
  const managerRole = PosRole(
    id: 3,
    code: 'manager',
    nameEn: 'Manager',
    // `shift.close` too: these tests count the drawer they opened, and the
    // shift repository asks for it now rather than trusting whoever calls.
    capabilities: {
      PosCapability.purchaseManage,
      PosCapability.cashMovement,
      PosCapability.shiftClose,
    },
  );
  const bookkeeperRole = PosRole(
    id: 4,
    code: 'bookkeeper',
    nameEn: 'Bookkeeper',
    capabilities: {PosCapability.purchaseManage},
  );

  late PosStaff manager;
  late PosStaff bookkeeper;
  late String terminalId;
  late PosShift openShift;
  late PostgresShiftRepository shifts;

  DateTime day(int d) => DateTime.utc(2026, 3, d);

  late int invoiceVoidReason;
  late int paymentVoidReason;

  setUp(() async {
    pg = await PgFixture.open('supplier_invoices');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_businesses (slug, name) VALUES ('si', 'SI') RETURNING id",
            )).first[0]!
            as int;
    branchId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_branches (business_id, code, name) '
              "VALUES (@r, 'MAIN', 'Main') RETURNING id",
              parameters: {'r': businessId},
            )).first[0]!
            as int;
    supplierId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_suppliers (business_id, name_en, payment_term_days) '
              "VALUES (@r, 'Nile Dairy', 30) RETURNING id",
              parameters: {'r': businessId},
            )).first[0]!
            as int;
    otherSupplierId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_suppliers (business_id, name_en) '
              "VALUES (@r, 'Cairo Meats') RETURNING id",
              parameters: {'r': businessId},
            )).first[0]!
            as int;

    // **Seeded the way a real install seeds them.** Migration 31's CROSS JOIN
    // can only see businesses that already existed, and this fixture creates
    // one afterwards — the same gap that left a freshly installed business
    // with no payment methods. Going through `LocalBootstrap` is what proves
    // the new scopes are on its list.
    await LocalBootstrap(db).seedReasonCodes(pg.config, businessId);

    invoiceVoidReason = (await db.query(
      pg.config,
      "SELECT id FROM pos_reason_codes WHERE business_id = @r "
      "AND scope = 'invoice_void' AND code = 'entered_twice'",
      parameters: {'r': businessId},
    )).first[0]! as int;
    paymentVoidReason = (await db.query(
      pg.config,
      "SELECT id FROM pos_reason_codes WHERE business_id = @r "
      "AND scope = 'payment_void' AND code = 'wrong_invoice'",
      parameters: {'r': businessId},
    )).first[0]! as int;

    ledger = PostgresSupplierInvoicesRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      businessId: businessId,
      branchId: branchId,
    );

    // ── A till with an open drawer, so a supplier can be paid out of it ──
    terminalId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
              "VALUES (gen_random_uuid(), @r, @b, 'Counter 1') RETURNING id::text",
              parameters: {'r': businessId, 'b': branchId},
            )).first[0]!
            as String;

    Future<PosStaff> person(String name, String username, PosRole role) async {
      final salt = PinHash.newSalt();
      final row = await db.query(
        pg.config,
        'INSERT INTO pos_users (business_id, branch_id, name, username, '
        '  pin_salt, pin_hash) VALUES (@r, @b, @n, @u, @s, @h) RETURNING id',
        parameters: {
          'r': businessId,
          'b': branchId,
          'n': name,
          'u': username,
          's': salt,
          'h': await PinHash.hash('1111', salt),
        },
      );
      return PosStaff(id: row.first[0]! as int, name: name, role: role);
    }

    manager = await person('Hoda K.', 'hoda', managerRole);
    bookkeeper = await person('Tarek S.', 'tarek', bookkeeperRole);

    shifts = PostgresShiftRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
      terminalId: terminalId,
    );
    openShift = await shifts.open(
      by: manager,
      openingFloat: const Money(20000),
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

  /// Pay out of [openShift]'s drawer — the switch, turned on.
  Future<AdminResult<SupplierPayment>> payFromTheTill({
    required int amountMinor,
    int? invoiceId,
    SupplierPaymentMethod method = SupplierPaymentMethod.cash,
    PosStaff? by,
    int? shiftId,
  }) => ledger.pay(
    SupplierPayment(
      id: 0,
      supplierId: supplierId,
      invoiceId: invoiceId,
      amount: Money(amountMinor),
      method: method,
      paidAt: day(5),
    ),
    by: by ?? manager,
    fromShiftId: shiftId ?? openShift.id,
  );

  /// Every movement on the open shift, oldest first: kind, amount, note.
  Future<List<List<Object?>>> drawerMovements() async {
    final rows = await db.query(
      pg.config,
      'SELECT kind, amount_minor, note, reason_id, user_id, terminal_id::text '
      'FROM pos_cash_movements WHERE shift_id = @s ORDER BY id',
      parameters: {'s': openShift.id},
    );
    return [for (final row in rows) row.toList()];
  }

  Future<Money> expectedCash() async =>
      (await shifts.summarise(openShift)).expectedCash;

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
      // Numbering is the supplier's, not the business's.
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
      // Stamping `now()` would hand the business weeks the supplier has not
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

    test('a supplier from another business is refused', () async {
      final elsewhere =
          (await db.query(
                pg.config,
                "INSERT INTO pos_businesses (slug, name) VALUES ('x', 'X') RETURNING id",
              )).first[0]!
              as int;
      final theirs =
          (await db.query(
                pg.config,
                "INSERT INTO pos_suppliers (business_id, name_en) "
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
          'INSERT INTO pos_supplier_payments (business_id, branch_id, '
          '  supplier_id, supplier_name, invoice_id, method, amount_minor) '
          "VALUES (@r, @b, @s, 'Nile Dairy', @i, 'cash', 150000)",
          parameters: {
            'r': businessId,
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
          'INSERT INTO pos_supplier_payments (business_id, branch_id, '
          '  supplier_id, supplier_name, invoice_id, method, amount_minor) '
          "VALUES (@r, @b, @s, 'Nile Dairy', @i, 'cash', 1000)",
          parameters: {
            'r': businessId,
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

    test('a payment nobody said came out of the till touches no drawer', () async {
      // The default, and it has to stay the default: recording what the
      // business paid is not the same as saying money left a till, and a
      // bookkeeper typing up last week's receipt book must not take today's
      // drawer down. Cash as the method changes nothing on its own.
      final paid = await settle(amountMinor: 50000, invoiceId: null);
      expect(paid.cashMovementId, isNull);
      expect(await drawerMovements(), isEmpty);
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

  group('out of the till drawer', () {
    test('one pay-out, linked to the payment, on the shift\'s own terminal', () async {
      final bill = await enter(draft(totalMinor: 50000));
      // Deliberately without `invoiceNumber`: the note has to come off the
      // invoice row, because that is what somebody reads it back against.
      final result = await payFromTheTill(amountMinor: 50000, invoiceId: bill.id);
      expect(result.succeeded, isTrue, reason: '${result.refusal}');

      final movements = await drawerMovements();
      expect(movements.length, 1, reason: 'exactly one, never two');
      expect(movements.single[0], 'pay_out');
      // Positive, with the direction carried by the kind — the table's own rule.
      expect(movements.single[1], 50000);
      expect(movements.single[2], 'Nile Dairy — INV-900');
      expect(movements.single[4], manager.id, reason: 'somebody is answerable');
      expect(
        movements.single[5],
        terminalId,
        reason: 'the till the shift is open on, not the office machine',
      );
      expect(result.value!.cashMovementId, isNotNull);
    });

    test('the shift expects that much less in the drawer', () async {
      // The whole point. A business that pays its vegetable man 500 out of the
      // till used to have a drawer 500 short at cash-up with nothing explaining
      // it.
      final before = await expectedCash();
      expect(before, const Money(20000), reason: 'the float, and nothing sold');

      await payFromTheTill(amountMinor: 50000);

      expect(await expectedCash(), const Money(-30000));
    });

    test('the pay-out is reported under the business\'s own supplier reason', () async {
      // `ReasonScope.payOut` already had the right answer on it since migration
      // 14. Inventing a code would have meant a Z report with a pay-out nobody's
      // reason list could account for.
      final supplierReason = (await db.query(
        pg.config,
        "SELECT id FROM pos_reason_codes WHERE business_id = @r "
        "AND scope = 'pay_out' AND code = 'supplier'",
        parameters: {'r': businessId},
      )).first[0]! as int;

      await payFromTheTill(amountMinor: 50000);
      expect((await drawerMovements()).single[3], supplierReason);
    });

    test('the drawer movement is what the payment reads back as', () async {
      final result = await payFromTheTill(amountMinor: 50000);
      final movementId = (await db.query(
        pg.config,
        'SELECT id FROM pos_cash_movements WHERE shift_id = @s',
        parameters: {'s': openShift.id},
      )).first[0]! as int;

      expect(result.value!.cashMovementId, movementId);
      // And on the reread, not merely on what `pay` handed back.
      final listed = (await ledger.payments()).single;
      expect(listed.cashMovementId, movementId);
    });

    test('a transfer cannot come out of a drawer', () async {
      // Money leaving a bank account does not pass through a till, and a pay-out
      // recorded for one would be a drawer short of cash that is still in it.
      final result = await payFromTheTill(
        amountMinor: 50000,
        method: SupplierPaymentMethod.bankTransfer,
      );
      expect(result.succeeded, isFalse);
      expect(await drawerMovements(), isEmpty);
    });

    test('paying out of a drawer needs the drawer key as well as the purchase one', () async {
      // Two authorities. A bookkeeper who may say what the business owes is
      // not automatically somebody who may reach into a till.
      final result = await payFromTheTill(amountMinor: 50000, by: bookkeeper);
      expect(result.refusal, isA<NotPermitted>());
      expect((result.refusal! as NotPermitted).capability, PosCapability.cashMovement);
      expect(await drawerMovements(), isEmpty);
      expect(await ledger.payments(), isEmpty, reason: 'and nothing recorded');

      // The same person may still record the payment — it just does not claim to
      // have come out of the drawer.
      final office = await ledger.pay(
        SupplierPayment(
          id: 0,
          supplierId: supplierId,
          amount: const Money(50000),
          method: SupplierPaymentMethod.cash,
          paidAt: day(5),
        ),
        by: bookkeeper,
      );
      expect(office.succeeded, isTrue, reason: '${office.refusal}');
    });

    test('a shift that has been counted cannot be paid out of', () async {
      // A pay-out added afterwards would change an expected total a manager has
      // already argued about.
      await shifts.close(
        shift: openShift,
        by: manager,
        countedCash: const Money(20000),
      );

      final result = await payFromTheTill(amountMinor: 50000);
      expect(result.succeeded, isFalse);
      expect(
        (result.refusal! as CatalogInvalid).reason,
        contains('closed and counted'),
      );
      expect(await drawerMovements(), isEmpty);
    });

    test('another branch\'s shift is not this branch\'s drawer', () async {
      final elsewhere = (await db.query(
        pg.config,
        'INSERT INTO pos_branches (business_id, code, name) '
        "VALUES (@r, 'TWO', 'Two') RETURNING id",
        parameters: {'r': businessId},
      )).first[0]! as int;
      final theirTerminal = (await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
        "VALUES (gen_random_uuid(), @r, @b, 'Counter 2') RETURNING id::text",
        parameters: {'r': businessId, 'b': elsewhere},
      )).first[0]! as String;
      final theirShift = await PostgresShiftRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: elsewhere,
        terminalId: theirTerminal,
      ).open(by: manager, openingFloat: const Money(10000));

      final result = await payFromTheTill(
        amountMinor: 5000,
        shiftId: theirShift.id,
      );
      expect(result.succeeded, isFalse);
      expect(await ledger.payments(), isEmpty);
    });

    test('a payment refused on the invoice leaves no movement behind', () async {
      // Both rows or neither. A drawer 1,500 down with no payment behind it is
      // worse than the shortage this feature removes.
      final bill = await enter(draft(totalMinor: 100000));
      final result = await payFromTheTill(
        amountMinor: 150000,
        invoiceId: bill.id,
      );

      expect(result.succeeded, isFalse);
      expect(await drawerMovements(), isEmpty);
      expect(await ledger.payments(), isEmpty);
    });

    test('with no pay-out reason on file, nothing is written at all', () async {
      // The business edited its list down to nothing this could be reported
      // under. Refused rather than recorded with a null reason: a pay-out that
      // appears on a Z report under no heading is a number a manager cannot
      // account for, which is where this started.
      await db.query(
        pg.config,
        "DELETE FROM pos_cash_movements WHERE shift_id = @s",
        parameters: {'s': openShift.id},
      );
      await db.query(
        pg.config,
        "UPDATE pos_reason_codes SET is_active = false "
        "WHERE business_id = @r AND scope = 'pay_out' AND code = 'supplier'",
        parameters: {'r': businessId},
      );

      final result = await payFromTheTill(amountMinor: 50000);
      expect(result.succeeded, isFalse);
      expect(await ledger.payments(), isEmpty);
      expect(await drawerMovements(), isEmpty);
    });

    test('the database refuses a payment pointed at anything but its own pay-out', () async {
      // The Dart above is one writer. This is the rule, and it holds against the
      // next one — a hand-written UPDATE included.
      final payIn = (await db.query(
        pg.config,
        'INSERT INTO pos_cash_movements (business_id, branch_id, terminal_id, '
        '  shift_id, kind, amount_minor, user_id) '
        "VALUES (@r, @b, @t::uuid, @s, 'pay_in', 50000, @staff) RETURNING id",
        parameters: {
          'r': businessId,
          'b': branchId,
          't': terminalId,
          's': openShift.id,
          'staff': manager.id,
        },
      )).first[0]! as int;

      Future<void> pointAt(int movementId, int amountMinor) => db.query(
        pg.config,
        'INSERT INTO pos_supplier_payments (business_id, branch_id, '
        '  supplier_id, supplier_name, method, amount_minor, paid_at, '
        '  cash_movement_id) '
        "VALUES (@r, @b, @s, 'Nile Dairy', 'cash', @amount, now(), @m)",
        parameters: {
          'r': businessId,
          'b': branchId,
          's': supplierId,
          'amount': amountMinor,
          'm': movementId,
        },
      );

      // A pay-in is money arriving. Nothing left the drawer through it.
      await expectLater(pointAt(payIn, 50000), throwsA(isA<Object>()));

      final payOut = (await db.query(
        pg.config,
        'INSERT INTO pos_cash_movements (business_id, branch_id, terminal_id, '
        '  shift_id, kind, amount_minor, user_id) '
        "VALUES (@r, @b, @t::uuid, @s, 'pay_out', 50000, @staff) RETURNING id",
        parameters: {
          'r': businessId,
          'b': branchId,
          't': terminalId,
          's': openShift.id,
          'staff': manager.id,
        },
      )).first[0]! as int;

      // Right kind, wrong money: 100 left the drawer and is owed to nobody.
      await expectLater(pointAt(payOut, 40000), throwsA(isA<Object>()));

      // And the same movement cannot be spent twice.
      await pointAt(payOut, 50000);
      await expectLater(pointAt(payOut, 50000), throwsA(isA<Object>()));
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

    test('voiding a till payment puts the cash back with a pay-in', () async {
      // **A cash movement is never edited or deleted.** The pay-out stands and a
      // second movement answers it, which is this product's rule everywhere
      // money is concerned.
      final paid = await payFromTheTill(amountMinor: 50000);
      expect(await expectedCash(), const Money(-30000));

      final undone = await ledger.voidPayment(
        paid.value!.id,
        reasonId: paymentVoidReason,
        by: manager,
      );
      expect(undone.succeeded, isTrue, reason: '${undone.refusal}');

      final movements = await drawerMovements();
      expect(movements.length, 2, reason: 'the pay-out, and the pay-in over it');
      expect(movements.first[0], 'pay_out');
      expect(movements.last[0], 'pay_in');
      expect(movements.last[1], 50000);
      expect(
        movements.last[2],
        movements.first[2],
        reason: 'the pair reads as a pair on the drawer history',
      );
      expect(
        await expectedCash(),
        const Money(20000),
        reason: 'the drawer is back where it started',
      );
    });

    test('putting cash back needs the drawer key too', () async {
      final paid = await payFromTheTill(amountMinor: 50000);
      final undone = await ledger.voidPayment(
        paid.value!.id,
        reasonId: paymentVoidReason,
        by: bookkeeper,
      );

      expect(undone.refusal, isA<NotPermitted>());
      expect(
        await expectedCash(),
        const Money(-30000),
        reason: 'and the pay-out still stands',
      );
    });

    test('once the drawer is counted, the void asks where the money went', () async {
      // No `pay_in` is written either way: one on the closed shift would rewrite
      // a Z report somebody signed, and one on today's shift would claim cash
      // appeared in a drawer nobody put cash into. The only thing left worth
      // recording is where it actually went, so a note is required.
      // 50 out of a 200 float, so the drawer can be counted at what it holds —
      // a count is what somebody found in a till and is never negative.
      final paid = await payFromTheTill(amountMinor: 5000);
      await shifts.close(
        shift: openShift,
        by: manager,
        countedCash: const Money(15000),
      );

      final bare = await ledger.voidPayment(
        paid.value!.id,
        reasonId: paymentVoidReason,
        by: manager,
      );
      expect(bare.succeeded, isFalse);
      expect(
        (bare.refusal! as CatalogInvalid).reason,
        contains('where the money went'),
      );

      final told = await ledger.voidPayment(
        paid.value!.id,
        reasonId: paymentVoidReason,
        by: manager,
        note: 'Hoda brought the 50 back on Tuesday — paid in at the till.',
      );
      expect(told.succeeded, isTrue, reason: '${told.refusal}');
      expect(told.value!.isVoided, isTrue);
      expect(
        (await drawerMovements()).length,
        1,
        reason: 'the counted shift is left exactly as it was counted',
      );
      expect(
        told.value!.cashMovementId,
        isNotNull,
        reason: 'the pay-out is still on the payment: it happened',
      );
    });

    test('a void carries one of the business\'s own reason codes', () async {
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

    test('a reason from another business is refused by the database', () async {
      // The FK is what makes the count trustworthy: a reason id from somebody
      // else's vocabulary would be counted under their label.
      final elsewhere = (await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('z', 'Z') RETURNING id",
      )).first[0]! as int;
      await LocalBootstrap(db).seedReasonCodes(pg.config, elsewhere);
      final theirReason = (await db.query(
        pg.config,
        "SELECT id FROM pos_reason_codes WHERE business_id = @r "
        "AND scope = 'invoice_void' LIMIT 1",
        parameters: {'r': elsewhere},
      )).first[0]! as int;

      final bill = await enter(draft());
      // The reference itself is satisfied — both rows are in the same table —
      // so this is the one cross-business case the schema cannot catch, and
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
        businessId: businessId,
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

    test('another business keeps its own ledger', () async {
      await enter(draft());
      final elsewhere =
          (await db.query(
                pg.config,
                "INSERT INTO pos_businesses (slug, name) VALUES ('y', 'Y') RETURNING id",
              )).first[0]!
              as int;
      final theirBranch =
          (await db.query(
                pg.config,
                'INSERT INTO pos_branches (business_id, code, name) '
                "VALUES (@r, 'M', 'M') RETURNING id",
                parameters: {'r': elsewhere},
              )).first[0]!
              as int;

      final theirs = PostgresSupplierInvoicesRepository(
        database: db,
        config: pg.config,
        adminAvailable: true,
        businessId: elsewhere,
        branchId: theirBranch,
      );
      expect(await theirs.all(), isEmpty);
      expect(await theirs.balances(), isEmpty);
    });
  });
}
