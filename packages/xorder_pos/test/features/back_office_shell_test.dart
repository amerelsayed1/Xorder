import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/combo_draft.dart';
import 'package:xorder_pos/domain/models/option_group.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/refund_history.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart'
    show etaFilingEnabled;
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_home_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/history/presentation/order_history_screen.dart';
import 'package:xorder_pos/features/history/presentation/refund_detail_pane.dart';

import '../support/back_office.dart';
import '../support/fakes.dart';
import '../support/fonts.dart';

// Everybody who could be standing in the back office, each holding what they
// hold through a ROLE where a real one would — `PosStaff.capabilities` is
// direct grants only — plus one who holds everything by direct grant, because
// that is a real shape too and the gate has to read both.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
const _manager = PosStaff(
  id: 2,
  name: 'Mona F.',
  username: 'mona',
  role: PosRole(
    id: 2,
    code: SystemRoles.managerCode,
    nameEn: 'Manager',
    capabilities: {...SystemRoles.manager, PosCapability.adminEnter},
  ),
);
// Let into Admin Mode by the owner, and not into buying.
const _supervisor = PosStaff(
  id: 3,
  name: 'Nour S.',
  username: 'nour',
  role: FakeSessionRepository.trustedSupervisor,
);
const _granted = PosStaff(
  id: 4,
  name: 'Hady K.',
  username: 'hady',
  capabilities: {
    PosCapability.adminEnter,
    PosCapability.staffManage,
    PosCapability.purchaseManage,
  },
);
// The machine and its copies, and nothing of the business.
const _keeper = PosStaff(
  id: 5,
  name: 'Salma T.',
  username: 'salma',
  role: PosRole(
    id: 5,
    code: 'keeper',
    nameEn: 'Keeper',
    capabilities: {
      PosCapability.adminEnter,
      PosCapability.backupManage,
      PosCapability.terminalManage,
    },
  ),
);

const _fixtures = <String, PosStaff>{
  'owner': _owner,
  'manager': _manager,
  'supervisor': _supervisor,
  'direct grant': _granted,
  'keeper': _keeper,
};

/// The tabs whose content is a later slice. None of them holds a pane yet.
/// Home, Sales, Reports and Finance left this list with BO-4, BO-2, BO-6 and
/// BO-9.
const _later = <BackOfficeTab>[];

/// Finance's panes, in the order its bar menu lists them: Overview and Revenue,
/// then the owner's map's الخزينة، المصروفات، التسويات، الضرائب, in its order
/// (payments left for Reports, XORD-022-A), then Bills due and Transactions (BO-9, BO-10, `pos/ia-screens`).
const _finance = [
  ManagementPane.financeOverview,
  ManagementPane.financeRevenue,
  ManagementPane.financeDrawers,
  ManagementPane.financeExpenses,
  ManagementPane.settlements,
  ManagementPane.financeTaxes,
  ManagementPane.financeBills,
  ManagementPane.financeTransactions,
  ManagementPane.financeProfitLoss,
  // Last, and only for somebody holding `finance.accounts` (XORD-015).
  ManagementPane.financeAccounts,
];

/// Reports' panes, in the order its bar menu lists them: Business summary and
/// the owner's map's five breakdowns.
const _reports = [
  ManagementPane.reports,
  ManagementPane.reportsSales,
  ManagementPane.reportsItems,
  ManagementPane.reportsPayments,
  ManagementPane.reportsBranches,
  ManagementPane.reportsEmployees,
];

/// What [admin] has of [_finance]: all of it where the supplier ledger is
/// theirs to read here — offline, with `purchase.manage` — and all but Bills
/// due otherwise (BO-10).
List<ManagementPane> _financeFor(PosStaff admin, {required bool authors}) => [
  for (final pane in _finance)
    if ((pane != ManagementPane.financeBills ||
            (authors &&
                Authorization.check(
                  admin,
                  PosCapability.purchaseManage,
                ).isAllowed)) &&
        (pane != ManagementPane.financeAccounts ||
            Authorization.check(admin, PosCapability.financeAccounts)
                .isAllowed))
      pane,
];

/// An offline till's catalogue administrator that can be LOOKED at.
///
/// `offlineTerminal()` binds a bare mock, which is right for a test that only
/// asks whether this till authors — and wrong for one that opens every pane,
/// because Extras reads its library, and Combos its list, the moment they
/// show. Those reads are the only ones an authoring pane makes unprompted;
/// everything else is a write behind a button the walk never presses, and
/// stays unanswered on purpose.
class _OfflineCatalogue extends Mock implements CatalogAdminRepository {
  _OfflineCatalogue() {
    when(optionLibrary).thenAnswer((_) async => const <LibraryGroup>[]);
    when(combos).thenAnswer((_) async => const <ComboDraft>[]);
  }
}

