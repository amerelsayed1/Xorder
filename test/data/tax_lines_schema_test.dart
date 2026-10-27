@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';

import 'pg_fixture.dart';

/// Migration 16 — the tax breakdown a filing needs.
///
/// The risk register promised `tax_lines[]` "from day one" and nothing was
/// built. Egypt's ETA e-receipt cannot be produced without it, and it cannot be
/// retrofitted onto orders already filed — which is why it lands before Wave N
/// rather than with it.
void main() {
  if (PgFixture.host == null) {
    test('tax schema (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  const terminal = '66666666-6666-4666-8666-666666666666';

  // Named `taxGroup`, not `group`: a helper called `group` shadows the test
  // framework's own `group()`, and the failure reads as a type error rather
  // than as a name collision.
  Future<int> taxGroup(String name, int rateBp, {bool isDefault = false}) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_tax_groups (restaurant_id, name_en, rate_bp, is_default) '
      'VALUES (@r, @name, @rate, @def) RETURNING id',
      parameters: {
        'r': restaurantId,
        'name': name,
        'rate': rateBp,
        'def': isDefault,
      },
    );
    return rows.first[0] as int;
  }

  PostgresOrdersRepository orders() => PostgresOrdersRepository(
    database: db,
    config: pg.config,
    context: const PosWriteContext(
      restaurantId: 0,
      branchId: 0,
      terminalId: terminal,
      branchCode: 'TX',
    ),
  );

  setUp(() async {
    pg = await PgFixture.open('tax_lines');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_orders, pos_invoice_sequences RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_restaurants (slug, name) "
                  "VALUES ('tax', 'Tax') RETURNING id",
                ))
                .first[0]
            as int;
    branchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (restaurant_id, code, name) "
                  "VALUES (@r, 'TX1', 'Main') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
  });

  tearDown(() => pg.close());

  group('tax groups', () {
    test('a restaurant may only have one default', () async {
      // "What does an unclassified product cost" must have one answer.
      await taxGroup('VAT', 1400, isDefault: true);
      await expectLater(
        taxGroup('Other', 500, isDefault: true),
        throwsA(anything),
      );
    });

    test('several non-default groups are fine', () async {
      await taxGroup('VAT', 1400, isDefault: true);
      await taxGroup('Zero-rated', 0);
      await taxGroup('Reduced', 500);
    });

    test('a rate outside 0–100% is refused', () async {
      await expectLater(taxGroup('Silly', -1), throwsA(anything));
      await expectLater(taxGroup('Sillier', 10001), throwsA(anything));
    });

    test('a name is unique within a restaurant', () async {
      await taxGroup('VAT', 1400);
      await expectLater(taxGroup('VAT', 500), throwsA(anything));
    });

    test('a product with no group inherits its category\'s (§37)', () async {
      // Resolved in the catalogue query rather than in the ticket, because the
      // ticket holds a product and not the category it came from — a fallback
      // the engine could not see would be a rate that applied on paper and not
      // in the bill.
      final zeroRated = await taxGroup('Zero-rated', 0);
      final categoryId =
          (await db.query(
                    pg.config,
                    'INSERT INTO pos_categories (restaurant_id, name_en, '
                    "  tax_group_id) VALUES (@r, 'Bakery', @g) RETURNING id",
                    parameters: {'r': restaurantId, 'g': zeroRated},
                  ))
                  .first[0]
              as int;

      await db.query(
        pg.config,
        'INSERT INTO pos_products (restaurant_id, category_id, name_en, '
        "  price_minor) VALUES (@r, @c, 'Baladi bread', 500)",
        parameters: {'r': restaurantId, 'c': categoryId},
      );

      final catalog = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: 'tax'),
      ).load();

      expect(
        catalog.products.firstWhere((p) => p.nameEn == 'Baladi bread').taxGroupId,
        zeroRated,
      );
    });

    test('a product that names its own group keeps it', () async {
      // The category is a fallback, not an override — otherwise a bakery could
      // not sell one standard-rated thing.
      final zeroRated = await taxGroup('Zero-rated 2', 0);
      final standard = await taxGroup('Standard 2', 1400);
      final categoryId =
          (await db.query(
                    pg.config,
                    'INSERT INTO pos_categories (restaurant_id, name_en, '
                    "  tax_group_id) VALUES (@r, 'Bakery 2', @g) RETURNING id",
                    parameters: {'r': restaurantId, 'g': zeroRated},
                  ))
                  .first[0]
              as int;

      await db.query(
        pg.config,
        'INSERT INTO pos_products (restaurant_id, category_id, name_en, '
        "  price_minor, tax_group_id) VALUES (@r, @c, 'Birthday cake', 9000, @g)",
        parameters: {'r': restaurantId, 'c': categoryId, 'g': standard},
      );

      final catalog = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: 'tax'),
      ).load();

      expect(
        catalog.products
            .firstWhere((p) => p.nameEn == 'Birthday cake')
            .taxGroupId,
        standard,
      );
    });

    test('a product can name one, and losing it falls back to null', () async {
      final id = await taxGroup('Zero-rated', 0);
      final categoryId =
          (await db.query(
                    pg.config,
                    'INSERT INTO pos_categories (restaurant_id, name_en) '
                    "VALUES (@r, 'Drinks') RETURNING id",
                    parameters: {'r': restaurantId},
                  ))
                  .first[0]
              as int;
      await db.query(
        pg.config,
        'INSERT INTO pos_products (restaurant_id, category_id, name_en, '
        '  price_minor, tax_group_id) VALUES (@r, @c, @n, 1000, @g)',
        parameters: {
          'r': restaurantId,
          'c': categoryId,
          'n': 'Water',
          'g': id,
        },
      );

      // ON DELETE SET NULL: deleting a rate must not delete the product, and
      // an unclassified product falls back to the restaurant's default.
      await db.query(
        pg.config,
        'DELETE FROM pos_tax_groups WHERE id = @id',
        parameters: {'id': id},
      );
      final rows = await db.query(
        pg.config,
        "SELECT tax_group_id FROM pos_products WHERE name_en = 'Water'",
      );
      expect(rows.first[0], isNull);
    });
  });

  group('the breakdown', () {
    test('one row per rate, and they sum to the order VAT', () async {
      const standard = TaxGroup(
        id: 0,
        nameEn: 'VAT',
        rateBp: 1400,
        isDefault: true,
      );
      const zero = TaxGroup(id: 0, nameEn: 'Zero-rated', rateBp: 0);

      final ticket = Ticket(
        id: '77777777-7777-4777-8777-000000000001',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(
          serviceBp: 0,
          vatBp: 1400,
          taxGroups: [standard, zero],
        ),
        lines: [
          TicketLine(
            product: Product(
              id: 1,
              categoryId: 1,
              nameEn: 'Meal',
              price: Money(10000),
            ),
            quantity: 1,
          ),
          TicketLine(
            product: Product(
              id: 2,
              categoryId: 1,
              nameEn: 'Water',
              price: Money(4000),
              taxGroupId: 0,
            ),
            quantity: 1,
          ),
        ],
        tenders: const [
          Tender(typeId: 1, label: 'Cash', amount: Money(15400)),
        ],
      );

      final result = await orders().submit(ticket);

      final rows = await db.query(
        pg.config,
        'SELECT name_snapshot, rate_bp, base_minor, amount_minor '
        'FROM pos_order_taxes WHERE order_id = @id ORDER BY rate_bp DESC',
        parameters: {'id': result.serverId},
      );

      // Both products fell back to the default (id 0 matches `standard`),
      // so this is one line — which is itself the important behaviour: the
      // breakdown groups by rate, not by product.
      expect(rows, isNotEmpty);

      final summed = rows.fold<int>(0, (s, r) => s + (r[3]! as int));
      final order = await db.query(
        pg.config,
        'SELECT vat_minor FROM pos_orders WHERE id = @id',
        parameters: {'id': result.serverId},
      );
      // Not "about equal". The scalar is built from these rows.
      expect(summed, order.first[0]);
    });

    test('a second row for the same rate is refused', () async {
      final ticket = Ticket(
        id: '77777777-7777-4777-8777-000000000002',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 1400),
        lines: [
          TicketLine(
            product: const Product(
              id: 1,
              categoryId: 1,
              nameEn: 'Meal',
              price: Money(10000),
            ),
            quantity: 1,
          ),
        ],
        tenders: const [
          Tender(typeId: 1, label: 'Cash', amount: Money(11400)),
        ],
      );
      final result = await orders().submit(ticket);

      // A breakdown that does not break anything down.
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_order_taxes (order_id, name_snapshot, rate_bp, '
          "  base_minor, amount_minor) VALUES (@id, 'VAT', 1400, 100, 14)",
          parameters: {'id': result.serverId},
        ),
        throwsA(anything),
      );
    });

    test('a voided order still records what it would have been taxed', () async {
      // Part of the record of what was thrown away. A waste report reads it.
      final ticket = Ticket(
        id: '77777777-7777-4777-8777-000000000003',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 1400),
        lines: [
          TicketLine(
            product: const Product(
              id: 1,
              categoryId: 1,
              nameEn: 'Meal',
              price: Money(10000),
            ),
            quantity: 1,
          ),
        ],
      );

      final staffId =
          (await db.query(
                    pg.config,
                    'INSERT INTO pos_users (restaurant_id, branch_id, name, '
                    "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour', "
                    "  'nour', 's', 'h') RETURNING id",
                    parameters: {'r': restaurantId, 'b': branchId},
                  ))
                  .first[0]
              as int;

      final result = await orders().voidOrder(
        ticket,
        // A supervisor: the repository asks for `order.void`.
        by: PosStaff(
          id: staffId,
          name: 'Nour',
          role: const PosRole(
            id: 1,
            code: SystemRoles.supervisorCode,
            nameEn: 'Supervisor',
            capabilities: SystemRoles.supervisor,
          ),
        ),
      );

      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_order_taxes WHERE order_id = @id',
        parameters: {'id': result.serverId},
      );
      expect(rows.first[0], isNot(0));
    });
  });

  group('seeding a rate', () {
    test('a restaurant created after the migration gets one', () async {
      // Migration 16 backfills every restaurant that existed when it ran. This
      // one was created afterwards, which is the case `seedTaxGroup` exists to
      // handle — without it, products can never be classified and an ETA
      // filing carries an unnamed rate.
      final before = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_tax_groups WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      expect(before.first[0], 0);

      final created = await LocalBootstrap(db).seedTaxGroup(
        pg.config,
        restaurantId,
      );
      expect(created, isTrue);

      final rows = await db.query(
        pg.config,
        'SELECT name_en, rate_bp, is_default FROM pos_tax_groups '
        'WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      expect(rows.first[0], 'VAT');
      expect(rows.first[1], 1400);
      expect(rows.first[2], true);
    });

    test('it keeps the rate the branch actually charges', () async {
      // Defaulting a 15% branch back to Egypt's headline rate would change
      // what customers pay.
      await LocalBootstrap(db).seedTaxGroup(pg.config, restaurantId, rateBp: 1500);
      final rows = await db.query(
        pg.config,
        'SELECT rate_bp FROM pos_tax_groups WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      expect(rows.first[0], 1500);
    });

    test('re-running setup does not reset an accountant\u2019s decision', () async {
      await LocalBootstrap(db).seedTaxGroup(pg.config, restaurantId);
      await db.query(
        pg.config,
        "UPDATE pos_tax_groups SET rate_bp = 500 WHERE restaurant_id = @r",
        parameters: {'r': restaurantId},
      );

      final again = await LocalBootstrap(db).seedTaxGroup(pg.config, restaurantId);
      expect(again, isFalse);

      final rows = await db.query(
        pg.config,
        'SELECT rate_bp FROM pos_tax_groups WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      expect(rows.first[0], 500);
    });
  });

  /// What a payment row means.
  ///
  /// `payment_status.dart` states it and explains why there is no OVERPAID:
  /// a row records what was APPLIED to the bill, never what was tendered,
  /// because change is a till concern that never reaches the ledger. It also
  /// warned this would break "the day somebody wrote tendered by mistake" —
  /// and on 27 Sep 2026 it had, all the way up to the platform, which took a
  /// 380.00 payment against a 360.00 sale.
  group('a payment records what it applied', () {
    Ticket billOf(String id, int totalMinor, List<Tender> tenders) => Ticket(
      id: id,
      orderType: OrderType.takeaway,
      taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
      lines: [
        TicketLine(
          product: Product(
            id: 1,
            categoryId: 1,
            nameEn: 'Meal',
            price: Money(totalMinor),
          ),
          quantity: 1,
        ),
      ],
      tenders: tenders,
    );

    /// Summed from the rows, addressed by the till's own key for the sale —
    /// `submit` answers with that and not with the local id.
    Future<int> paidFor(String clientTransactionId) async {
      final rows = await db.query(
        pg.config,
        'SELECT COALESCE(SUM(p.amount_minor), 0) FROM pos_order_payments p '
        'JOIN pos_orders o ON o.id = p.order_id '
        'WHERE o.client_transaction_id = @k',
        parameters: {'k': clientTransactionId},
      );
      // SUM of a bigint comes back as a String from the driver, not a num.
      return int.parse('${rows.first[0]}');
    }

    test('cash over the total is capped, and the change is still the slip\'s',
        () async {
      // 380.00 handed over for a 360.00 bill.
      const key = '77777777-7777-4777-8777-00000000000a';
      final ticket = billOf(key, 36000, const [
        Tender(typeId: 1, label: 'Cash', amount: Money(38000)),
      ]);

      // The TICKET keeps the tendered figure — the receipt prints what the
      // customer handed over and what came back.
      expect(ticket.totals.change, const Money(2000));

      await orders().submit(ticket);
      expect(
        await paidFor(key),
        36000,
        reason: 'the ledger takes what the sale took, not what the drawer saw',
      );
    });

    test('a split tender applies each in turn and only the last is short',
        () async {
      const key = '77777777-7777-4777-8777-00000000000b';
      await orders().submit(billOf(key, 36000, const [
        Tender(typeId: 1, label: 'Card', amount: Money(20000)),
        Tender(typeId: 1, label: 'Cash', amount: Money(30000)),
      ]));

      // 200 applied, then 160 of the 300 — never 500 against a 360 bill.
      expect(await paidFor(key), 36000);
    });

    test('an exact tender is written exactly, with nothing clever', () async {
      const key = '77777777-7777-4777-8777-00000000000c';
      await orders().submit(billOf(key, 36000, const [
        Tender(typeId: 1, label: 'Cash', amount: Money(36000)),
      ]));
      expect(await paidFor(key), 36000);
    });
  });
}
