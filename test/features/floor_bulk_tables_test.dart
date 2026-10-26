import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_floor_pane.dart';

import '../support/staff.dart';

/// XORD-006 — Settings › Floor › Add several.
void main() {
  final strings = const EnStrings();

  Future<_Floor> pump(
    WidgetTester tester, {
    List<DiningTable> existing = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = _Floor();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(repository),
          tablesProvider.overrideWith((ref) async => existing),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          home: Scaffold(
            body: ManagementFloorPane(
              admin: staffWith({PosCapability.settingsManage}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('add-several-tables')));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pump();
  }

  String preview(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('bulk-preview'))).data!;

  testWidgets('the form opens on Table, 1, 10 and shows the run before saving', (tester) async {
    final repo = await pump(tester);
    await open(tester);

    expect(preview(tester), strings.bulkTablePreview('Table 1', 'Table 10', 10));
    expect(find.text(strings.bulkTablesCreate(10)), findsOneWidget);
    expect(repo.created, isEmpty, reason: 'looking is not saving');
  });

  testWidgets('creating sends ten uniquely named tables with the shared seats and area', (tester) async {
    final repo = await pump(tester);
    await open(tester);

    await type(tester, 'bulk-seats', '4');
    await type(tester, 'bulk-area', 'Terrace');
    await tester.tap(find.byKey(const Key('bulk-create')));
    await tester.pumpAndSettle();

    final sent = repo.created.single;
    expect(sent.map((t) => t.label), [for (var n = 1; n <= 10; n++) 'Table $n']);
    expect(sent.every((t) => t.seats == 4 && t.areaName == 'Terrace'), isTrue);
    expect(sent.every((t) => t.id == 0), isTrue);
    expect(find.text(strings.bulkTablesCreated(10)), findsOneWidget, reason: 'and says so');
    expect(find.byKey(const Key('bulk-create')), findsNothing, reason: 'the dialog closed');
  });

  testWidgets('a first number and a prefix of your own', (tester) async {
    final repo = await pump(tester);
    await open(tester);

    await type(tester, 'bulk-prefix', 'T');
    await type(tester, 'bulk-start', '21');
    await type(tester, 'bulk-quantity', '3');
    expect(preview(tester), strings.bulkTablePreview('T 21', 'T 23', 3));

    await tester.tap(find.byKey(const Key('bulk-create')));
    await tester.pumpAndSettle();
    expect(repo.created.single.map((t) => t.label), ['T 21', 'T 22', 'T 23']);
  });

  testWidgets('names the branch already has are named, and Add is off', (tester) async {
    final repo = await pump(
      tester,
      existing: const [
        DiningTable(id: 1, label: 'Table 3', seats: 2),
        DiningTable(id: 2, label: 'Table 4', seats: 2),
      ],
    );
    await open(tester);

    expect(
      find.text(strings.bulkTableClashes('"Table 3", "Table 4"')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('bulk-create')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.created, isEmpty);

    // Moving the run clear of them turns it back on.
    await type(tester, 'bulk-start', '5');
    await tester.tap(find.byKey(const Key('bulk-create')));
    await tester.pumpAndSettle();
    expect(repo.created.single.first.label, 'Table 5');
  });

  testWidgets('a bad quantity is said before anything is sent', (tester) async {
    final repo = await pump(tester);
    await open(tester);

    for (final bad in ['0', '101', 'abc', '']) {
      await type(tester, 'bulk-quantity', bad);
      expect(
        find.text(strings.bulkTableQuantityInvalid(100)),
        findsOneWidget,
        reason: '"$bad"',
      );
      expect(find.byKey(const Key('bulk-preview')), findsNothing);
    }
    await tester.tap(find.byKey(const Key('bulk-create')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.created, isEmpty);

    await type(tester, 'bulk-quantity', '100');
    expect(find.text(strings.bulkTablesCreate(100)), findsOneWidget);
  });

  testWidgets('no seats is said too', (tester) async {
    await pump(tester);
    await open(tester);
    await type(tester, 'bulk-seats', '0');
    expect(find.text(strings.bulkTableSeatsInvalid), findsOneWidget);
  });

  testWidgets('pressing Add twice sends one batch', (tester) async {
    final repo = await pump(tester);
    repo.gate = Completer<void>();
    await open(tester);

    await tester.tap(find.byKey(const Key('bulk-create')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bulk-create')), warnIfMissed: false);
    await tester.pump();
    repo.gate!.complete();
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1), reason: 'the second press found it busy');
  });

  testWidgets('a refusal is said in the dialog, which stays open with what was typed', (tester) async {
    final repo = await pump(tester);
    repo.refuse = const CatalogInvalid('This branch already has "Table 9". Nothing was added.');
    await open(tester);
    await type(tester, 'bulk-quantity', '12');

    await tester.tap(find.byKey(const Key('bulk-create')));
    await tester.pumpAndSettle();

    expect(find.text('This branch already has "Table 9". Nothing was added.'), findsOneWidget);
    expect(find.byKey(const Key('bulk-create')), findsOneWidget, reason: 'still open');
    expect(preview(tester), strings.bulkTablePreview('Table 1', 'Table 12', 12));

    // And it can be tried again once the cause is gone.
    repo.refuse = null;
    await tester.tap(find.byKey(const Key('bulk-create')));
    await tester.pumpAndSettle();
    expect(repo.created, hasLength(1));
  });

  testWidgets('Cancel saves nothing, and the single-table form still works', (tester) async {
    final repo = await pump(tester);
    await open(tester);
    await tester.tap(find.text(strings.cancel));
    await tester.pumpAndSettle();
    expect(repo.created, isEmpty);

    await tester.tap(find.text(strings.addTable));
    await tester.pumpAndSettle();
    // The single-table form: label, seats and area, and not the batch form.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byKey(const Key('bulk-quantity')), findsNothing);
  });

  testWidgets('in Arabic the form speaks Arabic', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(_Floor()),
          tablesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildPosTheme(PosPalette.light),
          home: Scaffold(
            body: ManagementFloorPane(
              admin: staffWith({PosCapability.settingsManage}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await open(tester);

    const ar = ArStrings();
    expect(preview(tester), ar.bulkTablePreview('طاولة 1', 'طاولة 10', 10));
  });
}

class _Floor implements CatalogAdminRepository {
  final created = <List<DiningTable>>[];
  AdminRefusal? refuse;
  Completer<void>? gate;

  @override
  Future<AdminResult<List<DiningTable>>> createTables(
    List<DiningTable> tables, {
    required PosStaff by,
  }) async {
    await gate?.future;
    if (refuse != null) return AdminResult.refused(refuse!);
    created.add(tables);
    return AdminResult.done(tables);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
