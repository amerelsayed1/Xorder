import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/receipt_profile.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/admin_pane_bits.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_receipt_pane.dart';
import 'package:shared_module/features/receipt/receipt_data.dart';
import 'package:shared_module/features/receipt/receipt_paper.dart';
import 'package:shared_module/features/receipt/receipt_qr.dart';

/// Who the receipt says sold the food, on screen.
///
/// Two things are worth pinning here and neither is the form itself. The pane
/// must let a half-finished profile be saved, because that is how one is
/// actually filled in. And the slip must print **nothing** where it has
/// nothing — the line it replaced read `TAX REG 000-000-000` on every receipt
/// this product has ever printed.
void main() {
  const admin = PosStaff(
    id: 4,
    name: 'Mona Fahmy',
    capabilities: {PosCapability.settingsManage},
  );

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
    phone: '+20 2 2577 5935',
    footerNote: 'Open until 2am',
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    // Tall enough for the whole form. The save button is the last child of a
    // lazy `ListView`, and dragging it into view instead means dragging across
    // a text field, which starts a selection rather than a scroll.
    view.physicalSize = const Size(1440, 2600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget host(Widget child, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  group('the pane', () {
    Future<_Profiles> pump(
      WidgetTester tester, {
      ReceiptProfile stored = const ReceiptProfile(branchId: 1),
      AdminRefusal? refuse,
      bool files = true,
      bool authors = true,
    }) async {
      final repository = _Profiles(stored, refuse: refuse);
      await tester.pumpWidget(
        host(
          const ManagementReceiptPane(admin: admin),
          overrides: [
            receiptProfileRepositoryProvider.overrideWithValue(repository),
            // On, so the filing half of the pane is exercised; the builds
            // that ship with it off have their own case below.
            etaFilingEnabledProvider.overrideWithValue(files),
            // An OFFLINE till by default, which is the only deployment that
            // authors this at all (CB-08). Left to the real provider every
            // case below would silently become the read-only cloud pane and
            // still pass its "nothing was saved" assertions — so the
            // deployment is stated rather than inherited, the way
            // `offlineTerminal()` states it for the back-office shell.
            catalogAdminRepositoryProvider.overrideWithValue(
              authors ? _Catalogue() : null,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    /// The form is taller than the pane, and the save button lives at the
    /// bottom of it. `ensureVisible` cannot reach a `ListView` child that was
    /// never built.
    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('receipt-profile-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('what General hands in as leading sits above the form, and '
        'sections below it', (tester) async {
      final repository = _Profiles(const ReceiptProfile(branchId: 1));
      await tester.pumpWidget(
        host(
          const ManagementReceiptPane(
            admin: admin,
            leading: [SizedBox(key: Key('lead'), height: 40)],
            sections: [SizedBox(key: Key('tail'), height: 40)],
          ),
          overrides: [
            receiptProfileRepositoryProvider.overrideWithValue(repository),
            etaFilingEnabledProvider.overrideWithValue(false),
            catalogAdminRepositoryProvider.overrideWithValue(_Catalogue()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final lead = tester.getTopLeft(find.byKey(const Key('lead'))).dy;
      final firstField = tester.getTopLeft(find.byType(TextField).first).dy;
      expect(lead, lessThan(firstField), reason: 'leading is above the form');
      expect(find.byKey(const Key('lead')), findsOneWidget);
      // The form's own Save stays the form's: the leading widget is not in it.
      await tester.scrollUntilVisible(
        find.byKey(const Key('tail')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('tail'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('receipt-profile-save'))).dy,
        ),
        reason: 'sections stay under the form',
      );
    });

    testWidgets('a branch nobody has set up says so, rather than complaining', (
      tester,
    ) async {
      await pump(tester);

      // "Not set up yet" is a much less alarming sentence on day one than
      // "seven problems", and it is the true one.
      expect(find.textContaining('Not set up yet'), findsOneWidget);
    });

    testWidgets('with e-receipts off, the paper is all it asks about', (
      tester,
    ) async {
      await pump(
        tester,
        stored: const ReceiptProfile(branchId: 1, tradeName: 'Koshari'),
        files: false,
      );

      // No banner, no activity or branch code, and no complaint about an
      // address a business that files nothing does not have to give.
      expect(find.textContaining('Incomplete.'), findsNothing);
      expect(find.textContaining('Not set up yet'), findsNothing);
      expect(find.text('An activity code is four digits.'), findsNothing);
      expect(find.text('A street is required.'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(14));
    });

    testWidgets('a complete profile says it can be filed', (tester) async {
      await pump(tester, stored: complete);
      expect(find.textContaining('Complete.'), findsOneWidget);
    });

    testWidgets('a half-typed profile warns without blocking', (tester) async {
      await pump(
        tester,
        stored: const ReceiptProfile(branchId: 1, tradeName: 'Koshari'),
      );
      expect(find.textContaining('Incomplete.'), findsOneWidget);
    });

    testWidgets('the warning follows the typing, not the save', (tester) async {
      final repository = await pump(tester, stored: complete);
      expect(find.textContaining('Complete.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).at(4), // the registration number
        '1234',
      );
      await tester.pumpAndSettle();

      // Under the operator's hands, before anything is written.
      expect(find.textContaining('Incomplete.'), findsOneWidget);
      expect(repository.saved, isEmpty);
    });

    testWidgets('a problem is printed under the box it belongs to', (
      tester,
    ) async {
      await pump(tester, stored: complete);
      await tester.enterText(find.byType(TextField).at(4), '1234');
      await tester.pumpAndSettle();

      expect(
        find.text('A tax registration number is nine digits.'),
        findsOneWidget,
      );
    });

    testWidgets('a half-finished profile saves anyway', (tester) async {
      final repository = await pump(
        tester,
        stored: const ReceiptProfile(branchId: 1, tradeName: 'Koshari'),
      );

      await save(tester);

      // This is how one is actually filled in — the name today, the activity
      // code after a phone call to the accountant.
      expect(repository.saved.single.tradeName, 'Koshari');
      expect(repository.saved.single.canFile, isFalse);
    });

    testWidgets('what was typed is what is handed to the repository', (
      tester,
    ) async {
      final repository = await pump(tester, stored: complete);

      await tester.enterText(find.byType(TextField).first, 'Koshari Downtown');
      await tester.pumpAndSettle();
      await save(tester);

      final saved = repository.saved.single;
      expect(saved.tradeName, 'Koshari Downtown');
      expect(saved.registrationNumber, '123456789', reason: 'and the rest');
      expect(saved.address.street, 'Champollion');
    });

    testWidgets('the slip beside the form follows the typing', (tester) async {
      // What the customer will be handed, while it is being written — not
      // after a save, a sale and a test print.
      final repository = await pump(tester, stored: complete);
      expect(find.byKey(const Key('receipt-profile-preview')), findsOneWidget);
      expect(find.text('KOSHARI ABOU TAREK'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Koshari Downtown');
      await tester.pumpAndSettle();

      expect(find.text('KOSHARI DOWNTOWN'), findsOneWidget);
      expect(find.text('KOSHARI ABOU TAREK'), findsNothing);
      expect(repository.saved, isEmpty, reason: 'previewed, not saved');
    });

    testWidgets('a second save carries the revision the first one returned', (
      tester,
    ) async {
      final repository = await pump(tester, stored: complete);

      await save(tester);
      await save(tester);

      // Without this the pane would be refused as an edit from elsewhere — by
      // itself, on the second press.
      expect(repository.saved.map((p) => p.revision), [0, 1]);
    });

    testWidgets('a refusal is shown and nothing is claimed', (tester) async {
      await pump(
        tester,
        stored: complete,
        refuse: const NotPermitted(PosCapability.settingsManage),
      );

      await save(tester);

      expect(find.textContaining('Saved.'), findsNothing);
    });

    group('on a cloud till, where the platform authors this', () {
      testWidgets('it says so, and names where the boxes are typed', (
        tester,
      ) async {
        await pump(tester, stored: complete, authors: false);

        expect(find.byType(PlatformOwnedNotice), findsOneWidget);
        // The sentence has to answer "then where?", not merely "not here".
        expect(find.textContaining('dashboard'), findsOneWidget);
        expect(find.textContaining('Receipt details'), findsOneWidget);
        // And not the explanation that says these facts are typed here, which
        // is the one thing that is no longer true.
        expect(find.textContaining('typed here and read from here'), findsNothing);
      });

      testWidgets('there is no Save, because a sync would erase what it wrote', (
        tester,
      ) async {
        await pump(tester, stored: complete, authors: false);

        // Absent rather than disabled: `BootstrapSeeder` upserts this table
        // now, so a local edit would live until the next bundle and then
        // vanish — after the manager watched it save.
        expect(find.byKey(const Key('receipt-profile-save')), findsNothing);
      });

      testWidgets('every box is read-only, and none of them is hidden', (
        tester,
      ) async {
        final repository = await pump(
          tester,
          stored: complete,
          authors: false,
        );

        final boxes = tester.widgetList<TextField>(find.byType(TextField));
        expect(boxes, hasLength(16), reason: 'shown, not taken away');
        expect(boxes.every((f) => f.readOnly), isTrue);

        // Typing into a read-only field changes nothing, and there is nothing
        // to press if it did.
        await tester.enterText(find.byType(TextField).first, 'Somewhere Else');
        await tester.pumpAndSettle();
        expect(find.text('KOSHARI ABOU TAREK'), findsOneWidget);
        expect(repository.saved, isEmpty);
      });

      testWidgets('the slip is still beside it, which is why the pane stays', (
        tester,
      ) async {
        // Unlike Menu or Purchasing this pane is not hidden on cloud: it is
        // the one screen that answers "what does our receipt say", and
        // somebody checking a registration number before an audit reads it at
        // the till that prints it.
        await pump(tester, stored: complete, authors: false);

        expect(find.byKey(const Key('receipt-profile-preview')), findsOneWidget);
        expect(find.text('TAX REG 123456789'), findsOneWidget);
        expect(find.textContaining('Complete.'), findsOneWidget);
      });
    });
  });

  group('the slip', () {
    ReceiptData data() => ReceiptData(
      orderType: OrderType.takeaway,
      occurredAt: DateTime(2026, 9, 8, 13),
      lines: const [
        ReceiptLine(name: 'Koshari', quantity: 1, lineTotal: Money(4500)),
      ],
      subtotal: const Money(4500),
      discount: Money.zero,
      service: Money.zero,
      vat: const Money(630),
      total: const Money(5130),
      paid: const Money(5130),
      change: Money.zero,
      invoiceNumber: 'INV-0001',
    );

    Future<void> pumpSlip(WidgetTester tester, ReceiptProfile profile) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: ReceiptPaper(
              data: data(),
              profile: profile,
              tenantName: 'XOrder Demo',
              terminalCode: 'T1',
              cashierName: 'Rana',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an unset profile prints no tax registration number at all', (
      tester,
    ) async {
      await pumpSlip(tester, const ReceiptProfile(branchId: 1));

      // The line this replaced read `TAX REG 000-000-000` on every receipt
      // this product ever printed — a fabricated registration number on a
      // document a customer keeps. A blank space is not a compliance problem;
      // a made-up number is.
      expect(find.textContaining('TAX REG'), findsNothing);
      expect(find.textContaining('000-000-000'), findsNothing);
    });

    testWidgets('an unset profile still prints, under the tenant name', (
      tester,
    ) async {
      await pumpSlip(tester, const ReceiptProfile(branchId: 1));
      expect(find.text('XORDER DEMO'), findsOneWidget);
    });

    testWidgets('the profile name wins over the session tenant', (
      tester,
    ) async {
      await pumpSlip(tester, complete);
      expect(find.text('KOSHARI ABOU TAREK'), findsOneWidget);
      expect(find.text('XORDER DEMO'), findsNothing);
    });

    testWidgets('the registration number prints when there is one', (
      tester,
    ) async {
      await pumpSlip(tester, complete);
      expect(find.text('TAX REG 123456789'), findsOneWidget);
    });

    testWidgets('the address prints only the parts that were filled in', (
      tester,
    ) async {
      await pumpSlip(tester, complete);
      expect(find.text('16, Champollion, Downtown, Cairo'), findsOneWidget);
    });

    testWidgets("the business's own footer prints", (tester) async {
      await pumpSlip(tester, complete);
      expect(find.text('Open until 2am'), findsOneWidget);
    });

    testWidgets('no QR prints until the receipt has been sealed', (
      tester,
    ) async {
      // On a till selling through an outage the seal may land minutes or hours
      // after the slip was handed over. ETA allow twenty-four hours, so the
      // slip prints without a square rather than with a broken one.
      await pumpSlip(tester, complete);
      expect(find.byType(ReceiptQr), findsNothing);
    });

    testWidgets('a sealed receipt prints its QR', (tester) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: ReceiptPaper(
              data: ReceiptData(
                orderType: OrderType.takeaway,
                occurredAt: DateTime(2026, 9, 8, 13),
                lines: const [
                  ReceiptLine(
                    name: 'Koshari',
                    quantity: 1,
                    lineTotal: Money(4500),
                  ),
                ],
                subtotal: const Money(4500),
                discount: Money.zero,
                service: Money.zero,
                vat: const Money(630),
                total: const Money(5130),
                paid: const Money(5130),
                change: Money.zero,
                invoiceNumber: 'INV-0001',
                etaQrPayload: 'https://example.invalid/r/abc123',
              ),
              profile: complete,
              tenantName: 'XOrder Demo',
              terminalCode: 'T1',
              cashierName: 'Rana',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptQr), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone number stays left to right', (tester) async {
      await pumpSlip(tester, complete);
      final phone = find.text('+20 2 2577 5935');
      expect(Directionality.of(tester.element(phone)), TextDirection.ltr);
    });
  });
}

/// Stands in for "this terminal authors its own configuration", which is what
/// `catalogAdminRepositoryProvider` answers. Nothing here calls it: the pane
/// only asks whether it is bound.
class _Catalogue implements CatalogAdminRepository {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('the pane only asks whether this is bound');
}

class _Profiles implements ReceiptProfileRepository {
  _Profiles(this._stored, {this.refuse});

  ReceiptProfile _stored;
  final AdminRefusal? refuse;

  final saved = <ReceiptProfile>[];

  @override
  Future<ReceiptProfile> load() async => _stored;

  @override
  Future<AdminResult<ReceiptProfile>> save(
    ReceiptProfile profile, {
    required PosStaff by,
  }) async {
    if (refuse != null) return AdminResult.refused(refuse!);
    saved.add(profile);
    _stored = profile.copyWith(revision: profile.revision + 1);
    return AdminResult.done(_stored);
  }
}