/// The panes on screen right now, read off the key the shell puts on each.
Set<ManagementPane> _showing(WidgetTester tester) => {
  for (final element
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'back-office-pane-',
                ),
          )
          .evaluate())
    ManagementPane.values.byName(
      (element.widget.key! as ValueKey<String>).value.substring(
        'back-office-pane-'.length,
      ),
    ),
};

/// The back office through its door, in [language], at [width] — and the
/// route the bar would move it along, since that is the only way between its
/// pages.
Future<(ProviderContainer, BarRoute)> _open(
  WidgetTester tester, {
  ManagementPane? pane,
  bool offline = false,
  String language = 'en',
  double width = 1440,
  String username = 'amer',
  String pin = '4321',
  List<Override> overrides = const [],
  VoidCallback? onClose,
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      if (offline)
        catalogAdminRepositoryProvider.overrideWithValue(_OfflineCatalogue()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  final bar = BarRoute(pane);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: bar.screen(onClose: onClose),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await enterAdminMode(tester, username: username, pin: pin);
  return (container, bar);
}

/// The bar's menus as whoever is in Admin Mode has them, on this till.
List<ManagementBarMenu> _barOf(ProviderContainer container) => managementBarFor(
  const EnStrings(),
  admin: container.read(adminSessionProvider)!.staff,
  authorsItsOwnCatalogue:
      container.read(catalogAdminRepositoryProvider) != null,
);

/// Every line of the window's bar, followed as the bar follows it, and every
/// row of Settings' side nav under the page it lands on — what a person can
/// reach by pointing, collected as they reach it.
///
/// A line that starts something new — Purchasing's "New order" and its kin —
/// is passed over: it opens the same pane as the list line beside it, with a
/// form over it the walk would then have to close.
Future<Set<ManagementPane>> _walk(
  WidgetTester tester,
  ProviderContainer container,
  BarRoute bar,
) async {
  final seen = <ManagementPane>{..._showing(tester)};
  for (final menu in _barOf(container)) {
    for (final line in menu.lines) {
      final to = line.open();
      if (to.create) continue;
      await bar.go(tester, to);
      seen.addAll(_showing(tester));
      for (final pane in ManagementPane.values) {
        final row = find.byKey(Key('back-office-settings-${pane.name}'));
        if (row.evaluate().isNotEmpty) {
          await tester.tap(row);
          await tester.pumpAndSettle();
          seen.addAll(_showing(tester));
        }
      }
    }
  }
  return seen;
}

/// The back office's shell: the owner's ten tabs as the window's bar draws
/// them, Settings' side nav, a status bar — and not one pane more or less than
/// before.
///
/// **Re-hosting, so the claim is equality.** Every pane a person could open
/// through the old flat bar they can open through the tabs' menus, and
/// nothing else; `managementPanesFor` is the rule that was there before BO-1
/// and is unchanged by it, so it is what the tabs are held to.
///
/// **No strip and no sub-nav since 15 Sep 2026** — the owner's words: "no
/// need for this, use same design only on the top menu". So "reachable by
/// pointing" means reachable through the bar's lines and Settings' side nav,
/// and that is what [_walk] points at.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled faces, not the test font. The test font draws every glyph a
  // full em wide, which is a measurement of nothing: "every page lays out at
  // 1100 px" is a claim about IBM Plex Sans Arabic, in both of its scripts.
  setUpAll(loadPosFonts);

  group('the tabs reach exactly what the back office reached before', () {
    for (final MapEntry(key: name, value: admin) in _fixtures.entries) {
      for (final authors in [true, false]) {
        final where = authors ? 'offline' : 'cloud';
        test('$name, $where', () {
          final before = managementPanesFor(
            admin: admin,
            authorsItsOwnCatalogue: authors,
          );
          final tabs = backOfficeTabsFor(
            admin: admin,
            authorsItsOwnCatalogue: authors,
          );
          final reachable = [for (final (_, own) in tabs) ...own];

          expect(reachable.toSet(), before.toSet());
          expect(reachable, hasLength(before.length), reason: 'no pane twice');

          for (final (tab, own) in tabs) {
            for (final pane in own) {
              expect(tabOf(pane), tab, reason: pane.name);
            }
            // A tab with no visible pane is absent — bar the two a cloud till
            // keeps as pointers to the platform.
            if (own.isEmpty) {
              expect(authors, isFalse, reason: tab.name);
              expect(
                tab,
                isIn(const [BackOfficeTab.inventory, BackOfficeTab.purchasing]),
              );
            }
          }
          for (final tab in _later) {
            expect(
              [for (final (t, _) in tabs) t],
              isNot(contains(tab)),
              reason: '${tab.name} has no pane until its slice lands',
            );
          }
          // Sales for everybody past the door (BO-2): one page, holding the
          // list with its filters and the Returns view — whose sales is the
          // rows' scope, not a gate.
          expect(
            [
              for (final (t, own) in tabs)
                if (t == BackOfficeTab.sales) own,
            ],
            [
              [ManagementPane.sales],
            ],
            reason: '$name, $where',
          );

          // Reports for whoever holds `reports.view` — the owner and the
          // manager through their roles, nobody else here — holding Business
          // summary (BO-6) and the map's five breakdowns, in its order, on
          // both deployments: the figures are the branch's own rows, not the
          // platform's.
          final reads = Authorization.check(
            admin,
            PosCapability.reportsView,
          ).isAllowed;

          // The panes `pos/ia-screens` built, each behind exactly its own
          // gate and no other: Shifts and Settlements are `reports.view`, as
          // the panes' `requires` say, so whoever lacks it sees neither;
          // Printer is `terminal.manage`, as the till's dialog is; the rest
          // are everybody's past the door, on both deployments.
          final machine = Authorization.check(
            admin,
            PosCapability.terminalManage,
          ).isAllowed;
          for (final (pane, allowed) in [
            (ManagementPane.shifts, reads),
            (ManagementPane.settlements, reads),
            (ManagementPane.printer, machine),
            (ManagementPane.sync, true),
            (ManagementPane.user, true),
            (ManagementPane.about, true),
          ]) {
            expect(
              reachable.contains(pane),
              allowed,
              reason: '${pane.name}, $name, $where',
            );
          }
          expect(
            [
              for (final (t, own) in tabs)
                if (t == BackOfficeTab.reports) own,
            ],
            reads ? [_reports] : isEmpty,
            reason: '$name, $where',
          );

          // Finance for whoever holds `reports.view` — through the role or
          // directly, asked the one way — on both deployments; absent for
          // everybody else (BO-9). Bills due only offline and with
          // `purchase.manage` as well (BO-10): the direct-grant fixture holds
          // purchasing and not the reports, so it has no Finance at all.
          expect(
            [
              for (final (t, own) in tabs)
                if (t == BackOfficeTab.finance) own,
            ],
            Authorization.check(admin, PosCapability.reportsView).isAllowed
                ? [_financeFor(admin, authors: authors)]
                : isEmpty,
            reason: '$name, $where',
          );

          // Home is everybody's, and first — so the door lands on it.
          expect(tabs.first.$1, BackOfficeTab.home);
          expect(tabs.first.$2, [ManagementPane.home]);
          expect(backOfficeLanding(tabs), ManagementPane.home);

          // The bar: a menu per tab, in the same order, and no line reaching
          // what the tabs do not.
          final bar = managementBarFor(
            const EnStrings(),
            admin: admin,
            authorsItsOwnCatalogue: authors,
          );
          expect(
            [for (final menu in bar) menu.tab],
            [for (final (tab, _) in tabs) tab],
          );
          // Home is a word that opens itself (15 Sep 2026), and so is Sales
          // (one page, with filters and a Returns switch); every other word is
          // a menu. Their one line each is still the model's.
          expect(
            [
              for (final menu in bar)
                if (menu.direct) menu.tab,
            ],
            [BackOfficeTab.home, BackOfficeTab.sales],
          );
          expect(bar.first.lines.single.open().pane, ManagementPane.home);
          expect(
            bar
                .firstWhere((m) => m.tab == BackOfficeTab.sales)
                .lines
                .single
                .open()
                .pane,
            ManagementPane.sales,
          );
          for (final menu in bar) {
            for (final line in menu.lines) {
              final to = line.open().pane!;
              expect(tabOf(to), menu.tab, reason: line.label);
              if (line.pane == null) {
                expect(
                  hiddenBecausePlatformAuthors(
                    to,
                    authorsItsOwnCatalogue: authors,
                  ),
                  isTrue,
                  reason: line.label,
                );
              } else {
                expect(reachable, contains(to), reason: line.label);
              }
            }
          }

          // …and the other way: every item is a line of its menu, and the
          // items hold every pane of the tab — Settings' side-nav panes
          // through the item that holds them, Purchasing through its own
          // lines. So the bar and `managementPanesFor` are one set, gates
          // included — which, with no strip, is what makes every pane
          // reachable at all.
          for (final (tab, own) in tabs) {
            if (own.isEmpty) continue;
            final items = backOfficeItemsFor(const EnStrings(), tab, own);
            expect(
              {for (final item in items) ...item.holds},
              own.toSet(),
              reason: tab.name,
            );
            expect(
              {
                for (final line in bar.firstWhere((m) => m.tab == tab).lines)
                  line.pane,
              },
              {for (final item in items) item.opens},
              reason: tab.name,
            );
          }
        });
      }
    }
  });

  group('and by pointing, not only by the rule', () {
    for (final (name, username, pin) in [
      ('the owner', 'amer', '4321'),
      ('a supervisor who does not buy', 'nour', '2468'),
    ]) {
      for (final offline in [true, false]) {
        final where = offline ? 'offline' : 'cloud';
        testWidgets('$name, $where', (tester) async {
          final (container, bar) = await _open(
            tester,
            offline: offline,
            username: username,
            pin: pin,
          );
          final admin = container.read(adminSessionProvider)!.staff;

          expect(
            await _walk(tester, container, bar),
            managementPanesFor(
              admin: admin,
              authorsItsOwnCatalogue: offline,
            ).toSet(),
          );
          final menus = [for (final menu in _barOf(container)) menu.tab];
          for (final tab in _later) {
            expect(menus, isNot(contains(tab)), reason: tab.name);
          }
          expect(
            menus.contains(BackOfficeTab.finance),
            Authorization.check(admin, PosCapability.reportsView).isAllowed,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('Finance: eleven lines of its bar menu, in the map\'s order, each '
      'opening its own page', (tester) async {
    final (container, bar) = await _open(tester, offline: true);
    final finance = _barOf(container)
        .firstWhere((menu) => menu.tab == BackOfficeTab.finance);

    expect([for (final line in finance.lines) line.pane], _finance);
    for (final line in finance.lines) {
      await bar.go(tester, line.open());
      expect(_showing(tester), {line.pane}, reason: line.label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a cloud till Finance has no Bills due, and a deep link to '
      'it lands on Home', (tester) async {
    final (container, bar) = await _open(
      tester,
      pane: ManagementPane.financeBills,
    );
    expect(_showing(tester), {ManagementPane.home});
    // Not the platform pointer either: Finance is not a tab that points.
    expect(find.byKey(const Key('management-platform-pointer')), findsNothing);

    final finance = _barOf(container)
        .firstWhere((menu) => menu.tab == BackOfficeTab.finance);
    final lines = [for (final line in finance.lines) line.pane];
    expect(lines, isNot(contains(ManagementPane.financeBills)));
    expect(lines, contains(ManagementPane.financeExpenses));
    await bar.open(tester, ManagementPane.financeExpenses);
    expect(_showing(tester), {ManagementPane.financeExpenses});
  });

  testWidgets('Returns\' "Open the sale" lands on the sales list, open on that '
      'sale — a fresh list for each, and the plain one from the bar', (
    tester,
  ) async {
    // Today, so both are in Returns' first window.
    final now = DateTime.now();
    RefundRecord refund(int id, int orderId) => RefundRecord(
      id: id,
      orderId: orderId,
      invoiceNumber: 'INV-$orderId',
      occurredAt: now,
      total: const Money(2500),
      kind: RefundKind.partial,
      lineCount: 1,
      refundedByName: 'Sami Farid',
    );
    final (_, bar) = await _open(
      tester,
      pane: ManagementPane.sales,
      overrides: [
        orderHistoryRepositoryProvider.overrideWithValue(
          FakeOrderHistoryRepository(refunds: [refund(1, 11), refund(2, 12)]),
        ),
        refundsForOrderProvider.overrideWith(
          (ref, orderId) async => const <Refund>[],
        ),
      ],
    );

    OrderHistoryScreen orders() =>
        tester.widget<OrderHistoryScreen>(find.byType(OrderHistoryScreen));
    Future<void> openSaleOf(String row) async {
      // Returns is a view of the Sales page, behind its switch.
      await tester.tap(find.byKey(const Key('sales-view-returns')));
      await tester.pumpAndSettle();
      expect(find.byType(OrderHistoryScreen), findsNothing, reason: row);
      expect(_showing(tester), {ManagementPane.sales});
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RefundDetailPane.openSaleKey));
      await tester.pumpAndSettle();
      expect(_showing(tester), {ManagementPane.sales}, reason: row);
      expect(find.byType(OrderHistoryScreen), findsOneWidget, reason: row);
    }

    await openSaleOf('#1');
    const first = SaleToOpen(orderId: 11, invoiceNumber: 'INV-11');
    expect(orders().openSale, first);
    expect(orders().key, const ValueKey(first));

    // The history reads `openSale` once; only a new key makes a second
    // sale more than a new argument to a list already built for the first.
    await openSaleOf('#2');
    const second = SaleToOpen(orderId: 12, invoiceNumber: 'INV-12');
    expect(orders().openSale, second);
    expect(orders().key, const ValueKey(second));

    await bar.open(tester, ManagementPane.sales);
    expect(orders().openSale, isNull, reason: 'the list, not the last sale');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings › User\'s Exit leaves the back office, as Log out '
      'does', (tester) async {
    var closed = 0;
    final (container, _) = await _open(
      tester,
      pane: ManagementPane.user,
      onClose: () => closed++,
    );
    expect(_showing(tester), {ManagementPane.user});

    await tester.tap(find.byKey(const Key('user-exit')));
    await tester.pumpAndSettle();
    expect(container.read(adminSessionProvider), isNull);
    expect(closed, 1);
  });

  group('where the door lands: Home', () {
    for (final offline in [true, false]) {
      final where = offline ? 'offline' : 'cloud';
      testWidgets(where, (tester) async {
        await _open(tester, offline: offline);
        expect(_showing(tester), {ManagementPane.home});
        expect(find.byType(ManagementHomePane), findsOneWidget);
        // Not the pointer a cloud till's Inventory holds: greeting the owner
        // with "this is not here" on every entry would make it a welcome.
        expect(
          find.byKey(const Key('management-platform-pointer')),
          findsNothing,
        );
      });
    }

    testWidgets('and for somebody with no business figures, too', (
      tester,
    ) async {
      // The supervisor holds no `reports.view`: Home still greets them,
      // without the tiles.
      await _open(tester, username: 'nour', pin: '2468');
      expect(_showing(tester), {ManagementPane.home});
      expect(
        find.text(const EnStrings().homeWelcome(_supervisor.name)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-tiles')), findsNothing);
    });
  });

  // The owner, 15 Sep 2026: "there is duplication here, I don't need that".
  // Home's four cards said what the status bar says and its shortcuts what
  // the window's bar says; both went. The till's name was said only by its
  // card, so it moved to the status bar rather than being lost.
  group('Home says nothing the rest of the screen already does', () {
    for (final offline in [true, false]) {
      final where = offline ? 'offline' : 'cloud';
      testWidgets('$where: no cards, no shortcuts, Exit once, and no status '
          'bar of Management\'s own', (tester) async {
        final (container, _) = await _open(tester, offline: offline);
        container
            .read(terminalProfileProvider.notifier)
            .apply(
              const TerminalProfile(
                branchName: 'Maadi',
                terminalName: 'Counter 1',
              ),
            );
        await tester.pumpAndSettle();
        expect(_showing(tester), {ManagementPane.home});
        final home = find.byKey(const Key('home-pane'));

        for (final key in [
          'home-card-branch',
          'home-card-device',
          'home-card-connection',
          'home-card-last-backup',
          'home-card-last-sync',
          'home-action-salesReports',
          'home-action-products',
          'home-action-employees',
        ]) {
          expect(find.byKey(Key(key)), findsNothing, reason: key);
        }
        expect(
          find.descendant(of: home, matching: find.byType(GestureDetector)),
          findsNothing,
          reason: 'no way out of Home but the bar',
        );

        // No Exit on the page: the way out is Log out, in the window's bar.
        expect(find.text(const EnStrings().exitAdminMode), findsNothing);
        expect(find.byKey(const Key('admin-exit')), findsNothing);

        // Branch, till and connection are the status bar's, under every screen
        // (26 Oct 2026) — not on Home, and not drawn a second time by this
        // screen: the bar is mounted once, by the app, and `till_status_bar_test`
        // owns what it says.
        for (final said in [find.text('Counter 1'), find.text('Maadi')]) {
          expect(find.descendant(of: home, matching: said), findsNothing);
        }
        expect(find.byKey(const Key('till-status-bar')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('and no Reports menu for somebody without reports.view', (
      tester,
    ) async {
      final (container, _) = await _open(tester, username: 'nour', pin: '2468');
      expect([
        for (final menu in _barOf(container)) menu.tab,
      ], isNot(contains(BackOfficeTab.reports)));
    });
  });

  testWidgets('on a cloud till Menu is absent, and Inventory and Purchasing '
      'point at the platform', (tester) async {
    final (container, bar) = await _open(tester);
    final menus = _barOf(container);

    expect([
      for (final menu in menus) menu.tab,
    ], isNot(contains(BackOfficeTab.menu)));
    const s = EnStrings();
    for (final tab in [BackOfficeTab.inventory, BackOfficeTab.purchasing]) {
      final line = menus.firstWhere((menu) => menu.tab == tab).lines.single;
      expect(line.pane, isNull, reason: 'the pointer, not a pane');
      await bar.go(tester, line.open());
      expect(
        find.text(s.purchasingComesFromPlatform),
        findsOneWidget,
        reason: tab.name,
      );
      expect(_showing(tester), isEmpty, reason: 'a sentence, not a pane');
      // The tab's word in the header, since there is no page to name.
      expect(
        tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
        backOfficeTabName(s, tab),
      );
    }
  });

  // XORD-022 replaced the owner's map of 14 Sep 2026 (owner's decision,
  // 2026-10-25): Home is Dashboard, System is Management and took Dining areas
  // & tables from Menu, Finance's Payment methods went into Reports, and the
  // account menu is a tab of its own that the bar draws as the person's name.
  group('the back office map (XORD-022)', () {
    test('eleven tabs, in order, in their words', () {
      expect(BackOfficeTab.values, [
        BackOfficeTab.home,
        BackOfficeTab.sales,
        BackOfficeTab.reports,
        BackOfficeTab.menu,
        BackOfficeTab.inventory,
        BackOfficeTab.purchasing,
        BackOfficeTab.finance,
        BackOfficeTab.people,
        BackOfficeTab.system,
        BackOfficeTab.settings,
        BackOfficeTab.account,
      ]);
      expect(
        [
          for (final tab in BackOfficeTab.values)
            backOfficeTabName(const ArStrings(), tab),
        ],
        [
          'لوحة التحكم',
          'المبيعات',
          'التقارير',
          'قائمة الطعام',
          'المخزون',
          'المشتريات',
          'المالية',
          'المستخدمون والعملاء',
          'الإدارة',
          'الإعدادات',
          'الحساب',
        ],
      );
    });

    test('every pane has a label in both languages, never two of one label '
        'in one menu, and only the documented labels repeat across menus', () {
      // XORD-022-A: a repeated word is allowed only where the two pages do
      // different jobs and sit under different words — each says why.
      //  · Sales — the page of sales, and Reports' breakdown of them.
      //  · Payment methods — Reports' analysis, and Settings' management.
      //  · Employees — People's management, and Reports' breakdown.
      const allowed = {
        'en': {'Sales', 'Payment methods', 'Employees'},
        'ar': {'المبيعات', 'طرق الدفع', 'الموظفون'},
      };
      for (final (code, strings) in [
        ('en', const EnStrings() as AppStrings),
        ('ar', const ArStrings() as AppStrings),
      ]) {
        final byLabel = <String, List<ManagementPane>>{};
        for (final pane in ManagementPane.values) {
          final label = managementPaneLabel(strings, pane).$1;
          expect(label, isNotEmpty, reason: '${pane.name}, $code');
          byLabel.putIfAbsent(label, () => []).add(pane);
        }
        for (final MapEntry(key: label, value: panes) in byLabel.entries) {
          if (panes.length < 2) continue;
          expect(
            allowed[code],
            contains(label),
            reason: '"$label" ($code) names ${[for (final p in panes) p.name]}',
          );
          expect(
            {for (final pane in panes) tabOf(pane)},
            hasLength(panes.length),
            reason: '"$label" ($code) twice in one menu',
          );
        }
      }
    });

    test('every tab\'s items, for the owner offline — all of the map but '
        'Reports\' breakdowns, and no placeholder for those', () {
      // Read off the bar: each tab's items, with Purchasing's own tabs in
      // place of its one — the map's words, in the map's order.
      const ar = ArStrings();
      expect(
        {
          for (final menu in managementBarFor(
            ar,
            admin: _owner,
            authorsItsOwnCatalogue: true,
          ))
            menu.tab: [for (final line in menu.lines) line.label],
        },
        {
          BackOfficeTab.home: ['لوحة التحكم'],
          // One page, a button in the bar: the invoices and cancelled orders
          // are its filters, and the returns a switch inside it.
          BackOfficeTab.sales: ['المبيعات'],
          BackOfficeTab.reports: [
            'ملخص الأعمال',
            'المبيعات',
            'الأصناف',
            'طرق الدفع',
            'الفروع والأجهزة',
            'الموظفون',
          ],
          BackOfficeTab.menu: [
            'المنتجات',
            'الأقسام',
            'مكتبة الإضافات',
            'الكومبو',
          ],
          BackOfficeTab.inventory: [
            'أصناف المخزون',
            'المخزون المتاح',
            'الوحدات',
          ],
          BackOfficeTab.purchasing: [
            'أوامر الشراء',
            ar.purchaseOrderNew,
            'المورّدون',
            ar.supplierNew,
            'فواتير الشراء',
            ar.invoiceNew,
            'المدفوعات',
          ],
          // Overview and Revenue lead; Bills due and Transactions follow.
          BackOfficeTab.finance: [
            'نظرة عامة',
            'الإيرادات',
            'الخزينة',
            'المصروفات',
            'التسويات',
            'الضرائب',
            'الفواتير المستحقة',
            'الحركات',
            'الأرباح والخسائر',
            'الحسابات',
          ],
          BackOfficeTab.people: [
            'المستخدمون',
            'الأدوار والصلاحيات',
            'الورديات',
            'العملاء',
          ],
          // ETA only while filing is on.
          // Dining areas & tables first, as the epic lists them.
          BackOfficeTab.system: [
            'الصالات والطاولات',
            'الأجهزة',
            'المزامنة',
            'النسخ الاحتياطي',
            'السجل',
            if (etaFilingEnabled) ar.paneEta,
          ],
          BackOfficeTab.settings: [
            'إعدادات الطلبات والفواتير',
            'الطابعة ودرج النقدية',
            'اللغة',
            'المظهر',
          ],
          // The account menu's two pages; the till's own lines (Switch user,
          // Lock, Log out) are added by the bar, not by `managementBarFor`.
          BackOfficeTab.account: ['المستخدم', 'حول XOrder'],
        },
      );
    });

    test('every Settings pane sits under one of Settings\' items, and only '
        'those', () {
      for (final pane in ManagementPane.values) {
        expect(
          settingsSectionOf(pane) != null,
          tabOf(pane) == BackOfficeTab.settings,
          reason: pane.name,
        );
      }
      expect(
        {
          for (final pane in ManagementPane.values)
            if (settingsSectionOf(pane) == SettingsSection.ordersAndInvoices)
              pane,
        },
        {
          ManagementPane.receipt,
          ManagementPane.orderTypes,
          ManagementPane.taxes,
          ManagementPane.charges,
          ManagementPane.tenders,
        },
      );
    });

    test('People is a tab again, holding Staff and Roles; ETA is System', () {
      const s = EnStrings();
      for (final pane in [ManagementPane.staff, ManagementPane.roles]) {
        expect(tabOf(pane), BackOfficeTab.people, reason: pane.name);
        expect(settingsSectionOf(pane), isNull, reason: pane.name);
      }
      expect(managementPaneLabel(s, ManagementPane.staff).$1, s.paneStaff);
      expect(
        managementPaneLabel(s, ManagementPane.receipt).$1,
        s.settingsGeneral,
      );
      expect(tabOf(ManagementPane.eta), BackOfficeTab.system);
    });

    testWidgets('General opens with the business logo, above the company form '
        '(XORD-021): in view on arrival, not found by scrolling', (
      tester,
    ) async {
      await _open(tester, pane: ManagementPane.receipt);

      final card = find.byKey(const Key('business-logo'));
      expect(card, findsOneWidget);
      expect(
        tester.getRect(card).bottom,
        lessThan(900),
        reason: 'the whole card is on the first screen',
      );
      // This harness has no receipt-profile repository, so the pane shows its
      // "no database" line and General's other cards under it; the logo is
      // above all of them. Its place over the real form is pinned in
      // `receipt_profile_ui_test`.
      expect(
        tester.getTopLeft(card).dy,
        lessThan(
          tester
              .getTopLeft(find.text(const EnStrings().receiptProfileNoDatabase))
              .dy,
        ),
        reason: 'above the pane\'s own content, not under it',
      );
    });

    testWidgets('Orders & invoices settings has a side nav of its five — '
        'the page\'s own, since the bar has one line for them; the other '
        'five items have none', (tester) async {
      final (_, bar) = await _open(tester, pane: ManagementPane.receipt);

      final nav = find.byKey(const Key('back-office-settings-nav'));
      expect(tester.getSize(nav).width, PosSize.settingsNav);
      for (final text in [
        'General',
        'Order types',
        'Tax',
        'Service charges',
        'Payment methods',
      ]) {
        expect(
          find.descendant(of: nav, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      // The other five of Settings' items are a page each, so no side nav.
      // Their order is the bar's, asserted with the map's words above.
      for (final pane in [
        ManagementPane.printer,
        ManagementPane.user,
        ManagementPane.about,
      ]) {
        await bar.open(tester, pane);
        expect(_showing(tester), {pane});
        expect(nav, findsNothing, reason: pane.name);
      }
      await bar.open(tester, ManagementPane.receipt);

      await tester.tap(find.byKey(const Key('back-office-settings-charges')));
      await tester.pumpAndSettle();
      expect(_showing(tester), {ManagementPane.charges});

      await bar.open(tester, ManagementPane.language);
      expect(_showing(tester), {ManagementPane.language});
      expect(nav, findsNothing, reason: 'one page, so no side nav');
    });
  });

  // The owner, 15 Sep 2026: "no need for this, use same design only on the
  // top menu". Replaces the test that measured the strip at 1100 px; the bar
  // is measured there instead, in `settings_bar_test.dart`.
  testWidgets('no tab strip and no sub-nav: the page under its name, and the '
      'bar is the way round', (tester) async {
    final (_, bar) = await _open(tester, offline: true);
    const s = EnStrings();

    List<String> strayKeys() => [
      for (final element
          in find
              .byWidgetPredicate((w) => w.key is ValueKey<String>)
              .evaluate())
        if ((element.widget.key! as ValueKey<String>).value case final key
            when key == 'back-office-tabs' ||
                key == 'back-office-subnav' ||
                key.startsWith('back-office-tab-') ||
                key.startsWith('back-office-subnav-'))
          key,
    ];

    // One page of every tab with more than one — where the sub-nav was drawn
    // — and Home, where the strip began, and General, which keeps its side
    // nav.
    for (final pane in [
      ManagementPane.home,
      ManagementPane.sales,
      ManagementPane.reportsItems,
      ManagementPane.categories,
      ManagementPane.stock,
      ManagementPane.purchasing,
      ManagementPane.financeDrawers,
      ManagementPane.roles,
      ManagementPane.backup,
      ManagementPane.receipt,
      ManagementPane.language,
    ]) {
      await bar.open(tester, pane);
      expect(_showing(tester), {pane});
      expect(strayKeys(), isEmpty, reason: pane.name);
      // The header and the page, and nothing between. (The status bar is the
      // app's, under every screen.)
      expect(
        tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
        managementPaneLabel(s, pane).$1,
        reason: pane.name,
      );
      expect(find.byKey(const Key('admin-exit')), findsNothing);
      expect(find.byKey(const Key('till-status-bar')), findsNothing);
      expect(
        find.byKey(const Key('back-office-settings-nav')),
        pane == ManagementPane.receipt ? findsOneWidget : findsNothing,
        reason: pane.name,
      );
    }
    expect(tester.takeException(), isNull);
  });

  group('at 1100 px', () {
    for (final language in ['en', 'ar']) {
      testWidgets('every page the bar reaches lays out, in $language, and '
          'the side nav is on the start side', (tester) async {
        final (container, bar) = await _open(
          tester,
          offline: true,
          language: language,
          width: PosSize.wideShellMin,
        );
        expect(tester.takeException(), isNull);

        // Every line, as an offline owner has them — the most pages anybody
        // gets — with no header, notice or page overflowing. Lines that start
        // something new are the list beside them with a form on top.
        for (final menu in _barOf(container)) {
          for (final line in menu.lines) {
            final to = line.open();
            if (to.create) continue;
            await bar.go(tester, to);
            expect(_showing(tester), {line.pane}, reason: line.label);
            expect(tester.takeException(), isNull, reason: line.label);
          }
        }

        await bar.open(tester, ManagementPane.receipt);
        expect(tester.takeException(), isNull);

        // The side nav on the start side — the right, in Arabic.
        final nav = tester.getRect(
          find.byKey(const Key('back-office-settings-nav')),
        );
        expect(nav.width, PosSize.settingsNav);
        if (language == 'ar') {
          expect(nav.right, PosSize.wideShellMin);
        } else {
          expect(nav.left, 0);
        }
      });
    }
  });

  test('every tab is named in both languages, never the same word twice', () {
    for (final s in const <AppStrings>[EnStrings(), ArStrings()]) {
      final names = [
        for (final tab in BackOfficeTab.values) backOfficeTabName(s, tab),
      ];
      expect(names.toSet(), hasLength(BackOfficeTab.values.length));
    }
    for (final tab in BackOfficeTab.values) {
      expect(
        backOfficeTabName(const ArStrings(), tab),
        isNot(backOfficeTabName(const EnStrings(), tab)),
        reason: tab.name,
      );
    }
    expect(const ArStrings().backOffice, isNot(const EnStrings().backOffice));
  });
}
