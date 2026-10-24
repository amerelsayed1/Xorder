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
import 'package:xorder_pos/domain/models/option_group.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_menu_pane.dart';

import '../support/fakes.dart';

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
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    catalogue = _Catalogue();

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

    testWidgets('still adds, renames and takes sections off the rail', (
      tester,
    ) async {
      await pump(tester, mode: MenuPaneMode.sections);

      expect(find.text(en.addCategory), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.archive_outlined), findsNWidgets(2));
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
