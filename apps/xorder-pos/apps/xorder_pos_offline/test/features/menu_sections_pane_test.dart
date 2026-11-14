import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/option_group.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_menu_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// Adding items inside a section, and the Menu and Sections pages being two
/// different pages.
///
/// Found on the real till: the only "Add item" was a button in the toolbar, far
/// from the list, applying to whichever section happened to be selected — an
/// empty section said "nothing in this category yet" and offered nothing — and
/// the Menu tab's drop-down held two entries, "Menu" and "Sections", that
/// opened the very same screen.
void main() {
  const en = EnStrings();
  const manager = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.catalogManage},
    ),
  );

  const hot = Category(id: 1, nameEn: 'Hot Drinks');
  const desserts = Category(id: 2, nameEn: 'Desserts');
  const espresso = Product(
    id: 9,
    categoryId: 1,
    nameEn: 'Espresso',
    price: Money(3500),
  );
  const tea = Product(id: 10, categoryId: 1, nameEn: 'Tea', price: Money(2000));

  late _Catalogue catalogue;

  Future<void> pump(
    WidgetTester tester, {
    MenuPaneMode mode = MenuPaneMode.menu,
    List<Category> inactive = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    catalogue = _Catalogue()..inactive = inactive;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          catalogAdminRepositoryProvider.overrideWithValue(catalogue),
          taxGroupsAllProvider.overrideWith((ref) async => const []),
          catalogProvider.overrideWith(
            (ref) async => Catalog(
              categories: const [hot, desserts],
              products: const [espresso, tea],
              modifierGroups: const [],
              syncedAt: DateTime.utc(2026),
            ),
          ),
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
            body: ManagementMenuPane(admin: manager, mode: mode),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the Menu page', () {
    testWidgets('the items have a header naming the section, with its count', (
      tester,
    ) async {
      await pump(tester);

      final header = find.byKey(const Key('menu-section-header'));
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('Hot Drinks')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.text(en.sectionItemCount(2))),
        findsOneWidget,
      );
    });

    testWidgets('Add item sits in that header, and is the only one', (
      tester,
    ) async {
      await pump(tester);

      final header = find.byKey(const Key('menu-section-header'));
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const Key('menu-add-item')),
        ),
        findsOneWidget,
      );
      // Not a second one up in the toolbar, applying to who-knows-which section.
      expect(find.text(en.addItem), findsOneWidget);
    });

    testWidgets('an item added there goes into the section being looked at', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('Desserts'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-add-item')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Cheesecake');
      await tester.enterText(find.byKey(const Key('product-price')), '60');
      await tester.tap(find.byKey(const Key('menu-dialog-save')));
      await tester.pumpAndSettle();

      expect(catalogue.saved?.nameEn, 'Cheesecake');
      expect(catalogue.saved?.categoryId, 2, reason: 'Desserts, not Hot Drinks');
    });

    testWidgets('an empty section still offers Add item', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Desserts'));
      await tester.pumpAndSettle();

      expect(find.text(en.nothingInCategoryYet), findsOneWidget);
      expect(find.byKey(const Key('menu-add-item')), findsOneWidget);
    });
  });

  group('the Sections page', () {
    testWidgets('lists the sections with how many items each holds', (
      tester,
    ) async {
      await pump(tester, mode: MenuPaneMode.sections);

      expect(find.text('Hot Drinks'), findsOneWidget);
      expect(find.text('Desserts'), findsOneWidget);
      expect(find.text(en.sectionItemCount(2)), findsOneWidget);
      expect(find.text(en.sectionItemCount(0)), findsOneWidget);
    });

    testWidgets('has no item list and no Add item: that is the Menu page', (
      tester,
    ) async {
      await pump(tester, mode: MenuPaneMode.sections);

      expect(find.text('Espresso'), findsNothing);
      expect(find.byKey(const Key('menu-add-item')), findsNothing);
      expect(find.byKey(const Key('menu-section-header')), findsNothing);
    });

    testWidgets('each section has three actions: a switch, Edit and Delete', (
      tester,
    ) async {
      await pump(tester, mode: MenuPaneMode.sections);

      expect(find.text(en.addCategory), findsOneWidget);
      for (final id in [1, 2]) {
        expect(find.byKey(Key('category-$id-active')), findsOneWidget);
        expect(find.byKey(Key('category-$id-edit')), findsOneWidget);
        expect(find.byKey(Key('category-$id-delete')), findsOneWidget);
      }
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.byIcon(Icons.archive_outlined), findsNothing);
    });

    testWidgets('the switch is on for an active section and turns it off', (
      tester,
    ) async {
      await pump(tester, mode: MenuPaneMode.sections);

      final toggle = find.byKey(const Key('category-1-active'));
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(catalogue.archived.single.id, 1);
      expect(catalogue.restoreFlag, isFalse, reason: 'off, not back on');
    });

    testWidgets('a section that is off is listed with the switch off, and turns back on', (
      tester,
    ) async {
      await pump(
        tester,
        mode: MenuPaneMode.sections,
        inactive: const [Category(id: 3, nameEn: 'Seasonal', isActive: false)],
      );

      expect(find.text('Seasonal'), findsOneWidget);
      final toggle = find.byKey(const Key('category-3-active'));
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(catalogue.archived.single.id, 3);
      expect(catalogue.restoreFlag, isTrue, reason: 'on again');
    });

    testWidgets('Edit opens the section for editing', (tester) async {
      await pump(tester, mode: MenuPaneMode.sections);

      await tester.tap(find.byKey(const Key('category-2-edit')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Desserts'), findsWidgets);
    });

    testWidgets('Delete asks first, and keeping it deletes nothing', (
      tester,
    ) async {
      await pump(tester, mode: MenuPaneMode.sections);

      await tester.tap(find.byKey(const Key('category-2-delete')));
      await tester.pumpAndSettle();
      expect(find.text(en.deleteSectionTitle('Desserts')), findsOneWidget);

      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();

      expect(catalogue.deleted, isEmpty);
    });

    testWidgets('confirming deletes that section', (tester) async {
      await pump(tester, mode: MenuPaneMode.sections);

      await tester.tap(find.byKey(const Key('category-2-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.deleteLabel));
      await tester.pumpAndSettle();

      expect(catalogue.deleted.single.id, 2);
    });

    testWidgets('a section with items is refused, and the refusal is said', (
      tester,
    ) async {
      await pump(tester, mode: MenuPaneMode.sections);
      catalogue.deleteRefusal = const CatalogRefused(
        CatalogProblem.categoryHasItems,
      );

      await tester.tap(find.byKey(const Key('category-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.deleteLabel));
      await tester.pumpAndSettle();

      expect(find.text(en.refusalCategoryHasItems), findsOneWidget);
    });
  });

  test('the item count is worded in both languages', () {
    const ar = ArStrings();
    for (final n in [0, 1, 2, 11]) {
      expect(en.sectionItemCount(n), contains('$n'));
      expect(ar.sectionItemCount(n), contains('$n'));
    }
    expect(ar.sectionItemCount(2), isNot(en.sectionItemCount(2)));
    expect(ar.paneSectionsBlurb, isNot(en.paneSectionsBlurb));
    expect(en.paneSectionsBlurb, isNotEmpty);
  });
}

/// Records the item the editor saved. Everything else the pane might ask for
/// is stubbed or throws, so a test straying outside this path fails loudly.
class _Catalogue implements CatalogAdminRepository {
  Product? saved;
  List<Category> inactive = const [];
  final archived = <Category>[];
  bool? restoreFlag;
  final deleted = <Category>[];
  AdminRefusal? deleteRefusal;

  @override
  Future<List<Category>> inactiveCategories() async => inactive;

  @override
  Future<AdminResult<Category>> archiveCategory(
    Category category, {
    required PosStaff by,
    bool restore = false,
  }) async {
    archived.add(category);
    restoreFlag = restore;
    return AdminResult.done(category);
  }

  @override
  Future<AdminResult<void>> deleteCategory(
    Category category, {
    required PosStaff by,
  }) async {
    final refusal = deleteRefusal;
    if (refusal != null) return AdminResult<void>.refused(refusal);
    deleted.add(category);
    return const AdminResult<void>.done(null);
  }

  @override
  Future<AdminResult<Product>> saveProduct(
    Product product, {
    required PosStaff by,
  }) async {
    saved = product;
    return AdminResult.done(product);
  }

  @override
  Future<List<OptionGroupRef>> productOptionGroups(int productId) async =>
      const [];

  @override
  Future<List<LibraryGroup>> optionLibrary() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
