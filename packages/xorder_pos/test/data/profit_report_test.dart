@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_reports_repository.dart';
import 'package:xorder_pos/domain/models/profit_report.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// The profit report's SQL, against the stock ledger it reads.
///
/// Everything here is on 10 September 2026 unless it says otherwise, in
/// piastres. The ledger is built to put one question to each rule the query
/// holds, because a profit query is wrong quietly: it returns a plausible
/// number for any of the mistakes below.
///
/// | Item | What sold | Cost on the ledger |
/// |---|---|---|
/// | Cola (stocked) | A: 3 @ 20.00; B: 2 @ 20.00, one refunded | 3,000 milli @ 8.00, 2,000 milli @ 9.00 |
/// | Chips (stocked) | A: 2 @ 15.00 sold before any delivery; E: 1 @ 15.00 after | A at cost 0 — "never bought"; E at 10.00 |
/// | Rice (stocked) | F: 1 @ 10.00 | 1,500 milli @ 3.33 — 4.995 rounds half-up |
/// | Burger (a dish) | A: 1 @ 85.00 | none — no recipe, never costed |
///
/// Around it, everything that must NOT count: a voided order with a Cola
/// sale, a 'waste' and a 'receipt' movement, a sale on the 8th, and another
/// branch's till.
void main() {
  if (PgFixture.host == null) {
    test('profit report (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const terminal = '30000000-0000-4000-8000-000000000001';
  const otherTerminal = '30000000-0000-4000-8000-000000000002';

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int nour;
  late int cola;
  late int chips;
  late int rice;
  late int burger;
  late PostgresReportsRepository reports;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> product(String name, {required bool stocked}) => scalar(
    'INSERT INTO pos_products (business_id, category_id, name_en, '
    '  price_minor, is_stocked) '
    'VALUES (@r, (SELECT id FROM pos_categories WHERE business_id = @r), '
    '  @n, 1000, @s) RETURNING id',
    {'r': businessId, 'n': name, 's': stocked},
  );

  /// One order, its lines `(menu item, name, quantity, unit price, refunded)`.
  Future<int> order({
    required DateTime at,
    required List<(int, String, int, int, int)> lines,
    String status = 'PAID',
    int? branch,
    String? onTerminal,
  }) async {
    invoice++;
    final total = lines.fold<int>(0, (sum, l) => sum + l.$3 * l.$4);
    final id = await scalar(
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, voided_at, voided_by) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, 'dine_in', 'EGP', 2, "
      '  @total, 0, 0, 0, @total, @at::timestamptz, @status, '
      "  CASE WHEN @status::text = 'VOIDED' THEN @at::timestamptz END, "
      "  CASE WHEN @status::text = 'VOIDED' THEN @by::bigint END) "
      'RETURNING id',
      {
        'r': businessId,
        'b': branch ?? branchId,
        't': onTerminal ?? terminal,
        'inv': 'PR-$invoice',
        'total': total,
        'at': at,
        'status': status,
        'by': nour,
      },
    );
    var key = 0;
    for (final (item, name, quantity, unit, refunded) in lines) {
      key++;
      await db.query(
        pg.config,
        'INSERT INTO pos_order_lines (order_id, line_key, menu_item_id, '
        '  name_snapshot, quantity, unit_price_minor, line_total_minor, stage, '
        '  refunded_quantity) '
        "VALUES (@o, @key, @item, @name, @q, @unit, @line, 'sent', @refunded)",
        parameters: {
          'o': id,
          'key': 'l$key',
          'item': item,
          'name': name,
          'q': quantity,
          'unit': unit,
          'line': unit * quantity,
          'refunded': refunded,
        },
      );
    }
    return id;
  }

  /// A stock movement, on the ledger as the till writes it.
  Future<void> movement({
    required int product,
    required String kind,
    required int milli,
    required int cost,
    int? orderId,
    int? branch,
  }) => db.query(
    pg.config,
    'INSERT INTO pos_stock_movements (business_id, branch_id, product_id, '
    '  kind, quantity_milli, unit_cost_minor, balance_milli, '
    '  average_cost_minor, order_id) '
    'VALUES (@r, @b, @p, @kind, @q, @cost, 0, @cost, @o)',
    parameters: {
      'r': businessId,
      'b': branch ?? branchId,
      'p': product,
      'kind': kind,
      'q': milli,
      'cost': cost,
      'o': orderId,
    },
  );

  final tenth = DateTime.utc(2026, 9, 10, 10);
  final range = ReportFilter.day(DateTime(2026, 9, 10));

  setUp(() async {
    pg = await PgFixture.open('profit_report');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_outbox, pos_refunds, pos_orders, pos_business_days, '
      'pos_invoice_sequences RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_combos');
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    invoice = 0;

    businessId = await scalar(
      "INSERT INTO pos_businesses (slug, name) VALUES ('pf', 'Profit') "
      'RETURNING id',
    );
    branchId = await scalar(
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'MANS', 'Mansoura') RETURNING id",
      {'r': businessId},
    );
    otherBranchId = await scalar(
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'TANT', 'Tanta') RETURNING id",
      {'r': businessId},
    );
    nour = await scalar(
      'INSERT INTO pos_users (business_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', 'nour', 'salt', 'hash') "
      'RETURNING id',
      {'r': businessId, 'b': branchId},
    );
    for (final (id, name, branch) in [
      (terminal, 'POS-01', branchId),
      (otherTerminal, 'TANTA-01', otherBranchId),
    ]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
        'VALUES (@id::uuid, @r, @b, @name)',
        parameters: {'id': id, 'r': businessId, 'b': branch, 'name': name},
      );
    }
    await db.query(
      pg.config,
      'INSERT INTO pos_categories (business_id, name_en, slug) '
      "VALUES (@r, 'Menu', 'menu')",
      parameters: {'r': businessId},
    );
    cola = await product('Cola', stocked: true);
    chips = await product('Chips', stocked: true);
    rice = await product('Rice', stocked: true);
    burger = await product('Burger', stocked: false);

    reports = PostgresReportsRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  /// The ledger the table above describes.
  Future<void> seed() async {
    final a = await order(
      at: tenth,
      lines: [
        (cola, 'Cola', 3, 2000, 0),
        (chips, 'Chips', 2, 1500, 0),
        (burger, 'Burger', 1, 8500, 0),
      ],
    );
    await movement(product: cola, kind: 'sale', milli: -3000, cost: 800, orderId: a);
    // Sold before the first delivery: the carrying cost was zero.
    await movement(product: chips, kind: 'sale', milli: -2000, cost: 0, orderId: a);
    // Not the cost of a sale, though it names this order.
    await movement(product: cola, kind: 'waste', milli: -1000, cost: 800, orderId: a);

    final b = await order(
      at: tenth.add(const Duration(hours: 1)),
      // Two sold, one refunded: the revenue came back, the cost did not.
      lines: [(cola, 'Cola', 2, 2000, 1)],
    );
    await movement(product: cola, kind: 'sale', milli: -2000, cost: 900, orderId: b);

    final e = await order(
      at: tenth.add(const Duration(hours: 2)),
      lines: [(chips, 'Chips', 1, 1500, 0)],
    );
    await movement(product: chips, kind: 'sale', milli: -1000, cost: 1000, orderId: e);

    final f = await order(
      at: tenth.add(const Duration(hours: 3)),
      lines: [(rice, 'Rice', 1, 1000, 0)],
    );
    // 1.500 × 3.33 = 4.995 → half-up 5.00, per movement.
    await movement(product: rice, kind: 'sale', milli: -1500, cost: 333, orderId: f);

    // Everything below must not be in the answer.
    final voided = await order(
      at: tenth,
      status: 'VOIDED',
      lines: [(cola, 'Cola', 5, 2000, 0)],
    );
    await movement(product: cola, kind: 'sale', milli: -5000, cost: 800, orderId: voided);
    await movement(product: cola, kind: 'receipt', milli: 24000, cost: 800);
    final eighth = await order(
      at: DateTime.utc(2026, 9, 8, 10),
      lines: [(cola, 'Cola', 9, 2000, 0)],
    );
    await movement(product: cola, kind: 'sale', milli: -9000, cost: 800, orderId: eighth);
    final elsewhere = await order(
      at: tenth,
      branch: otherBranchId,
      onTerminal: otherTerminal,
      lines: [(cola, 'Cola', 7, 2000, 0)],
    );
    await movement(
      product: cola,
      kind: 'sale',
      milli: -7000,
      cost: 800,
      orderId: elsewhere,
      branch: otherBranchId,
    );
  }

  ProductProfit row(ProfitReport r, String name) =>
      r.products.singleWhere((p) => p.name == name);

  test('a sale at cost is profit, summed across orders', () async {
    await seed();
    final cola = row(await reports.profit(range), 'Cola');

    // Orders A and B only: 3 + 2 sold, 1 refunded → 4 kept.
    expect(cola.quantity, 4);
    expect(cola.revenue.minor, 8000);
    expect(cola.costedRevenue.minor, 8000);
    // 3,000 milli @ 8.00 = 2,400 and 2,000 milli @ 9.00 = 1,800.
    expect(cola.cost!.minor, 4200);
    expect(cola.profit!.minor, 3800);
    expect(cola.marginBp, 4750);
  });

  test('a refund takes the revenue back and leaves the cost spent', () async {
    await seed();
    final cola = row(await reports.profit(range), 'Cola');

    // Order B sold two at 20.00 and one came back: 20.00 of its 40.00 is kept,
    // but the ledger issued both, so its full 18.00 is still the cost.
    expect(cola.revenue.minor, 6000 + 2000);
    expect(cola.cost!.minor, 2400 + 1800);
  });

  test('a sale at a carrying cost of zero is not costed, not free', () async {
    await seed();
    final chips = row(await reports.profit(range), 'Chips');

    // 3 kept: 2 before any delivery (uncosted) and 1 after (costed at 10.00).
    expect(chips.quantity, 3);
    expect(chips.revenue.minor, 4500);
    expect(chips.costedRevenue.minor, 1500);
    expect(chips.cost!.minor, 1000);
    // The margin is on the 15.00 that has a cost, never on all 45.00.
    expect(chips.profit!.minor, 500);
    expect(chips.marginBp, 3333);
  });

  test('each movement is rounded half-up on its own', () async {
    await seed();
    final rice = row(await reports.profit(range), 'Rice');

    expect(rice.cost!.minor, 500, reason: '1.500 × 3.33 = 4.995');
    expect(rice.profit!.minor, 500);
  });

  test('a dish has revenue and no cost, and is reported that way', () async {
    await seed();
    final burger = row(await reports.profit(range), 'Burger');

    expect(burger.revenue.minor, 8500);
    expect(burger.isCosted, isFalse);
    expect(burger.cost, isNull);
    expect(burger.costedRevenue.minor, 0);
  });

  test('the report says how much of the menu it covers', () async {
    await seed();
    final r = await reports.profit(range);

    // 80.00 + 45.00 + 10.00 + 85.00.
    expect(r.revenue.minor, 22000);
    expect(r.costedRevenue.minor, 8000 + 1500 + 1000);
    expect(r.cost.minor, 4200 + 1000 + 500);
    expect(r.profit.minor, 4800);
    expect(r.uncostedRevenue.minor, 11500);
    expect(r.coverageBp, 4773);
    expect(r.marginBp, 4571);
  });

  test('it is ranked: costed by profit, then what it cannot cost', () async {
    await seed();
    final r = await reports.profit(range);

    // Chips and Rice tie on 5.00 profit; revenue breaks it.
    expect(r.products.map((p) => p.name), ['Cola', 'Chips', 'Rice', 'Burger']);
  });

  group('what is not in the answer', () {
    test('a voided order, another day and another branch', () async {
      await seed();
      final r = await reports.profit(range);

      // 5 voided + 9 on the 8th + 7 elsewhere would be 21 more Colas.
      expect(row(r, 'Cola').quantity, 4);
    });

    test('a waste or receipt movement is not the cost of a sale', () async {
      await seed();
      final cola = row(await reports.profit(range), 'Cola');

      // The 1,000-milli waste on order A would have added 8.00; the 24,000-milli
      // receipt would have subtracted from the cost entirely.
      expect(cola.cost!.minor, 4200);
    });

    test('a range with no sales is empty, not an error', () async {
      await seed();
      final r = await reports.profit(ReportFilter.day(DateTime(2026, 9, 20)));

      expect(r.products, isEmpty);
      expect(r.revenue.minor, 0);
      expect(r.coverageBp, isNull);
    });
  });

  group('when nothing has a cost', () {
    test('every item is revenue only', () async {
      await order(
        at: tenth,
        lines: [(burger, 'Burger', 2, 8500, 0)],
      );
      final r = await reports.profit(range);

      expect(r.hasAnyCost, isFalse);
      expect(r.revenue.minor, 17000);
      expect(r.marginBp, isNull);
      expect(r.coverageBp, 0);
    });
  });

  group('an item every unit of which came back', () {
    test('is still listed if its cost was spent: that is a loss', () async {
      final o = await order(
        at: tenth,
        lines: [(cola, 'Cola', 1, 2000, 1)],
      );
      await movement(product: cola, kind: 'sale', milli: -1000, cost: 800, orderId: o);

      final r = await reports.profit(range);
      final colaRow = row(r, 'Cola');

      expect(colaRow.quantity, 0);
      expect(colaRow.revenue.minor, 0);
      expect(colaRow.profit!.minor, -800);
      expect(colaRow.marginBp, isNull);
    });

    test('is dropped if it never had a cost: it simply did not sell', () async {
      await order(
        at: tenth,
        lines: [(burger, 'Burger', 1, 8500, 1)],
      );

      expect((await reports.profit(range)).products, isEmpty);
    });
  });

  group('lines that name no menu item', () {
    test('an open charge is grouped by its name and never costed', () async {
      await db.query(
        pg.config,
        'INSERT INTO pos_order_lines (order_id, line_key, menu_item_id, '
        '  name_snapshot, quantity, unit_price_minor, line_total_minor, stage) '
        "SELECT o.id, 'x', NULL, 'Corkage', 1, 5000, 5000, 'sent' "
        '  FROM (SELECT @id::bigint AS id) o',
        parameters: {
          'id': await order(at: tenth, lines: [(burger, 'Burger', 1, 8500, 0)]),
        },
      );

      final r = await reports.profit(range);

      expect(row(r, 'Corkage').menuItemId, isNull);
      expect(row(r, 'Corkage').isCosted, isFalse);
      expect(row(r, 'Corkage').revenue.minor, 5000);
    });
  });

  group('prices that contain tax: revenue is taken back to net', () {
    // The lines record no tax of their own, so each line is scaled by its
    // ORDER's net-to-gross ratio from `pos_order_taxes`. Three orders put the
    // three cases to it: one rate (exact), mixed rates (a documented estimate,
    // pinned so the approximation is explicit rather than discovered), and no
    // tax rows at all (left whole).
    Future<void> taxRow(int orderId, String name, int rateBp, int base, int amount) =>
        db.query(
          pg.config,
          'INSERT INTO pos_order_taxes (order_id, name_snapshot, rate_bp, '
          '  base_minor, amount_minor) VALUES (@o, @n, @r, @b, @a)',
          parameters: {
            'o': orderId,
            'n': name,
            'r': rateBp,
            'b': base,
            'a': amount,
          },
        );

    // Where the till prices from — the payload the Taxes pane saves — not
    // `pos_businesses.tax_mode`, which nothing writes.
    Future<void> inclusive() => db.query(
      pg.config,
      'INSERT INTO pos_money_config (business_id, payload) '
      "VALUES (@r, '{\"tax_mode\": \"inclusive\"}'::jsonb) "
      'ON CONFLICT (business_id) DO UPDATE '
      "SET payload = pos_money_config.payload || '{\"tax_mode\": \"inclusive\"}'::jsonb",
      parameters: {'r': businessId},
    );

    /// T1: three Colas at 11.40 gross, all at 14% → 30.00 net + 4.20 tax.
    /// T2: a Cola at 11.40 (14%) beside a Burger at 10.00 (zero-rated):
    ///     20.00 net over 21.40 gross.
    /// T3: a Cola at 10.00 with no tax recorded.
    Future<void> ledger() async {
      final t1 = await order(at: tenth, lines: [(cola, 'Cola', 3, 1140, 0)]);
      await taxRow(t1, 'VAT 14%', 1400, 3000, 420);
      await movement(product: cola, kind: 'sale', milli: -3000, cost: 500, orderId: t1);

      final t2 = await order(
        at: tenth.add(const Duration(hours: 1)),
        lines: [(cola, 'Cola', 1, 1140, 0), (burger, 'Burger', 1, 1000, 0)],
      );
      await taxRow(t2, 'VAT 14%', 1400, 1000, 140);
      await taxRow(t2, 'Zero-rated', 0, 1000, 0);
      await movement(product: cola, kind: 'sale', milli: -1000, cost: 500, orderId: t2);

      final t3 = await order(
        at: tenth.add(const Duration(hours: 2)),
        lines: [(cola, 'Cola', 1, 1000, 0)],
      );
      await movement(product: cola, kind: 'sale', milli: -1000, cost: 500, orderId: t3);
    }

    test('an order at one rate comes back to its net exactly', () async {
      await inclusive();
      // T1 on its own: three Colas, 34.20 gross, 14% in it.
      final only = await order(at: tenth, lines: [(cola, 'Cola', 3, 1140, 0)]);
      await taxRow(only, 'VAT 14%', 1400, 3000, 420);
      await movement(product: cola, kind: 'sale', milli: -3000, cost: 500, orderId: only);

      final cola_ = row(await reports.profit(range), 'Cola');

      // 30.00 — the net — and never the 34.20 it was rung up at.
      expect(cola_.revenue.minor, 3000);
      expect(cola_.cost!.minor, 1500);
      expect(cola_.profit!.minor, 1500);
      expect(cola_.marginBp, 5000);
    });

    test('across three orders the Cola is net, not gross', () async {
      await inclusive();
      await ledger();
      final colas = await reports.profit(range);

      // T1's 30.00, T2's 10.65 and T3's untaxed 10.00: 50.65, where gross is
      // 55.60.
      expect(row(colas, 'Cola').revenue.minor, 3000 + 1065 + 1000);
      expect(row(colas, 'Cola').revenue.minor, isNot(3420 + 1140 + 1000));
    });

    test('a mixed-rate order is shared out at its blend — an estimate', () async {
      await inclusive();
      await ledger();
      final r = await reports.profit(range);

      // T2's 20.00 net over 21.40 gross: the 14% Cola 11.40 → 10.65, and the
      // ZERO-RATED Burger 10.00 → 9.35, though it carried no tax at all. That
      // second figure is the approximation; the order's own net, 10.65 + 9.35,
      // is exactly its recorded 20.00.
      expect(row(r, 'Burger').revenue.minor, 935);
      expect(1065 + 935, 2000, reason: 'the order still adds up to its net');
    });

    test('an order with no recorded tax is left whole', () async {
      await inclusive();
      await ledger();
      final r = await reports.profit(range);

      // T3's Cola is 10.00 in the total above: 30.00 + 10.65 + 10.00.
      expect(row(r, 'Cola').revenue.minor, 5065);
    });

    test('profit is measured on that net revenue', () async {
      await inclusive();
      await ledger();
      final cola = row(await reports.profit(range), 'Cola');

      // Cost: 3,000 + 1,000 + 1,000 milli at 5.00 = 25.00.
      expect(cola.cost!.minor, 2500);
      expect(cola.costedRevenue.minor, 5065);
      expect(cola.profit!.minor, 2565);
    });

    test('the same orders on a tax-exclusive business are untouched', () async {
      // Default mode: the lines are already net, and nothing is scaled.
      await ledger();
      final r = await reports.profit(range);

      expect(r.pricesIncludeTax, isFalse);
      expect(row(r, 'Cola').revenue.minor, 3420 + 1140 + 1000);
      expect(row(r, 'Burger').revenue.minor, 1000);
    });
  });

  group('whether the price contains tax', () {
    test('an exclusive business is not flagged', () async {
      await seed();

      expect((await reports.profit(range)).pricesIncludeTax, isFalse);
    });

    test('an inclusive one is', () async {
      await seed();
      await db.query(
        pg.config,
        'INSERT INTO pos_money_config (business_id, payload) '
        "VALUES (@r, '{\"tax_mode\": \"inclusive\"}'::jsonb) "
        'ON CONFLICT (business_id) DO UPDATE '
        "SET payload = pos_money_config.payload || '{\"tax_mode\": \"inclusive\"}'::jsonb",
        parameters: {'r': businessId},
      );

      expect((await reports.profit(range)).pricesIncludeTax, isTrue);
    });
  });
}
