import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/app/waiter_shift_providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/mono_amount.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/waiter_shift.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_waiter_shifts_pane.dart';

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

/// What the open shift's length is counted to.
final _readAt = DateTime(2026, 9, 14, 15, 30);

/// Newest first by start, the open one among them — the order the real reader
/// answers in, which is not the order the pane draws.
///
/// 6 — Karim, 14 Sep 11:00–14:00: 3:00.
/// 7 — Mona, open since 13 Sep 20:00 (she never clocked out): 19:30 at 15:30.
/// 5 — Karim, 13 Sep 18:00 – 14 Sep 01:45, finished on another handheld: 7:45.
/// 4 — Mona, 13 Sep 10:00–16:20:30: 6:20, the half minute cut, not rounded.
/// 3 — Karim, 13 Sep 08:00–08:59:59, no handheld on record: 0:59.
///
/// Mona 19:30 + 6:20 = 25:50 over two; Karim 3:00 + 7:45 + 0:59 = 11:44 over
/// three.
final _shifts = [
  WaiterShiftRecord(
    id: 6,
    staffId: 12,
    staffName: 'Karim S.',
    startedAt: DateTime(2026, 9, 14, 11),
    endedAt: DateTime(2026, 9, 14, 14),
    startedDevice: 'Handheld 1',
    endedDevice: 'Handheld 1',
  ),
  WaiterShiftRecord(
    id: 7,
    staffId: 11,
    staffName: 'Mona H.',
    startedAt: DateTime(2026, 9, 13, 20),
    startedDevice: 'Handheld 2',
  ),
  WaiterShiftRecord(
    id: 5,
    staffId: 12,
    staffName: 'Karim S.',
    startedAt: DateTime(2026, 9, 13, 18),
    endedAt: DateTime(2026, 9, 14, 1, 45),
    startedDevice: 'Handheld 1',
    endedDevice: 'Handheld 2',
  ),
  WaiterShiftRecord(
    id: 4,
    staffId: 11,
    staffName: 'Mona H.',
    startedAt: DateTime(2026, 9, 13, 10),
    endedAt: DateTime(2026, 9, 13, 16, 20, 30),
    startedDevice: 'Handheld 2',
    endedDevice: 'Handheld 2',
  ),
  WaiterShiftRecord(
    id: 3,
    staffId: 12,
    staffName: 'Karim S.',
    startedAt: DateTime(2026, 9, 13, 8),
    endedAt: DateTime(2026, 9, 13, 8, 59, 59),
  ),
];

// ── Test doubles. Never a default binding. ──────────────────────────────────

/// Keeps what it was asked; answers [shifts] whatever the dates.
class _Clock implements WaiterShiftReader {
  _Clock(this.shifts);

  final List<WaiterShiftRecord> shifts;
  final asked = <(DateTime, DateTime)>[];

  @override
  Future<List<WaiterShiftRecord>> between(DateTime from, DateTime to) async {
    asked.add((from, to));
    return shifts;
  }
}

class _Viewer extends SignedInStaffController {
  _Viewer(this.staff);

  final PosStaff? staff;

  @override
  PosStaff? build() => staff;
}

