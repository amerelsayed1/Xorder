import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/mono_amount.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_settlements_pane.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_shifts_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

// Who reads them, each holding what they hold through a ROLE —
// `PosStaff.capabilities` is direct grants only.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
// The figures, and not the drawers' differences.
const _accountant = PosStaff(
  id: 6,
  name: 'Samir B.',
  role: PosRole(
    id: 6,
    code: 'accountant',
    nameEn: 'Accountant',
    capabilities: {PosCapability.reportsView},
  ),
);
const _cashier = PosStaff(
  id: 4,
  name: 'Rana A.',
  role: PosRole(
    id: 2,
    code: 'cashier',
    nameEn: 'Cashier',
    capabilities: {PosCapability.operate},
  ),
);

ShiftRecord _record(
  int id, {
  required String till,
  required int openedBy,
  required String opener,
  required int float,
  int cash = 0,
  int paidIn = 0,
  int paidOut = 0,
  int? closedBy,
  String? closer,
  int? variance,
  String? approvedBy,
  String? note,
}) {
  final summary = ShiftSummary(
    shift: PosShift(
      id: id,
      openedAt: DateTime(2026, 9, 14, 8 + id),
      openingFloat: Money(float),
      openedByName: opener,
      openedById: openedBy,
      closedAt: closedBy == null ? null : DateTime(2026, 9, 14, 16 + id),
    ),
    saleCount: 1,
    gross: Money(cash),
    tenders: [
      ShiftTenderTotal(
        label: 'Cash',
        count: 1,
        amount: Money(cash),
        countsAsCash: true,
      ),
    ],
    movements: CashMovementTotals(
      paidIn: Money(paidIn),
      paidOut: Money(paidOut),
      drawerOpens: 0,
      movements: const [],
    ),
  );
  final expected = summary.expectedCash;
  return ShiftRecord(
    summary: summary,
    terminalId: till == 'POS-01' ? 't1' : 't2',
    terminalName: till,
    closedById: closedBy,
    closedByName: closer,
    countedCash: variance == null ? null : expected + Money(variance),
    recordedExpected: variance == null ? null : expected,
    recordedVariance: variance == null ? null : Money(variance),
    approvedByName: approvedBy,
    note: note,
  );
}

/// Open first, then newest: the order the repository answers in.
///
/// 1 — open: 20,000 + 11,400 + 5,000 − 7,800 = 28,600 expected.
/// 4 — Omar's, 2.50 over. 3 — Sara's, counted by Omar on Hana's approval,
/// 5.00 short. 2 — Sara's, balanced.
final _records = [
  _record(
    1,
    till: 'POS-01',
    openedBy: 9,
    opener: 'Hoda K.',
    float: 20000,
    cash: 11400,
    paidIn: 5000,
    paidOut: 7800,
  ),
  _record(
    4,
    till: 'POS-02',
    openedBy: 4,
    opener: 'Omar T.',
    float: 5000,
    cash: 3000,
    closedBy: 4,
    closer: 'Omar T.',
    variance: 250,
  ),
  _record(
    3,
    till: 'POS-01',
    openedBy: 3,
    opener: 'Sara M.',
    float: 2000,
    cash: 3000,
    closedBy: 4,
    closer: 'Omar T.',
    variance: -500,
    approvedBy: 'Hana M.',
    note: 'Two notes torn',
  ),
  _record(
    2,
    till: 'POS-02',
    openedBy: 3,
    opener: 'Sara M.',
    float: 10000,
    cash: 3500,
    paidIn: 1200,
    paidOut: 1900,
    closedBy: 3,
    closer: 'Sara M.',
    variance: 0,
  ),
];

// ── Test doubles. Never a default binding. ──────────────────────────────────

/// Answers as the real repository filters, and keeps what it was asked.
class _Tills extends Fake implements ShiftRepository {
  final asked = <ShiftHistoryQuery>[];

  @override
  Future<ShiftHistory> history(ShiftHistoryQuery query) async {
    asked.add(query);
    return ShiftHistory(
      shifts: [
        for (final r in _records)
          if ((query.terminalId == null || query.terminalId == r.terminalId) &&
              (query.staffId == null || query.staffId == r.shift.openedById) &&
              (query.statuses.isEmpty || query.statuses.contains(r.status)))
            r,
      ],
      tills: const [('t1', 'POS-01'), ('t2', 'POS-02')],
      staff: const [(9, 'Hoda K.'), (4, 'Omar T.'), (3, 'Sara M.')],
    );
  }

  @override
  Future<PosShift?> current() async => null;

  @override
  Future<ShiftActivity> activity() async => ShiftActivity.empty;
}

class _Viewer extends SignedInStaffController {
  _Viewer(this.staff);

  final PosStaff? staff;

  @override
  PosStaff? build() => staff;
}

