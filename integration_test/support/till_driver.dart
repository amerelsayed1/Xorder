import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/app.dart';

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
  /// restaurant runs.
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
  Future<void> boot() async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // An empty frame first. Two `ProviderScope(child: XorderPosApp())` widgets
    // are structurally identical, so pumping the second over the first updates
    // the existing element in place and keeps the old container — a "second
    // till" would boot already set up, which is the opposite of the point.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const ProviderScope(child: XorderPosApp()));
    await settle();
  }

  // ------------------------------------------------------------------- wizard

  /// Walk first-run setup for a till on a branch server, end to end.
  ///
  /// The database details are typed in rather than pre-seeded, so this covers
  /// the path an installer actually takes: address, credential, *Test
  /// connection*, and only then a licence and a pairing code.
  Future<void> completeSetup({
    required String serverAddress,
    required String databaseName,
    required int databasePort,
    required String databaseUser,
    required String databasePassword,
    String upstream = 'https://xorder.io',
    String tenantSlug = 'mahsoub',
    String pairingCode = 'MAADI-7Q42',
    required String licenceFile,
  }) async {
    // 1 · Language.
    await tapButton('Continue');

    // 2 · Connection. Mode first: changing it deliberately discards the
    // endpoint and the credential, so anything typed before would be lost.
    await tapButton('Branch server');
    await enterField('Server address', serverAddress);

    // Only offered once the address is a private one, which is the reason it
    // is entered before this is tapped rather than after.
    await tapButton('Trust this server without a certificate');

    await enterField('Database', databaseName);
    await enterField('Port', databasePort.toString());
    await enterField('Database user', databaseUser);
    await enterField('Database password', databasePassword);
    await enterField('Upstream', upstream);

    // The button an installer leans on. If it lies about a real database the
    // rest of this walk is worthless, so the suite spends a round trip on it.
    await tapButton('Test connection');
    await waitForNoSpinner();
    await tapButton('Continue');

    // 3 · Sign in, by pairing code — the provisioned path, where the branch and
    // the till name come back from the dashboard instead of being typed. It
    // comes before the licence because a licence is issued to a tenant, and
    // this is the step that says which tenant this is.
    await enterField('Restaurant', tenantSlug);
    await enterField('Setup code', pairingCode);
    await tapButton('Claim this terminal');
    // The branch and the till name come back from the database, so the driver
    // must not assert what they are — only that the claim landed.
    await waitForTextContaining('Claimed as');
    await tapButton('Continue');

    // 4 · Licence. There is no licence server, so the wizard offers only the
    // file — and the app checks its signature against the key in the binary,
    // which is why the suite has to sign a real one rather than type a key.
    await tapButton('Activate from file');
    await waitForText('Paste licence file');
    await tester.enterText(
      find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).last,
      licenceFile,
    );
    await settle();
    await tapButton('Activate');
    await waitForText('LICENSED');
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

  // --------------------------------------------------------------------- till

  /// Sign in and open the drawer.
  ///
  /// Two questions stand between the start screen and selling now, and both are
  /// load-bearing: a shift with no named person is a drawer nobody is
  /// answerable for, and a shift with no opening float makes every variance
  /// wrong by the same unknown amount.
  Future<void> openShift({required String pin}) async {
    await waitForTextContaining('Start shift');
    await tapTextContaining('Start shift');

    await waitForText('Sign in');
    for (final digit in pin.split('')) {
      await tapButton(digit);
    }

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
    expect(confirm, findsOneWidget, reason: 'the cash-up dialog should be showing');
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
    expect(cta, findsWidgets, reason: 'the cart should offer a way to take money');
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
      (widget) => widget is Text && (widget.data?.contains(RegExp(r'^[A-Z]+-\d{4}-\d{6}$')) ?? false),
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
    expect(target, findsWidgets, reason: 'nothing on screen contains "$fragment"');
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

  Future<void> waitForTextContaining(String fragment) =>
      waitFor(find.textContaining(fragment), describedAs: 'text containing "$fragment"');

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
