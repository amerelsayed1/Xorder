import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/pos_main.dart' as app;

import 'e2e_app_files.dart';

/// Drives the assembled till the way the person standing at it does.
///
/// Nothing in here reads a provider or calls a controller. That restraint is
/// the point of the whole suite: the widget tests already drive the controllers
/// directly, so an end-to-end test that did the same would re-cover them and
/// still miss the seams it exists to catch — wizard to router, router to till,
/// till to database. Everything below goes through the surface a cashier can
/// actually touch.
class TillDriver {
  TillDriver(this.tester);

  final WidgetTester tester;

  /// A till is a fixed installation, so the window is pinned rather than left
  /// to whatever size the host hands us. The three-pane sale shell only exists
  /// above 1100dp; testing at some other width would exercise a layout no
  /// business runs.
  static const window = Size(1440, 900);

  /// How long any one wait may take before the test gives up.
  ///
  /// Generous because two genuinely slow things are being waited on: a
  /// PostgreSQL round trip, and the deliberate delays the fake repositories use
  /// to imitate a server.
  static const patience = Duration(seconds: 30);

  // ---------------------------------------------------------------- lifecycle

  /// Boot the real app — real router, real provider graph, no overrides.
  ///
  /// Overriding anything here would be self-defeating. The credential the till
  /// connects with is supposed to arrive by way of the wizard's password field,
  /// and a test that injected it instead would pass on a till that could never
  /// be set up by hand.
  Future<void> boot({bool freshInstallation = false}) async {
    if (freshInstallation) await E2eAppFiles.clearInstallation();

    // Registered from INSIDE the test body so it runs in the test's own zone.
    // The live binding asserts no frame is pending at teardown, and a till
    // that just settled a sale has a receipt animating and a sync pass in
    // flight; replacing the tree disposes the ProviderScope, which cancels
    // both. Doing this from the suite's own `tearDown` instead trips the
    // harness's guarded-function check, because that runs outside the zone.
    addTearDown(() async {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      } on Object {
        // Teardown must never fail a test whose assertions passed.
      }
    });

    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Unmount the previous installation before runPos() creates the production
    // ProviderScope and restores configuration and credentials from disk.
    // The suite walks a cloud install (see [walkWizard]), so it boots as
    // "XOrder POS - Cloud" (pos-split-apps, stage 2).
    await tester.pumpWidget(const SizedBox.shrink());
    await app.runPos(mode: DeploymentMode.cloud);
    await tester.pump();
    await settle();
  }

  // ------------------------------------------------------------------- wizard

  /// Open the Setup Wizard the way an installer does: Ctrl+Shift+S on the
  /// welcome screen. A no-op when the wizard is already showing, so the
  /// driver works from either entry point.
  Future<void> openSetupFromWelcome() async {
    if (find.text('Continue').evaluate().isNotEmpty) return;
    await waitForText('XORDER');

    // Tap first, then chord. The screen takes focus on tap precisely so a
    // mouse user cannot disarm the only way in — and a second app boot in one
    // process does not always re-run autofocus, which is the test-harness
    // version of the same problem an operator hits after clicking around.
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.tap(find.text('XORDER'));
      await settle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle();
      if (find.text('Continue').evaluate().isNotEmpty) return;
    }
    fail('Ctrl+Shift+S did not open the setup wizard from the welcome screen');
  }

  /// Walk first-run setup for a till on a branch server, end to end.
  ///
  /// The database details are typed in rather than pre-seeded, so this covers
  /// the path an installer actually takes: address, credential, *Test
  /// connection*, and only then a licence and a pairing code.
  Future<void> completeSetup({
    required String databaseHost,
    required String databaseName,
    required int databasePort,
    required String databaseUser,
    required String databasePassword,
    String pairingCode = 'MAADI-7Q42',
    required String licenceFile,
    /// The platform this till syncs to. Phase 1 builds the CLOUD path only —
    /// the offline tile is dimmed until its phase lands — so the wizard is
    /// walked as a cloud install talking to a local API.
    required String platformUrl,
    required String tenantSlug,
  }) async {
    // 0 · The welcome screen. An unconfigured till shows the mark and nothing
    // else; the wizard opens on a chord an installer knows (phase-1 owner
    // decision), so a driver that walked straight into "Continue" was
    // testing a screen that no longer greets anybody.
    await openSetupFromWelcome();

    // 1 · Setup type. Cloud is preselected and Offline is dimmed until its
    // phase lands, so this step is a confirmation on both paths today.
    await tapButton('Continue');

    // 2 · Language.
    await tapButton('Continue');

    // 3 · Connection. The mode was settled on step 1; this step asks where
    // the platform is and where the till's own database lives. A cloud till
    // keeps a local PostgreSQL of its own — the sale is written there first
    // and drains afterwards — so the database fields matter on both paths.
    await enterField('Platform address', platformUrl);

    // Only offered when the licence covers more than one terminal — a one-till
    // plan has no shared database to point at, and the wizard does not ask.
    if (find.text('Database address').evaluate().isNotEmpty) {
      await enterField('Database address', databaseHost);
    }

    await enterField('Database name', databaseName);
    await enterField('Port', databasePort.toString());
    await enterField('Database user', databaseUser);
    await enterField('Database password', databasePassword);

    // The button an installer leans on. If it lies about a real database the
    // rest of this walk is worthless, so the suite spends a round trip on it.
    await tapButton('Test connection');
    await waitForNoSpinner();
    await tapButton('Continue');

    // 4 · Sign in, by pairing code — the provisioned path, where the branch and
    // the till name come back from the platform instead of being typed. On the
    // cloud path the tenant is typed here (no licence step precedes it: a
    // cloud licence rides the bootstrap bundle at registration).
    await enterField('Business', tenantSlug);
    await tapButton('Setup code');
    await enterField('Setup code', pairingCode);
    await tapButton('Claim this terminal');
    // The branch and the till name come back from the database, so the driver
    // must not assert what they are — only that the claim landed.
    await waitForTextContaining('Claimed as');
    await tapButton('Continue');

    // 5 · Branch and 6 · Terminal are confirmations on this path: the claim
    // already filled them in.
    await tapButton('Continue');
    await tapButton('Continue');

    // 7 · Hardware. Skipped deliberately — a till with nothing attached is a
    // valid till, and setup must not stall on one.
    await tapButton('Continue');

    // 8 · Money.
    await tapButton('Continue');

    // 9 · Catalogue.
    await tapButton('Download menu');
    await waitForTextContaining('items cached on this terminal');
    await tapButton('Continue');

    // 10 · Ready.
    await tapButton('Open the till');
    await settle();
  }

  /// Bring the app to rest before the test body ends.
  ///
  /// The live binding asserts no frame is pending at teardown, and a till that
  /// just settled a sale has a receipt dialog animating and a sync pass in
  /// flight. Pumping to quiet here is the honest way to end a test that drove
  /// real work — the alternative is a suite that passes its assertions and
  /// then fails on the way out.
  Future<void> quiesce() async {
    // Replace the app with an empty tree. That disposes the ProviderScope —
    // cancelling the sync loop's timers and every running animation — which
    // is the only reliable way to reach the live binding's teardown with no
    // frame pending. Pumping alone cannot win against a spinner: an
    // indeterminate progress indicator schedules frames forever by design.
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    } on Object {
      // Teardown must not fail a test whose assertions passed.
    }
  }

  // --------------------------------------------------------------------- till

  /// Sign in at Start, then start the shift from Home and open the drawer.
  ///
  /// Signing in and opening a shift are two steps now (pos-signin-first-home):
  /// Start asks who is at the till, Home's Start shift asks what is in the
  /// drawer. Both are load-bearing: a shift with no named person is a drawer
  /// nobody is answerable for, and a shift with no opening float makes every
  /// variance wrong by the same unknown amount.
  ///
  /// **Not run in this change** (needs a real PostgreSQL and the platform); it
  /// also types no user name, as it did not before the name-and-PIN sign-in.
  Future<void> openShift({required String pin}) async {
    await waitForText('Sign in');
    await tapButton('Sign in');

    await waitForText('Sign in');
    for (final digit in pin.split('')) {
      await tapButton(digit);
    }

    await waitForTextContaining('Start shift');
    await tapTextContaining('Start shift');

    // The float defaults to 0.00, which is what the dialog offers and what an
    // empty drawer actually holds.
    await waitForText('Open shift');
    await tapButton('Open shift');
  }

  /// Cash up: read the Z report, count the drawer, confirm.
  ///
  /// [counted] is what the person at the drawer says is in it. Passing the
  /// expected total is the balanced case; anything else records a variance.
  Future<void> closeShift({required String counted}) async {
    // Settling a seated ticket returns the cashier to the floor (that is the
    // point — the next thing they do is seat another table), and the
    // Close-shift control lives on the sale screen. Walk back the way a
    // cashier would: pick any table, then cash up.
    if (find.text('Close shift').evaluate().isEmpty) {
      final anyTable = find.byType(InkWell);
      if (anyTable.evaluate().isNotEmpty) {
        await tester.tap(anyTable.first);
        await settle();
      }
    }
    await waitForText('Close shift');
    await tapButton('Close shift');
    await waitForTextContaining('Close SHIFT');

    await tester.enterText(find.byType(TextField).last, counted);
    await settle();

    // Scoped to the dialog. The top bar behind it also says "Close shift", and
    // tapping that one does nothing at all — which looks exactly like a cash-up
    // that silently failed.
    final confirm = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('Close shift'),
    );
    expect(
      confirm,
      findsOneWidget,
      reason: 'the cash-up dialog should be showing',
    );
    await tester.tap(confirm);
    await settle();

    await waitForText('Done');
    await tapButton('Done');
  }

  /// What the Z report says should be in the drawer, read off the dialog.
  String expectedInDrawer() {
    final row = find.ancestor(
      of: find.text('Expected in drawer'),
      matching: find.byType(Row),
    );
    final texts = find
        .descendant(of: row.first, matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    return texts.last;
  }

  Future<void> seatTable(String label) async {
    await waitForText('Pick a table');
    await tapButton(label);
    await waitForText('CATEGORIES');
  }

  /// Tap a product tile. Only for products with no modifier groups — anything
  /// with one opens the sheet first, which is a different interaction.
  Future<void> addProduct(String name) async {
    // A real menu is hundreds of items across many categories, so the tile is
    // usually not on screen. Search is how a cashier finds one — and using it
    // here means the suite also proves the search index works against a real
    // catalogue rather than a five-item fixture.
    if (find.text(name).evaluate().isEmpty) {
      final search = find.byType(TextField).first;
      await tester.tap(search);
      await tester.enterText(search, name);
      await settle();
      await waitForText(name);
    }
    await tapButton(name);
  }

  /// Tap a product that carries a required modifier group, choose [option] and
  /// confirm. A required group blocks the sheet's own button until something is
  /// picked, so this is also a check that the group came back from the database
  /// still marked required.
  Future<void> addProductWithOption(String name, String option) async {
    await tapButton(name);
    await waitForText('Add to ticket');
    await tapButton(option);
    await tapButton('Add to ticket');
  }

  /// Open payment from the cart's primary call to action.
  ///
  /// The label is the till's own state: a seated ticket closes a table, a
  /// takeaway ticket charges. Matching on either keeps the driver honest about
  /// which one it actually pressed.
  Future<void> charge() async {
    final cta = find.textContaining(RegExp('CLOSE TABLE|CHARGE'));
    expect(
      cta,
      findsWidgets,
      reason: 'the cart should offer a way to take money',
    );
    await tester.tap(cta.first);
    await settle();
    await waitForText('TAKE PAYMENT');
  }

  /// Take the whole remaining balance in cash and wait for the receipt.
  ///
  /// An empty amount means "everything still due", which is the common case at
  /// a counter. The wait is what covers the database write: the receipt is
  /// shown only after the order has been submitted, so a receipt on screen is
  /// proof the write returned.
  Future<void> takePayment() async {
    await tapButton('TAKE PAYMENT');
    await waitForText('New sale');
  }

  Future<void> startNextSale() async {
    await tapButton('New sale');
    await settle();
  }

  /// The invoice number printed on the receipt currently on screen.
  ///
  /// Read off the slip rather than out of the database, because the point of
  /// asking is to compare the two.
  String receiptInvoiceNumber() {
    final printed = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data?.contains(RegExp(r'^[A-Z]+-\d{4}-\d{6}$')) ?? false),
    );
    expect(
      printed,
      findsOneWidget,
      reason: 'the receipt must carry exactly one invoice number',
    );
    return (printed.evaluate().single.widget as Text).data!;
  }

  // ------------------------------------------------------------------ finding

  /// The text field belonging to a labelled wizard row.
  ///
  /// Both `_Field` and `_PasswordField` render a `MicroLabel` — which
  /// uppercases — directly above their input, inside one `Column`. The nearest
  /// `Column` ancestor of that label is therefore the field itself.
  Finder fieldNamed(String label) => find.descendant(
    of: find
        .ancestor(
          of: find.text(label.toUpperCase()),
          matching: find.byType(Column),
        )
        .first,
    matching: find.byType(TextFormField),
  );

  // ------------------------------------------------------------------ actions

  Future<void> enterField(String label, String value) async {
    final field = fieldNamed(label);
    await show(field);
    await tester.enterText(field, value);
    await settle();
  }

  Future<void> tapButton(String label) async {
    final target = find.text(label);
    expect(target, findsWidgets, reason: 'nothing on screen says "$label"');
    await show(target.first);
    await tester.tap(target.first);
    await settle();
  }

  Future<void> tapTextContaining(String fragment) async {
    final target = find.textContaining(fragment);
    expect(
      target,
      findsWidgets,
      reason: 'nothing on screen contains "$fragment"',
    );
    await show(target.first);
    await tester.tap(target.first);
    await settle();
  }

  /// Scroll something into view before touching it.
  ///
  /// The connection step is taller than the window on purpose — it asks for an
  /// address, a credential and four database fields — so half of it is off
  /// screen when the step opens.
  Future<void> show(Finder finder) async {
    if (finder.evaluate().isEmpty) return;
    await tester.ensureVisible(finder);
    await settle();
  }

  /// Every piece of text currently rendered, for diagnosing a failed wait.
  List<String> visibleText() => [
    for (final element in find.byType(Text).evaluate())
      if ((element.widget as Text).data?.trim().isNotEmpty ?? false)
        (element.widget as Text).data!.trim(),
  ];

  // ------------------------------------------------------------------ waiting

  Future<void> settle() => tester.pumpAndSettle();

  /// Pump on the real clock until [finder] matches.
  ///
  /// `pumpAndSettle` is not enough on its own anywhere real work happens.
  /// Neither a PostgreSQL round trip nor a `Future.delayed` schedules a frame,
  /// so settling reports quiet while the work is still in flight. Waiting on
  /// the *outcome* is both correct and a better failure message than a sleep
  /// that turned out to be too short.
  Future<void> waitFor(
    Finder finder, {
    String? describedAs,
    Duration timeout = patience,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) {
        await settle();
        return;
      }
    }
    // Say what *was* on screen. "It never appeared" on its own sends you
    // digging through a UI you cannot see; the screen the till was actually
    // showing is usually the whole answer — an error banner, a spinner, or the
    // wrong step entirely.
    fail(
      'Waited ${timeout.inSeconds}s for ${describedAs ?? finder.toString()}, '
      'and it never appeared.\n\nOn screen instead:\n${visibleText().join('\n')}',
    );
  }

  Future<void> waitForText(String text) =>
      waitFor(find.text(text), describedAs: '"$text" on screen');

  Future<void> waitForTextContaining(String fragment) => waitFor(
    find.textContaining(fragment),
    describedAs: 'text containing "$fragment"',
  );

  /// Wait for the wizard to stop being busy.
  ///
  /// Used after *Test connection*, which has no visible success state of its
  /// own — the absence of the spinner and of an error is the result.
  Future<void> waitForNoSpinner({Duration timeout = patience}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        await settle();
        return;
      }
    }
    fail('The wizard was still busy after ${timeout.inSeconds}s.');
  }
}
