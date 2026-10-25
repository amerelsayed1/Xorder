import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/menu_import.dart';
import 'package:xorder_pos/features/admin/presentation/menu_import_dialog.dart';

/// Importing a menu, as the operator sees it.
///
/// The parsing is pinned in `menu_import_test.dart` and the file formats in
/// `spreadsheet_reader_test.dart`. What is asserted here is the part that
/// protects the menu: that nothing is written until somebody has seen what
/// would change, and that a file with one bad row cannot be applied at all.
void main() {
  const admin = PosStaff(id: 9, name: 'Mona Fahmy');

  const header = ['Category', 'Name (EN)', 'Name (AR)', 'Price', 'SKU'];

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1200);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// Opens the dialog with [rows] waiting behind the file button.
  ///
  /// Returns the fake repository, so a test can ask what it was handed — or
  /// assert that it was handed nothing at all.
  Future<_Admin> pump(
    WidgetTester tester,
    List<List<String>> rows, {
    String locale = 'en',
    AdminRefusal? refuse,
    bool cancelled = false,
  }) async {
    final repository = _Admin(refuse: refuse);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(const _Catalog()),
          catalogAdminRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MenuImportDialog(
              admin: admin,
              source: () async =>
                  cancelled ? null : MenuFile('menu.csv', rows),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byKey(MenuImportDialog.chooseKey));
    await tester.pumpAndSettle();
  }

  Finder applyButton() => find.byKey(MenuImportDialog.applyKey);

  group('before a file is chosen', () {
    testWidgets('says what the file must contain', (tester) async {
      await pump(tester, const []);

      // The header a restaurant is handed, spelled out rather than described.
      expect(
        find.text('Category, Name (EN), Name (AR), Price, SKU, Barcode, Available'),
        findsOneWidget,
      );
    });

    testWidgets('promises nothing is deleted, before anything is pressed', (
      tester,
    ) async {
      await pump(tester, const []);

      // The question an operator has *before* they dare pick a file, so the
      // answer has to be on screen before they do.
      expect(
        find.textContaining('Nothing is removed'),
        findsOneWidget,
      );
    });

    testWidgets('cannot apply', (tester) async {
      final repository = await pump(tester, const []);

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(repository.applied, isNull);
    });
  });

  group('the preview', () {
    testWidgets('counts what would be created', (tester) async {
      await pump(tester, [
        header,
        ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
        ['Grills', 'Kebab', 'كباب', '75.00', 'GR-03'],
      ]);
      await choose(tester);

      expect(find.text('Adds 2 items'), findsOneWidget);
    });

    testWidgets('names the categories it would invent', (tester) async {
      await pump(tester, [
        header,
        ['Desserts', 'Basbousa', 'بسبوسة', '25.00', 'DS-01'],
      ]);
      await choose(tester);

      expect(find.textContaining('Desserts'), findsWidgets);
    });

    testWidgets('names each price change individually', (tester) async {
      await pump(tester, [
        header,
        ['Grills', 'Mixed Grill', 'مشاوي مشكلة', '55.00', 'GR-01'],
      ]);
      await choose(tester);

      // "Changes 1 item" is not a sentence anybody can approve. The item and
      // its new price are what makes the press an informed one.
      expect(find.text('Mixed Grill'), findsOneWidget);
      expect(find.text('55.00 EGP'), findsOneWidget);
    });

    testWidgets('a file that matches the menu offers nothing to do', (
      tester,
    ) async {
      final repository = await pump(tester, [
        header,
        ['Grills', 'Mixed Grill', 'مشاوي مشكلة', '50.00', 'GR-01'],
      ]);
      await choose(tester);

      expect(find.textContaining('already matches'), findsOneWidget);

      await tester.tap(applyButton());
      await tester.pumpAndSettle();
      expect(repository.applied, isNull);
    });

    testWidgets('shows the file that was read', (tester) async {
      await pump(tester, [
        header,
        ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
      ]);
      await choose(tester);

      expect(find.text('menu.csv'), findsOneWidget);
    });

    testWidgets('cancelling the file dialog leaves the instructions up', (
      tester,
    ) async {
      await pump(tester, const [], cancelled: true);
      await choose(tester);

      expect(find.textContaining('Nothing is removed'), findsOneWidget);
    });
  });

  group('a file with a bad row', () {
    testWidgets('says which line, as the spreadsheet numbers it', (
      tester,
    ) async {
      await pump(tester, [
        header,
        ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
        ['Grills', 'Kebab', 'كباب', 'seventy', 'GR-03'],
      ]);
      await choose(tester);

      // Line 3, not row 2 and not index 1 — the number in the spreadsheet's
      // own gutter, so somebody can go and look at it.
      expect(find.text('Line 3'), findsOneWidget);
    });

    testWidgets('cannot be applied at all, not even its good rows', (
      tester,
    ) async {
      final repository = await pump(tester, [
        header,
        ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
        ['Grills', 'Kebab', 'كباب', 'seventy', 'GR-03'],
      ]);
      await choose(tester);

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      // Half a menu is worse than none: nobody can tell which half landed.
      expect(repository.applied, isNull);
    });
  });

  group('applying', () {
    testWidgets('hands the repository the plan that was shown', (tester) async {
      final repository = await pump(tester, [
        header,
        ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
        ['Grills', 'Mixed Grill', 'مشاوي مشكلة', '55.00', 'GR-01'],
      ]);
      await choose(tester);

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      final plan = repository.applied!;
      expect(plan.creates.length, 1);
      expect(plan.updates.length, 1);
      expect(repository.by?.id, admin.id);
    });

    testWidgets('closes with what was imported', (tester) async {
      MenuImportOutcome? popped;
      final repository = _Admin();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogRepositoryProvider.overrideWithValue(const _Catalog()),
            catalogAdminRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: buildPosTheme(PosPalette.light),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    popped = await MenuImportDialog.show(
                      context,
                      admin: admin,
                      source: () async => MenuFile('menu.csv', [
                        header,
                        ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
                      ]),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await choose(tester);
      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(find.byType(MenuImportDialog), findsNothing);
      expect(popped?.productsCreated, 1);
    });

    testWidgets('a refusal stays on screen and writes nothing further', (
      tester,
    ) async {
      await pump(
        tester,
        [
          header,
          ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
        ],
        refuse: const NotPermitted('catalog.edit'),
      );
      await choose(tester);

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      // The dialog is the only place the refusal can be read, so it stays.
      expect(find.byType(MenuImportDialog), findsOneWidget);
      expect(find.textContaining('catalog.edit'), findsOneWidget);
    });
  });

  group('Arabic', () {
    testWidgets('renders right to left without overflowing', (tester) async {
      await pump(
        tester,
        [
          header,
          ['Grills', 'Kofta', 'كفتة', '60.00', 'GR-02'],
        ],
        locale: 'ar',
      );
      await choose(tester);

      expect(
        Directionality.of(tester.element(find.byType(MenuImportDialog))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the price stays left to right', (tester) async {
      await pump(
        tester,
        [
          header,
          ['Grills', 'Mixed Grill', 'مشاوي مشكلة', '55.00', 'GR-01'],
        ],
        locale: 'ar',
      );
      await choose(tester);

      final price = find.text('55.00 EGP');
      expect(Directionality.of(tester.element(price)), TextDirection.ltr);
    });
  });
}

class _Catalog implements CatalogRepository {
  const _Catalog();

  @override
  Future<Catalog> load({DateTime? since}) async => Catalog(
    categories: const [
      Category(id: 11, nameEn: 'Grills', nameAr: 'مشاوي'),
    ],
    products: const [
      Product(
        id: 101,
        categoryId: 11,
        nameEn: 'Mixed Grill',
        nameAr: 'مشاوي مشكلة',
        price: Money(5000),
        sku: 'GR-01',
      ),
    ],
    modifierGroups: const [],
    syncedAt: DateTime(2026, 9, 8),
  );
}

class _Admin implements CatalogAdminRepository {
  _Admin({this.refuse});

  final AdminRefusal? refuse;

  MenuImportPlan? applied;
  PosStaff? by;

  @override
  Future<AdminResult<MenuImportOutcome>> importMenu(
    MenuImportPlan plan, {
    required PosStaff by,
  }) async {
    if (refuse != null) return AdminResult.refused(refuse!);
    applied = plan;
    this.by = by;
    return AdminResult.done(
      MenuImportOutcome(
        categoriesCreated: plan.newCategories.length,
        productsCreated: plan.creates.length,
        productsUpdated: plan.updates.length,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not part of this test');
}
