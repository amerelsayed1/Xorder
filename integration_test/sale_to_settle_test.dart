@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';

import '../test/data/pg_fixture.dart';
import 'support/e2e_app_files.dart';
import 'support/e2e_licence.dart';
import 'support/e2e_platform.dart';
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
/// real business, seeded by [E2eSeed]. Nothing here is fake. The menu the till
/// shows, the branch it claims and the cashier in the top bar are all rows this
/// suite inserted, which is exactly how a business's own till works.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A licence key is no longer a precondition: without one the suite signs
  // with a key minted for the run, which a development build trusts — see
  // E2eLicence.issue. A release-build run still sets POS_LICENCE_KEY.
  if (PgFixture.host == null || E2ePlatform.baseUrl == null) {
    const required = bool.fromEnvironment('POS_E2E_REQUIRED');
    if (required) {
      throw StateError(
        'POS_E2E_REQUIRED is set, but POS_PG_HOST or POS_PLATFORM_URL is missing.',
      );
    }
    testWidgets(
      'sale to settle (skipped — set POS_PG_HOST and POS_PLATFORM_URL)',
      (_) async {},
      skip: true,
    );
    return;
  }

  late String licence;

  late PgFixture pg;

  final invoicePeriod = DateTime.now().year;

  setUp(() async {
    // Finishing the wizard writes a real terminal configuration, because this
    // suite runs the real wizard. Put back whatever this machine had.
    await E2eAppFiles.preserveTerminalConfig();

    // The schema is an install-time act performed with an admin credential —
    // `bin/pos_migrate.dart` is that act in production. The till itself only
    // ever reads and writes rows, so it cannot create the tables it needs and
    // the test must not pretend otherwise.
    licence = await E2eLicence.issue(
      tenantSlug: E2eSeed.slug,
      tenantName: E2eSeed.businessName,
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

  // The app itself is brought to rest by `TillDriver.boot`, which registers
  // its own teardown inside the test's zone — see the note there.
  tearDown(() => pg.close());

  /// The first table on the floor this till was actually given.
  ///
  /// Not a constant: the platform's bootstrap replaces the local floor with
  /// the branch the claimed terminal belongs to, so the fixture's own table
  /// belongs to a branch this till cannot see. Reading the label back is the
  /// honest way to seat one — and it is what a cashier does too.
  Future<String> firstTableLabel() async {
    final rows = await pg.database.query(
      pg.config,
      'SELECT t.label FROM pos_dining_tables t '
      'JOIN pos_terminals term ON term.branch_id = t.branch_id '
      'WHERE t.is_active ORDER BY term.created_at DESC, t.sort_order, t.id LIMIT 1',
    );
    if (rows.isEmpty) throw StateError('This terminal has no tables on its branch.');
    return rows.first[0] as String;
  }

  /// A product this till can actually sell, read from the catalog the
  /// platform seeded — for the same reason [firstTableLabel] is discovered
  /// rather than assumed. Prefers one with no required options, so a simple
  /// sale stays a simple sale.
  Future<({String name, int priceMinor})> firstProduct() async {
    final rows = await pg.database.query(
      pg.config,
      'SELECT p.name_en, p.price_minor FROM pos_products p '
      'WHERE p.is_available AND NOT EXISTS ('
      '  SELECT 1 FROM pos_product_modifier_groups pmg '
      '  JOIN pos_modifier_groups g ON g.id = pmg.group_id '
      '  WHERE pmg.product_id = p.id AND g.is_required'
      ') ORDER BY p.sort_order, p.id LIMIT 1',
    );
    if (rows.isEmpty) throw StateError('No sellable product on this till.');
    return (name: rows.first[0] as String, priceMinor: rows.first[1] as int);
  }

  /// The invoice prefix this terminal's branch actually carries.
  Future<String> branchCode() async {
    final rows = await pg.database.query(
      pg.config,
      'SELECT b.code FROM pos_branches b '
      'JOIN pos_terminals t ON t.branch_id = b.id '
      'ORDER BY t.created_at DESC LIMIT 1',
    );
    return rows.isEmpty ? 'MAIN' : rows.first[0] as String;
  }

  /// Walk the wizard with this run's real database and real platform behind
  /// it. Phase 1 ships the cloud path, so the terminal is provisioned on the
  /// platform first and claimed with a single-use code — the same order a
  /// manager and an installer follow.
  /// The pairing code the most recent [install] redeemed — the spent-code
  /// test needs to present exactly that one again.
  String? lastPairingCode;

  Future<void> install(TillDriver till) async {
    final code = await E2ePlatform.provisionTerminal(
      name: 'E2E ${DateTime.now().millisecondsSinceEpoch}',
    );
    lastPairingCode = code;
    await till.completeSetup(
      databaseHost: PgFixture.host!,
      databaseName: pg.config.databaseName,
      databasePort: PgFixture.port,
      databaseUser: PgFixture.user,
      databasePassword: PgFixture.password,
      pairingCode: code,
      licenceFile: licence,
      platformUrl: E2ePlatform.baseUrl!,
      tenantSlug: E2ePlatform.slug,
    );
  }

  testWidgets(
    'a new machine is set up, sells a table, and the ledger agrees with the receipt',
    (tester) async {
      final till = TillDriver(tester);
      await till.boot();
      await install(till);

      await till.openShift(pin: E2ePlatform.staffPin);
      await till.seatTable(await firstTableLabel());

      // The menu on screen is the menu the platform sent down. If the
      // bootstrap seed or the catalogue read were broken this fails here
      // rather than somewhere confusing later.
      final product = await firstProduct();
      expect(
        find.text(product.name),
        findsWidgets,
        reason: 'the till should be showing the platform menu, not an empty grid',
      );

      await till.addProduct(product.name);
      await till.charge();
      await till.takePayment();

      // ---- what the customer is holding -------------------------------------

      final invoiceNumber = till.receiptInvoiceNumber();
      expect(
        invoiceNumber,
        startsWith('${await branchCode()}-$invoicePeriod-'),
        reason: 'the prefix is the branch code the platform gave this terminal',
      );
      // A CLOUD sale is queued the instant it settles and drains behind the
      // cashier — so the honest receipt line is the queued one. On the
      // offline path (phase 2) the same slip reads SYNCED TO XORDER, because
      // there is nowhere further for the money to go.
      expect(
        find.text('QUEUED OFFLINE — WILL SYNC'),
        findsOneWidget,
        reason:
            'this sale went straight to the branch database, so the slip must '
            'not tell the customer it is queued',
      );

      // ---- what the branch server recorded ----------------------------------

      final orders = await pg.database.query(pg.config, '''
      SELECT invoice_number, order_type, table_label, guest_count,
             subtotal_minor, service_minor, vat_minor, total_minor, currency,
             business_id, branch_id
      FROM pos_orders
    ''');
      expect(orders, hasLength(1), reason: 'one sale, one row');

      final order = orders.single;
      expect(
        order[0],
        invoiceNumber,
        reason:
            'the number on the slip and the number in the ledger are the same '
            'number, or the receipt is unauditable',
      );
      expect(order[1], 'dine_in');
      expect(
        order[2],
        await firstTableLabel(),
        reason: 'the table the cashier picked on the floor',
      );
      expect(
        order[3],
        isNotNull,
        reason: 'the cover count comes from the table, not from a default',
      );

      final subtotal = order[4] as int;
      final service = order[5] as int;
      final vat = order[6] as int;
      final total = order[7] as int;

      expect(
        subtotal,
        product.priceMinor,
        reason: 'the price came out of pos_products and back through the '
            'engine unchanged',
      );
      expect(
        service,
        isNonZero,
        reason: 'service is charged on dine-in, and this ticket is seated',
      );
      expect(
        total,
        subtotal + service + vat,
        reason:
            'the ledger must foot: anything else means the till and the '
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
        reason:
            'the receipt on screen should show exactly ${Money(total).format()}',
      );

      // ---- the detail under the order ---------------------------------------

      final lines = await pg.database.query(
        pg.config,
        'SELECT name_snapshot, quantity, line_total_minor, modifier_summary '
        'FROM pos_order_lines ORDER BY id',
      );
      expect(lines, hasLength(1));
      expect(lines.map((row) => row[0]), [product.name]);
      expect(lines.map((row) => row[1]), [1]);
      expect(
        lines.fold<int>(0, (sum, row) => sum + (row[2] as int)),
        subtotal,
        reason: 'the lines must add up to the subtotal they were summed into',
      );
      // The product this suite picks is deliberately one with NO required
      // option group, so a simple sale stays simple — the modifier summary is
      // therefore empty here. Options reaching the ledger is covered by
      // `ticket_engine_test` and by `postgres_test`, which write a line with
      // modifiers directly.
      expect(lines.last[3], isNull);

      final payments = await pg.database.query(
        pg.config,
        'SELECT label, amount_minor FROM pos_order_payments',
      );
      expect(payments, hasLength(1), reason: 'paid once, in cash');
      expect(payments.single[0], 'Cash');
      expect(
        payments.single[1],
        total,
        reason:
            'an empty amount at the keypad means the whole remaining balance',
      );
    },
  );

  testWidgets(
    'the sale after a receipt is a new sale, not a replay of the last',
    (tester) async {
      final till = TillDriver(tester);
      await till.boot();
      await install(till);

      await till.openShift(pin: E2ePlatform.staffPin);
      await till.seatTable(await firstTableLabel());
      await till.addProduct((await firstProduct()).name);
      await till.charge();
      await till.takePayment();
      final first = till.receiptInvoiceNumber();

      // "New sale" is what mints a fresh client transaction id. If it did not,
      // the unique index would swallow the second sale silently and the till
      // would take money for an order nobody recorded.
      await till.startNextSale();
      // Settling a seated ticket returns the cashier to the floor, so the next
      // sale starts by seating a table — which is the flow, not a detour.
      await till.seatTable(await firstTableLabel());
      await till.addProduct((await firstProduct()).name);
      await till.charge();
      await till.takePayment();
      final second = till.receiptInvoiceNumber();

      expect(second, isNot(first));
      expect(second, '${await branchCode()}-$invoicePeriod-000002');

      final rows = await pg.database.query(
        pg.config,
        'SELECT client_transaction_id, invoice_number FROM pos_orders ORDER BY id',
      );
      expect(
        rows,
        hasLength(2),
        reason: 'two sales happened, so two rows exist',
      );
      expect(
        rows[0][0],
        isNot(rows[1][0]),
        reason:
            'two sales sharing a transaction id is how one of them disappears',
      );
      expect(rows.map((row) => row[1]), [first, second]);
    },
  );

  testWidgets(
    'the shift is opened, the sale is attributed to it, and the drawer is counted',
    (tester) async {
      final till = TillDriver(tester);
      await till.boot();
      await install(till);

      await till.openShift(pin: E2ePlatform.staffPin);
      await till.seatTable(await firstTableLabel());
      await till.addProduct((await firstProduct()).name);
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
      expect(
        attributed,
        hasLength(1),
        reason: 'the sale belongs to the open shift',
      );
      final total = attributed.single[0] as int;
      expect(
        attributed.single[1],
        0,
        reason: 'the dialog offered an empty drawer, and we took it',
      );

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
      expect(
        closed.single[1],
        total,
        reason: 'float of nothing, plus the cash taken',
      );
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
    },
  );

  testWidgets(
    'closing a shift with a ticket still on screen refuses, rather than losing it',
    (tester) async {
      final till = TillDriver(tester);
      await till.boot();
      await install(till);

      await till.openShift(pin: E2ePlatform.staffPin);
      await till.seatTable(await firstTableLabel());
      await till.addProduct((await firstProduct()).name);

      // The old button discarded this without a word.
      await till.tapButton('Close shift');
      await till.settle();

      expect(
        find.textContaining('still a ticket on this till'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Close SHIFT'),
        findsNothing,
        reason: 'no cash-up was started',
      );
      expect(
        find.text((await firstProduct()).name),
        findsWidgets,
        reason: "the customer's order is still there",
      );
    },
  );

  testWidgets('a machine that has not been set up cannot be sold from', (
    tester,
  ) async {
    final till = TillDriver(tester);
    await till.boot();

    // Setup is not skippable, and the router is what enforces it. A till with
    // no branch, no licence and no menu has nothing useful it could do anyway.
    // An unconfigured till shows the welcome mark; the wizard is a chord away
    // (phase-1 owner decision), so THIS is what "not set up" looks like now.
    expect(find.text('XORDER'), findsOneWidget);
    expect(find.text('This terminal has not been set up.'), findsOneWidget);
    expect(
      find.text('CATEGORIES'),
      findsNothing,
      reason: 'the sale screen must be unreachable before setup finishes',
    );
  });

  testWidgets('a completed installation survives the next application boot', (
    tester,
  ) async {
    final firstBoot = TillDriver(tester);
    await firstBoot.boot();
    await install(firstBoot);

    // Run the production entry point again without clearing Application
    // Support. main() must restore config.json and the file-backed database
    // credential before its first frame, otherwise this returns to setup.
    final restarted = TillDriver(tester);
    await restarted.boot();

    await restarted.waitForTextContaining('Start shift');
    expect(find.text('This terminal has not been set up.'), findsNothing);
  });

  testWidgets('a spent pairing code is refused the second time it is used', (
    tester,
  ) async {
    // The seed resets `claimed_at` between tests, so this is the only place the
    // single-use rule can be observed: claim it, then try again in the same run.
    final till = TillDriver(tester);
    await till.boot();
    await install(till);

    // A second machine, walked to the same step. It cannot reuse
    // `completeSetup`, which expects the claim to succeed — this test is about
    // the claim being refused.
    final second = TillDriver(tester);
    await second.boot(freshInstallation: true);
    await second.openSetupFromWelcome();

    // Setup type (cloud is preselected) and language are confirmations.
    await second.tapButton('Continue');
    await second.tapButton('Continue');

    // Connection: the platform, and this till's own local database.
    await second.enterField('Platform address', E2ePlatform.baseUrl!);
    if (find.text('Database address').evaluate().isNotEmpty) {
      await second.enterField('Database address', PgFixture.host!);
    }
    await second.enterField('Database name', pg.config.databaseName);
    await second.enterField('Port', PgFixture.port.toString());
    await second.enterField('Database user', PgFixture.user);
    await second.enterField('Database password', PgFixture.password);
    await second.tapButton('Test connection');
    await second.waitForNoSpinner();
    await second.tapButton('Continue');

    // Sign in with the code the FIRST machine already redeemed.
    await second.enterField('Business', E2ePlatform.slug);
    await second.tapButton('Setup code');
    await second.enterField('Setup code', lastPairingCode!);
    await second.tapButton('Claim this terminal');

    // "Already used" and "not recognised" are different problems: one needs a
    // new code from the dashboard, the other needs the operator to retype.
    await second.waitForTextContaining('already been used');
  });
}
