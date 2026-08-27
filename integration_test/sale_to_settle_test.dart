@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';

import '../test/data/pg_fixture.dart';
import 'support/e2e_licence.dart';
import 'support/e2e_seed.dart';
import 'support/till_driver.dart';

/// The whole till, from an unconfigured machine to money in the ledger.
///
/// Everything below the UI already has a suite: `ticket_engine_test` proves the
/// arithmetic, `postgres_test` proves the SQL, `postgres_wiring_test` proves the
/// provider graph resolves to Postgres. What none of them can prove is that a
/// person who walks up to a new machine ends up with a sale in the database,
/// because each one starts halfway in — with a container already built, or a
/// ticket already assembled.
///
/// This one starts where an installer does: a first-run wizard, a real password
/// typed into a real field, and a real PostgreSQL on the other side — holding a
/// real restaurant, seeded by [E2eSeed]. Nothing here is fake. The menu the till
/// shows, the branch it claims and the cashier in the top bar are all rows this
/// suite inserted, which is exactly how a restaurant's own till works.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (PgFixture.host == null || E2eLicence.signingKey == null) {
    testWidgets(
      'sale to settle (skipped — set POS_PG_HOST and POS_LICENCE_KEY to run)',
      (_) async {},
      skip: true,
    );
    return;
  }

  late String licence;

  late PgFixture pg;
  final invoicePeriod = DateTime.now().year;

  setUp(() async {
    // The schema is an install-time act performed with an admin credential —
    // `bin/pos_migrate.dart` is that act in production. The till itself only
    // ever reads and writes rows, so it cannot create the tables it needs and
    // the test must not pretend otherwise.
    licence = await E2eLicence.issue(
      tenantSlug: E2eSeed.slug,
      tenantName: E2eSeed.restaurantName,
    );

    pg = await PgFixture.open('e2e');
    await PosMigrator(pg.database).migrate(pg.config);
    await E2eSeed.apply(pg.database, pg.config);

    // The ledger first, then the shifts that own it. A shift left open by the
    // previous test would make the start screen offer to *resume* rather than
    // open one — correct behaviour, and not what the next test is testing.
    await pg.truncate();
    await pg.database.query(pg.config, 'DELETE FROM pos_shifts');
  });

  tearDown(() => pg.close());

  /// Walk the wizard with this run's real database behind it.
  Future<void> install(TillDriver till) => till.completeSetup(
        // The wizard will only waive certificate checks for a private address,
        // and the LAN box in a restaurant is exactly that case.
        serverAddress: 'http://${PgFixture.host}:8100',
        databaseName: pg.config.databaseName,
        databasePort: PgFixture.port,
        databaseUser: PgFixture.user,
        databasePassword: PgFixture.password,
        tenantSlug: E2eSeed.slug,
        pairingCode: E2eSeed.pairingCode,
        licenceFile: licence,
      );

  testWidgets('a new machine is set up, sells a table, and the ledger agrees with the receipt',
      (tester) async {
    final till = TillDriver(tester);
    await till.boot();
    await install(till);

    await till.openShift(pin: E2eSeed.staffPin);
    await till.seatTable(E2eSeed.tableLabel);

    // The menu on screen is the menu in the database. If the catalogue read
    // were broken this fails here rather than somewhere confusing later.
    expect(
      find.text(E2eSeed.water),
      findsOneWidget,
      reason: 'the till should be showing the seeded menu, not an empty grid',
    );

    await till.addProduct(E2eSeed.water); //                    25.00, no options
    await till.addProductWithOption(E2eSeed.fries, 'Regular'); // 55.00, required group
    await till.charge();
    await till.takePayment();

    // ---- what the customer is holding -------------------------------------

    final invoiceNumber = till.receiptInvoiceNumber();
    expect(
      invoiceNumber,
      '${E2eSeed.branchCode}-$invoicePeriod-000001',
      reason: 'the prefix is the seeded branch code, and the first sale of the '
          'period is number one',
    );
    expect(
      find.text('SYNCED TO XORDER'),
      findsOneWidget,
      reason: 'this sale went straight to the branch database, so the slip must '
          'not tell the customer it is queued',
    );

    // ---- what the branch server recorded ----------------------------------

    final orders = await pg.database.query(pg.config, '''
      SELECT invoice_number, order_type, table_label, guest_count,
             subtotal_minor, service_minor, vat_minor, total_minor, currency,
             restaurant_id, branch_id
      FROM pos_orders
    ''');
    expect(orders, hasLength(1), reason: 'one sale, one row');

    final order = orders.single;
    expect(
      order[0],
      invoiceNumber,
      reason: 'the number on the slip and the number in the ledger are the same '
          'number, or the receipt is unauditable',
    );
    expect(order[1], 'dine_in');
    expect(order[2], E2eSeed.tableLabel, reason: 'the table the cashier picked on the floor');
    expect(
      order[3],
      E2eSeed.tableSeats,
      reason: 'the cover count comes from the seeded table, not from a default',
    );

    final subtotal = order[4] as int;
    final service = order[5] as int;
    final vat = order[6] as int;
    final total = order[7] as int;

    expect(
      subtotal,
      E2eSeed.waterMinor + E2eSeed.friesMinor,
      reason: 'the prices came out of pos_products and back through the engine '
          'unchanged; "Regular" adds nothing',
    );
    expect(service, isNonZero, reason: 'service is charged on dine-in, and this ticket is seated');
    expect(
      total,
      subtotal + service + vat,
      reason: 'the ledger must foot: anything else means the till and the '
          'database disagree about what was charged',
    );
    expect(order[8], 'EGP');

    // Tenant scoping is not something the cashier can type — it arrived with
    // the pairing code and is stamped on the row.
    expect(order[9], isNotNull);
    expect(order[10], isNotNull);

    // The strongest statement this suite can make: the money printed on the
    // slip is the money in the ledger, having travelled the whole way through
    // the engine, the provider graph and a transaction.
    expect(
      find.text(Money(total).format()),
      findsWidgets,
      reason: 'the receipt on screen should show exactly ${Money(total).format()}',
    );

    // ---- the detail under the order ---------------------------------------

    final lines = await pg.database.query(
      pg.config,
      'SELECT name_snapshot, quantity, line_total_minor, modifier_summary '
      'FROM pos_order_lines ORDER BY id',
    );
    expect(lines, hasLength(2));
    expect(lines.map((row) => row[0]), [E2eSeed.water, E2eSeed.fries]);
    expect(lines.map((row) => row[1]), [1, 1]);
    expect(
      lines.fold<int>(0, (sum, row) => sum + (row[2] as int)),
      subtotal,
      reason: 'the lines must add up to the subtotal they were summed into',
    );
    expect(
      lines.last[3],
      contains('Regular'),
      reason: 'the option chosen in the sheet has to reach the ledger, or a '
          'kitchen dispute cannot be settled from the record',
    );

    final payments = await pg.database.query(
      pg.config,
      'SELECT label, amount_minor FROM pos_order_payments',
    );
    expect(payments, hasLength(1), reason: 'paid once, in cash');
    expect(payments.single[0], 'Cash');
    expect(
      payments.single[1],
      total,
      reason: 'an empty amount at the keypad means the whole remaining balance',
    );
  });

  testWidgets('the sale after a receipt is a new sale, not a replay of the last', (tester) async {
    final till = TillDriver(tester);
    await till.boot();
    await install(till);

    await till.openShift(pin: E2eSeed.staffPin);
    await till.seatTable(E2eSeed.tableLabel);
    await till.addProduct(E2eSeed.water);
    await till.charge();
    await till.takePayment();
    final first = till.receiptInvoiceNumber();

    // "New sale" is what mints a fresh client transaction id. If it did not,
    // the unique index would swallow the second sale silently and the till
    // would take money for an order nobody recorded.
    await till.startNextSale();
    await till.addProduct(E2eSeed.water);
    await till.charge();
    await till.takePayment();
    final second = till.receiptInvoiceNumber();

    expect(second, isNot(first));
    expect(second, '${E2eSeed.branchCode}-$invoicePeriod-000002');

    final rows = await pg.database.query(
      pg.config,
      'SELECT client_transaction_id, invoice_number FROM pos_orders ORDER BY id',
    );
    expect(rows, hasLength(2), reason: 'two sales happened, so two rows exist');
    expect(
      rows[0][0],
      isNot(rows[1][0]),
      reason: 'two sales sharing a transaction id is how one of them disappears',
    );
    expect(rows.map((row) => row[1]), [first, second]);
  });

  testWidgets('the shift is opened, the sale is attributed to it, and the drawer is counted',
      (tester) async {
    final till = TillDriver(tester);
    await till.boot();
    await install(till);

    await till.openShift(pin: E2eSeed.staffPin);
    await till.seatTable(E2eSeed.tableLabel);
    await till.addProduct(E2eSeed.water);
    await till.charge();
    await till.takePayment();
    await till.startNextSale();

    // The sale has to name the shift it was rung up in, or the Z report totals
    // nothing and the drawer cannot be reconciled to anything.
    final attributed = await pg.database.query(
      pg.config,
      'SELECT o.total_minor, s.opening_float_minor '
      'FROM pos_orders o JOIN pos_shifts s ON s.id = o.shift_id',
    );
    expect(attributed, hasLength(1), reason: 'the sale belongs to the open shift');
    final total = attributed.single[0] as int;
    expect(attributed.single[1], 0, reason: 'the dialog offered an empty drawer, and we took it');

    await till.closeShift(counted: Money(total).format());

    // Back at the start screen, and the shift is on the record with a count.
    await till.waitForTextContaining('Start shift');

    final closed = await pg.database.query(
      pg.config,
      'SELECT counted_cash_minor, expected_cash_minor, variance_minor, '
      '       closed_at IS NOT NULL, closed_by IS NOT NULL '
      'FROM pos_shifts ORDER BY id DESC LIMIT 1',
    );
    expect(closed.single[0], total, reason: 'what the cashier counted');
    expect(closed.single[1], total, reason: 'float of nothing, plus the cash taken');
    expect(closed.single[2], 0, reason: 'the drawer balances');
    expect(closed.single[3], true);
    expect(closed.single[4], true, reason: 'somebody signed for the count');

    // And the terminal is free for the next shift, which is the thing the old
    // navigate-and-forget button could never say.
    final open = await pg.database.query(
      pg.config,
      'SELECT count(*) FROM pos_shifts WHERE closed_at IS NULL',
    );
    expect(open.single[0], 0);
  });

  testWidgets('closing a shift with a ticket still on screen refuses, rather than losing it',
      (tester) async {
    final till = TillDriver(tester);
    await till.boot();
    await install(till);

    await till.openShift(pin: E2eSeed.staffPin);
    await till.seatTable(E2eSeed.tableLabel);
    await till.addProduct(E2eSeed.water);

    // The old button discarded this without a word.
    await till.tapButton('Close shift');
    await till.settle();

    expect(find.textContaining('still a ticket on this till'), findsOneWidget);
    expect(find.textContaining('Close SHIFT'), findsNothing, reason: 'no cash-up was started');
    expect(
      find.text(E2eSeed.water),
      findsWidgets,
      reason: "the customer's order is still there",
    );
  });

  testWidgets('a machine that has not been set up cannot be sold from', (tester) async {
    final till = TillDriver(tester);
    await till.boot();

    // Setup is not skippable, and the router is what enforces it. A till with
    // no branch, no licence and no menu has nothing useful it could do anyway.
    expect(find.text('TERMINAL SETUP'), findsOneWidget);
    expect(
      find.text('CATEGORIES'),
      findsNothing,
      reason: 'the sale screen must be unreachable before setup finishes',
    );
  });

  testWidgets('a spent pairing code is refused the second time it is used', (tester) async {
    // The seed resets `claimed_at` between tests, so this is the only place the
    // single-use rule can be observed: claim it, then try again in the same run.
    final till = TillDriver(tester);
    await till.boot();
    await install(till);

    final second = TillDriver(tester);
    await second.boot();
    await second.tapButton('Continue');
    await second.tapButton('Branch server');
    await second.enterField('Server address', 'http://${PgFixture.host}:8100');
    await second.tapButton('Trust this server without a certificate');
    await second.enterField('Database', pg.config.databaseName);
    await second.enterField('Port', PgFixture.port.toString());
    await second.enterField('Database user', PgFixture.user);
    await second.enterField('Database password', PgFixture.password);
    await second.enterField('Upstream', 'https://xorder.io');

    // Straight to Sign in — no licence needed to get this far, which is the
    // whole reason that step now comes second.
    await second.tapButton('Continue');
    await second.enterField('Restaurant', E2eSeed.slug);
    await second.enterField('Setup code', E2eSeed.pairingCode);
    await second.tapButton('Claim this terminal');

    // "Already used" and "not recognised" are different problems: one needs a
    // new code from the dashboard, the other needs the operator to retype.
    await second.waitForTextContaining('already been used');
  });
}
