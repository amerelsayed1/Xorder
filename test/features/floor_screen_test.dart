import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import '../support/fakes.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/features/floor/floor_screen.dart';

const _desktop = Size(1440, 900);

final _seven = DateTime(2026, 11, 8, 19, 0);

/// Two sections and a main room, with one table in every attention state.
List<DiningTable> _floor() => [
  const DiningTable(id: 1, label: 'T1', seats: 4, sortOrder: 1),
  const DiningTable(id: 2, label: 'T12', seats: 2, sortOrder: 2),
  const DiningTable(
    id: 3,
    label: 'P5',
    seats: 6,
    areaName: 'Terrace',
    sortOrder: 3,
  ),
  const DiningTable(
    id: 4,
    label: 'B7',
    seats: 2,
    areaName: 'Bar',
    sortOrder: 4,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<DiningTable> tables,
  required DateTime now,
  void Function(DiningTable)? onPicked,
}) async {
  tester.view
    ..physicalSize = _desktop
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeRepositoryOverrides(),
        // The floor provider overlays this till's parked tickets; feeding the
        // already-overlaid tables straight in keeps the test about the screen.
        floorTablesProvider.overrideWith((ref) async => tables),
      ],
      child: MaterialApp(
        theme: buildPosTheme(),
        home: FloorScreen(
          now: now,
          onTablePicked: onPicked ?? (_) {},
          onSellWithoutTable: () {},
          onClose: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sections become tabs, main room last, All first', (tester) async {
    await _pump(tester, tables: _floor(), now: _seven);

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Terrace'), findsOneWidget);
    expect(find.text('Bar'), findsOneWidget);
    expect(find.text('Main room'), findsOneWidget);
    // Every tile is on the All tab.
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('P5'), findsOneWidget);

    await tester.tap(find.text('Terrace'));
    await tester.pumpAndSettle();
    expect(find.text('P5'), findsOneWidget);
    expect(find.text('T1'), findsNothing);
    expect(find.text('B7'), findsNothing);
  });

  testWidgets('a single-section floor shows no tabs', (tester) async {
    await _pump(
      tester,
      tables: const [DiningTable(id: 1, label: 'T1', seats: 2)],
      now: _seven,
    );
    expect(find.text('All'), findsNothing);
    expect(find.text('Main room'), findsNothing);
  });

  testWidgets('tiles carry the seating timer and the attention line', (
    tester,
  ) async {
    final tables = [
      // Seated 42 minutes, last round 30 minutes ago: quiet.
      DiningTable(
        id: 1,
        label: 'T1',
        seats: 4,
        state: TableState.open,
        seatedAt: _seven.subtract(const Duration(minutes: 42)),
        lastSentAt: _seven.subtract(const Duration(minutes: 30)),
        guestCount: 3,
      ),
      // Rung up 5 minutes ago, nothing fired: not sent.
      DiningTable(
        id: 2,
        label: 'T2',
        seats: 2,
        state: TableState.open,
        seatedAt: _seven.subtract(const Duration(minutes: 5)),
        hasUnsentDraft: true,
      ),
      // Bill asked, kitchen quiet for 10: waiting.
      DiningTable(
        id: 3,
        label: 'T3',
        seats: 2,
        state: TableState.billAsked,
        seatedAt: _seven.subtract(const Duration(hours: 1, minutes: 12)),
        lastSentAt: _seven.subtract(const Duration(minutes: 10)),
      ),
      const DiningTable(id: 4, label: 'T4', seats: 2),
    ];
    await _pump(tester, tables: tables, now: _seven);

    expect(find.text('42m'), findsOneWidget);
    expect(find.text('3 guests'), findsOneWidget);
    expect(find.text('QUIET 30m'), findsOneWidget);
    expect(find.text('NOT SENT TO KITCHEN'), findsOneWidget);
    expect(find.text('1h 12m'), findsOneWidget);
    expect(find.text('BILL WAITING 10m'), findsOneWidget);
    expect(find.text('ATTENTION 3'), findsOneWidget);
    // A free table has no timer at all.
    expect(find.text('FREE'), findsOneWidget);
  });

  testWidgets('typing a number and Enter opens that table', (tester) async {
    DiningTable? picked;
    await _pump(
      tester,
      tables: _floor(),
      now: _seven,
      onPicked: (t) => picked = t,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    // Both T1 and T12 match "1"; the chip shows the search, the grid narrows.
    expect(find.textContaining('Jump to'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T12'), findsOneWidget);
    expect(find.text('P5'), findsNothing);

    // Enter on an ambiguous prefix opens the EXACT match, not the first tile.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked?.label, 'T1');
    expect(find.textContaining('Jump to'), findsNothing);
  });

  testWidgets('Escape clears what was typed', (tester) async {
    await _pump(tester, tables: _floor(), now: _seven);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsNothing);
    expect(find.text('T12'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('P5'), findsOneWidget);
  });
}