Future<_Tills> _pump(
  WidgetTester tester,
  Widget Function(PosStaff viewer) pane, {
  PosStaff viewer = _owner,
  String language = 'en',
  double width = 1400,
}) async {
  // Tall, so every row is laid out: a ListView builds only what it shows,
  // and a sum over rows that were never built is no sum.
  tester.view
    ..physicalSize = Size(width, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final tills = _Tills();
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      // Replaces the harness's `FakeShiftRepository`: the later override wins.
      shiftRepositoryProvider.overrideWithValue(tills),
      businessDayProvider.overrideWith(
        (ref) async => BusinessDay(
          id: 1,
          date: DateTime.utc(2026, 9, 14),
          openedAt: DateTime(2026, 9, 14, 8),
        ),
      ),
      signedInStaffProvider.overrideWith(() => _Viewer(viewer)),
    ],
  );
  addTearDown(container.dispose);

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
        home: Scaffold(body: pane(viewer)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tills;
}

Widget _shifts(PosStaff admin) => ManagementShiftsPane(admin: admin);
Widget _settlements(PosStaff admin) => ManagementSettlementsPane(admin: admin);

/// The amounts drawn under [finder], in order.
List<MonoAmount> _monos(WidgetTester tester, Finder finder) => [
  ...tester.widgetList<MonoAmount>(
    find.descendant(of: finder, matching: find.byType(MonoAmount)),
  ),
];

List<Money> _amounts(WidgetTester tester, String key) => [
  for (final w in _monos(tester, find.byKey(Key(key)))) w.value,
];

/// Keys starting with [prefix], in the order they are drawn.
List<String> _keys(String prefix) => [
  for (final e in find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      )
      .evaluate())
    (e.widget.key! as ValueKey<String>).value,
];