Future<_Clock> _pump(
  WidgetTester tester, {
  PosStaff viewer = _owner,
  String language = 'en',
  double width = 1400,
  List<WaiterShiftRecord>? shifts,
  bool configured = true,
}) async {
  // Tall, so every row is laid out: a ListView builds only what it shows.
  tester.view
    ..physicalSize = Size(width, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final clock = _Clock(shifts ?? _shifts);
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      // Unconfigured is the provider's own binding: the harness has no
      // database, so leaving it alone is the till before setup.
      if (configured) waiterShiftReaderProvider.overrideWithValue(clock),
      waiterShiftClockProvider.overrideWithValue(() => _readAt),
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
        theme: buildPosTheme(PosPalette.light),
        home: Scaffold(body: ManagementWaiterShiftsPane(admin: viewer)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return clock;
}

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

/// [text] inside the row keyed [key].
Finder _in(String key, String text) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.text(text),
);

Color? _colour(WidgetTester tester, String key, String text) =>
    tester.widget<Text>(_in(key, text)).style?.color;

void main() {
  const s = EnStrings();

  setUpAll(loadPosFonts);

  group('People › Waiter shifts', () {
    testWidgets('the open shift on top in the accent, then newest first, each '
        'length in hours and minutes', (tester) async {
      await _pump(tester);

      expect(_keys('waiter-shifts-row-'), [
        'waiter-shifts-row-7',
        'waiter-shifts-row-6',
        'waiter-shifts-row-5',
        'waiter-shifts-row-4',
        'waiter-shifts-row-3',
      ]);

      // Open: "on shift" where the finish would be, counted to the read.
      const accent = PosPalette.light;
      expect(_in('waiter-shifts-row-7', s.waiterShiftsOnShift), findsOneWidget);
      expect(
        _colour(tester, 'waiter-shifts-row-7', s.waiterShiftsOnShift),
        accent.accent,
      );
      expect(_in('waiter-shifts-row-7', '19:30'), findsOneWidget);
      expect(_colour(tester, 'waiter-shifts-row-7', '19:30'), accent.accent);
      expect(_in('waiter-shifts-row-7', '2026-09-13 20:00'), findsOneWidget);

      // Finished: both times, and nobody said "on shift".
      expect(_in('waiter-shifts-row-5', '2026-09-13 18:00'), findsOneWidget);
      expect(_in('waiter-shifts-row-5', '2026-09-14 01:45'), findsOneWidget);
      expect(_in('waiter-shifts-row-5', s.waiterShiftsOnShift), findsNothing);
      expect(_in('waiter-shifts-row-5', '7:45'), findsOneWidget);
      expect(_colour(tester, 'waiter-shifts-row-5', '7:45'), isNot(accent.accent));

      // Truncated, not rounded: 6 h 20 min 30 s is 6:20; 59 min 59 s is 0:59.
      expect(_in('waiter-shifts-row-4', '6:20'), findsOneWidget);
      expect(_in('waiter-shifts-row-3', '0:59'), findsOneWidget);
    });

    testWidgets('the handheld it started on, and the one it finished on when '
        'that was another', (tester) async {
      await _pump(tester);
      expect(_in('waiter-shifts-row-5', 'Handheld 1 / Handheld 2'), findsOneWidget);
      // The same handheld twice is one handheld.
      expect(_in('waiter-shifts-row-4', 'Handheld 2'), findsOneWidget);
      expect(_in('waiter-shifts-row-7', 'Handheld 2'), findsOneWidget);
      // None on record is a dash, not a blank.
      expect(_in('waiter-shifts-row-3', '—'), findsOneWidget);
    });

    testWidgets("each waiter's hours are the sum of their rows, most first", (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byKey(const Key('waiter-shifts-totals')), findsOneWidget);
      expect(_keys('waiter-shifts-total-'), [
        'waiter-shifts-total-11',
        'waiter-shifts-total-12',
      ]);
      // Mona: 19:30 + 6:20, still on shift so in the accent.
      expect(_in('waiter-shifts-total-11', 'Mona H.'), findsOneWidget);
      expect(_in('waiter-shifts-total-11', '2'), findsOneWidget);
      expect(_in('waiter-shifts-total-11', '25:50'), findsOneWidget);
      expect(
        _colour(tester, 'waiter-shifts-total-11', '25:50'),
        PosPalette.light.accent,
      );
      // Karim: 3:00 + 7:45 + 0:59 — the rows' own minutes, so a pencil down
      // the column agrees.
      expect(_in('waiter-shifts-total-12', '3'), findsOneWidget);
      expect(_in('waiter-shifts-total-12', '11:44'), findsOneWidget);
    });

    testWidgets('the dates are asked of the reader, and a chip asks again', (
      tester,
    ) async {
      final clock = await _pump(tester);
      // This week by default: from the week's first day to the end of the
      // open business day, as Finance counts it.
      final (from, to) = clock.asked.single;
      final today = DateTime(2026, 9, 14);
      expect(from.isAfter(today), isFalse);
      expect(today.difference(from).inDays, lessThan(7));
      expect(to, DateTime(2026, 9, 15));

      await tester.tap(find.byKey(const Key('waiter-shifts-period-today')));
      await tester.pumpAndSettle();
      expect(clock.asked.last, (today, DateTime(2026, 9, 15)));
    });

    testWidgets('no shifts in the dates says so', (tester) async {
      await _pump(tester, shifts: const []);
      expect(find.text(s.waiterShiftsNone), findsOneWidget);
      expect(_keys('waiter-shifts-row-'), isEmpty);
      expect(find.byKey(const Key('waiter-shifts-totals')), findsNothing);
    });

    testWidgets('a till with no database shows nothing, never invented rows', (
      tester,
    ) async {
      await _pump(tester, configured: false);
      expect(find.text(s.waiterShiftsNone), findsOneWidget);
      expect(_keys('waiter-shifts-row-'), isEmpty);
    });

    testWidgets('reports.view through a role is enough', (tester) async {
      final clock = await _pump(tester, viewer: _accountant);
      expect(clock.asked, hasLength(1));
      expect(_keys('waiter-shifts-row-'), hasLength(5));
    });

    testWidgets('without reports.view nothing is read and the pane says why', (
      tester,
    ) async {
      final clock = await _pump(tester, viewer: _cashier);
      expect(clock.asked, isEmpty);
      expect(find.text(s.waiterShiftsNeedReports), findsOneWidget);
      expect(_keys('waiter-shifts-row-'), isEmpty);
    });
  });

  testWidgets('in Arabic at 1100 px it lays out, with times left to right', (
    tester,
  ) async {
    await _pump(tester, language: 'ar', width: PosSize.wideShellMin);
    const ar = ArStrings();
    expect(tester.takeException(), isNull);
    expect(find.text(ar.waiterShiftsTotals), findsOneWidget);
    expect(find.text(ar.waiterShiftsOnShift), findsOneWidget);
    expect(find.text(s.waiterShiftsOnShift), findsNothing);
    // Latin digits, mono, left to right.
    expect(_in('waiter-shifts-row-7', '19:30'), findsOneWidget);
    final length = tester.widget<Directionality>(
      find
          .descendant(
            of: find.ancestor(
              of: _in('waiter-shifts-row-7', '19:30'),
              matching: find.byType(MonoCode),
            ),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(length.textDirection, TextDirection.ltr);
  });
}