Future<void> _choose(WidgetTester tester, String dropKey, String label) async {
  await tester.tap(find.byKey(Key(dropKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  const s = EnStrings();

  // The bundled faces, not the test font, for the 1100 px claims below — as
  // `back_office_shell_test.dart` loads them.
  setUpAll(loadPosFonts);

  group('People › Shifts', () {
    testWidgets('every shift, open first, each row its own Z report figures', (
      tester,
    ) async {
      await _pump(tester, _shifts);

      expect(_keys('shifts-row-'), [
        'shifts-row-1',
        'shifts-row-4',
        'shifts-row-3',
        'shifts-row-2',
      ]);

      // Open: float, cash taken, paid in, paid out, expected — and no count
      // or difference, which are dashes rather than zeros.
      expect(_amounts(tester, 'shifts-row-1'), [
        Money(20000),
        Money(11400),
        Money(5000),
        Money(7800),
        Money(28600),
      ]);
      expect(
        find.descendant(
          of: find.byKey(const Key('shifts-row-1')),
          matching: find.text(s.shiftStatusOpen),
        ),
        findsOneWidget,
      );

      // Sara's drawer, counted by Omar: 5,000 expected, 4,500 counted, and
      // the difference is the count less the expected.
      final three = _amounts(tester, 'shifts-row-3');
      expect(three.sublist(4), [Money(5000), Money(4500), Money(-500)]);
      expect(three[6], three[5] - three[4]);
      expect(
        find.descendant(
          of: find.byKey(const Key('shifts-row-3')),
          matching: find.text(s.shiftStatusForceClosed),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('each filter is asked of the repository, not of the rows on '
        'screen', (tester) async {
      final tills = await _pump(tester, _shifts);
      expect(tills.asked.last.statuses, isEmpty);

      await _choose(tester, 'shifts-status', s.shiftStatusForceClosed);
      expect(tills.asked.last.statuses, {ShiftStatus.forceClosed});
      expect(_keys('shifts-row-'), ['shifts-row-3']);

      await _choose(tester, 'shifts-till', 'POS-02');
      expect(tills.asked.last.terminalId, 't2');
      expect(_keys('shifts-row-'), isEmpty);
      expect(find.text(s.shiftsNone), findsOneWidget);

      await _choose(tester, 'shifts-status', s.shiftsAllStatuses);
      await _choose(tester, 'shifts-cashier', 'Omar T.');
      expect(tills.asked.last.staffId, 4);
      expect(tills.asked.last.terminalId, 't2');
      expect(_keys('shifts-row-'), ['shifts-row-4']);

      // New dates are new tills and people: the two choices go.
      await tester.tap(find.byKey(const Key('shifts-period-thisMonth')));
      await tester.pumpAndSettle();
      expect(tills.asked.last.terminalId, isNull);
      expect(tills.asked.last.staffId, isNull);
      expect(tills.asked.last.from, DateTime(2026, 9));
    });

    testWidgets('a row opens its Z report, judged against the stored figure', (
      tester,
    ) async {
      await _pump(tester, _shifts);
      await tester.tap(find.byKey(const Key('shifts-row-3')));
      await tester.pumpAndSettle();

      final report = find.byKey(const Key('shift-report'));
      expect(report, findsOneWidget);
      expect(
        find.descendant(of: report, matching: find.text(s.zExpectedInDrawer)),
        findsOneWidget,
      );
      final amounts = [for (final w in _monos(tester, report)) w.value];
      expect(amounts, containsAllInOrder([Money(5000), Money(4500), Money(-500)]));
      expect(
        find.descendant(
          of: report,
          matching: find.text(s.settlementsApprovedBy('Hana M.')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: report,
          matching: find.text(s.shiftReportNote('Two notes torn')),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(s.close));
      await tester.pumpAndSettle();
      expect(report, findsNothing);
    });

    testWidgets('without reports.view nothing is read and the pane says why', (
      tester,
    ) async {
      final tills = await _pump(tester, _shifts, viewer: _cashier);
      expect(tills.asked, isEmpty);
      expect(find.text(s.shiftsNeedReports), findsOneWidget);
      expect(_keys('shifts-row-'), isEmpty);
    });
  });

  group('Finance › Settlements', () {
    testWidgets('only counted drawers, and the strip is the rows summed', (
      tester,
    ) async {
      final tills = await _pump(tester, _settlements);
      expect(tills.asked.last.statuses, {
        ShiftStatus.closed,
        ShiftStatus.forceClosed,
      });

      final rows = _keys('settlements-row-');
      expect(rows, [
        'settlements-row-4',
        'settlements-row-3',
        'settlements-row-2',
      ]);

      // The last figure of each row is its over/short.
      final differences = [for (final key in rows) _amounts(tester, key).last];
      expect(differences, [Money(250), Money(-500), Money(0)]);
      var over = Money.zero;
      var short = Money.zero;
      for (final d in differences) {
        if (d.isNegative) {
          short += d;
        } else {
          over += d;
        }
      }
      expect(_amounts(tester, 'settlements-tile-over'), [over]);
      expect(_amounts(tester, 'settlements-tile-short'), [short]);
      expect(_amounts(tester, 'settlements-tile-net'), [over + short]);
      expect(
        find.descendant(
          of: find.byKey(const Key('settlements-tile-count')),
          matching: find.text('${rows.length}'),
        ),
        findsOneWidget,
      );
      // Who counted, and on whose approval.
      expect(
        find.descendant(
          of: find.byKey(const Key('settlements-row-3')),
          matching: find.text(s.settlementsApprovedBy('Hana M.')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the status filter offers the two counted states and asks for '
        'the one chosen', (tester) async {
      final tills = await _pump(tester, _settlements);
      await tester.tap(find.byKey(const Key('settlements-status')));
      await tester.pumpAndSettle();
      expect(find.text(s.shiftStatusOpen), findsNothing);
      await tester.tap(find.text(s.shiftStatusForceClosed).last);
      await tester.pumpAndSettle();

      expect(tills.asked.last.statuses, {ShiftStatus.forceClosed});
      expect(_keys('settlements-row-'), ['settlements-row-3']);
      expect(_amounts(tester, 'settlements-tile-net'), [Money(-500)]);
    });

    testWidgets('without cash.variance.view the differences are masked, and '
        'the pane says so', (tester) async {
      await _pump(tester, _settlements, viewer: _accountant);

      for (final tile in ['over', 'short', 'net']) {
        expect(
          _monos(
            tester,
            find.byKey(Key('settlements-tile-$tile')),
          ).single.masked,
          isTrue,
          reason: tile,
        );
      }
      expect(
        _monos(tester, find.byKey(const Key('settlements-row-3'))).last.masked,
        isTrue,
      );
      // Expected and counted are not the difference, and stay.
      expect(
        _monos(tester, find.byKey(const Key('settlements-row-3'))).first.masked,
        isFalse,
      );
      expect(find.text(s.shiftsVarianceHidden), findsOneWidget);
    });
  });

  group('in Arabic at 1100 px', () {
    for (final (name, pane) in [
      ('Shifts', _shifts),
      ('Settlements', _settlements),
    ]) {
      testWidgets('$name lays out, in Arabic, with figures left to right', (
        tester,
      ) async {
        await _pump(tester, pane, language: 'ar', width: PosSize.wideShellMin);
        const ar = ArStrings();
        expect(tester.takeException(), isNull);
        // The note both panes close on, and the filter both offer.
        expect(find.text(ar.shiftsExpectedNote), findsOneWidget);
        expect(find.text(s.shiftsExpectedNote), findsNothing);
        expect(find.text(ar.shiftsAllTills), findsOneWidget);

        final amount = tester.widget<Directionality>(
          find
              .descendant(
                of: find.byType(MonoAmount).first,
                matching: find.byType(Directionality),
              )
              .first,
        );
        expect(amount.textDirection, TextDirection.ltr);
      });
    }
  });
}
