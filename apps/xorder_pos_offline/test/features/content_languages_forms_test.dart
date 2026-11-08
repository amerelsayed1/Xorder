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
import 'package:shared_module/domain/models/content_languages.dart';
import 'package:shared_module/domain/models/option_group.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_menu_pane.dart';
import 'package:xorder_pos_offline/features/admin/presentation/menu_editor_widgets.dart' show MenuDialog;

import 'package:xorder_pos_test_support/fakes.dart';

/// XORD-005 — the menu forms ask only for the languages the menu is written in,
/// and a save never erases what a hidden language already holds.
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

  const hot = Category(id: 1, nameEn: 'Hot Drinks', nameAr: 'مشروبات ساخنة');
  const espresso = Product(
    id: 9,
    categoryId: 1,
    nameEn: 'Espresso',
    nameAr: 'اسبريسو',
    price: Money(3500),
  );

  late _Catalogue catalogue;

  Future<void> pump(
    WidgetTester tester,
    ContentLanguages languages, {
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
          contentLanguagesProvider.overrideWith((ref) async => languages),
          taxGroupsAllProvider.overrideWith((ref) async => const []),
          catalogProvider.overrideWith(
            (ref) async => Catalog(
              categories: const [hot],
              products: const [espresso],
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
          home: Scaffold(body: ManagementMenuPane(admin: manager, mode: mode)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder dialogFields() => find.descendant(
    of: find.byType(MenuDialog),
    matching: find.byType(TextField),
  );

  /// How many name boxes the item editor shows: the text boxes ahead of price.
  int nameBoxes(WidgetTester tester) {
    final fields = tester.widgetList<TextField>(dialogFields()).toList();
    return fields.indexWhere((f) => f.key == const Key('product-price'));
  }

  Future<void> openNewItem(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('menu-add-item')));
    await tester.pumpAndSettle();
  }

  Future<void> openEditItem(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('menu-dialog-save')));
    await tester.pumpAndSettle();
  }

  group('an item', () {
    testWidgets('no language chosen (both): still one name field, in the till language', (tester) async {
      // XORD-035: the POS has no two-box form; a till that never chose reads
      // `both` as its own language.
      await pump(tester, ContentLanguages.both);
      await openNewItem(tester);

      expect(nameBoxes(tester), 1);
    });

    testWidgets('Arabic only: one name field, and it is the Arabic one', (tester) async {
      await pump(tester, ContentLanguages.arabic);
      await openNewItem(tester);

      expect(nameBoxes(tester), 1);

      await tester.enterText(dialogFields().first, 'كابتشينو');
      await tester.enterText(find.byKey(const Key('product-price')), '40');
      await save(tester);

      final saved = catalogue.product!;
      expect(saved.nameAr, 'كابتشينو');
      expect(saved.nameEn, 'كابتشينو', reason: 'name_en is NOT NULL: it mirrors');
    });

    testWidgets('English only: one name field, and it is the English one', (tester) async {
      await pump(tester, ContentLanguages.english);
      await openNewItem(tester);

      expect(nameBoxes(tester), 1);

      await tester.enterText(dialogFields().first, 'Cappuccino');
      await tester.enterText(find.byKey(const Key('product-price')), '40');
      await save(tester);

      expect(catalogue.product!.nameEn, 'Cappuccino');
    });

    testWidgets('English only, editing: the hidden Arabic name survives the save', (tester) async {
      await pump(tester, ContentLanguages.english);
      await openEditItem(tester);

      await tester.enterText(dialogFields().first, 'Espresso Double');
      await save(tester);

      expect(catalogue.product!.nameEn, 'Espresso Double');
      expect(catalogue.product!.nameAr, 'اسبريسو', reason: 'not erased');
    });

    testWidgets('Arabic only, editing: the hidden English name survives the save', (tester) async {
      await pump(tester, ContentLanguages.arabic);
      await openEditItem(tester);

      await tester.enterText(dialogFields().first, 'اسبريسو دبل');
      await save(tester);

      expect(catalogue.product!.nameAr, 'اسبريسو دبل');
      expect(catalogue.product!.nameEn, 'Espresso', reason: 'a real translation is kept');
    });
  });

  group('a category', () {
    Future<void> openNewCategory(WidgetTester tester) async {
      await tester.tap(find.text(en.addCategory));
      await tester.pumpAndSettle();
    }

    testWidgets('Arabic only: one field, saved as Arabic', (tester) async {
      await pump(tester, ContentLanguages.arabic, mode: MenuPaneMode.sections);
      await openNewCategory(tester);

      expect(dialogFields(), findsOneWidget);
      await tester.enterText(dialogFields().first, 'حلويات');
      await save(tester);

      expect(catalogue.category!.nameAr, 'حلويات');
      expect(catalogue.category!.nameEn, 'حلويات');
    });

    testWidgets('English only: one field, saved as English, Arabic left empty', (tester) async {
      await pump(tester, ContentLanguages.english, mode: MenuPaneMode.sections);
      await openNewCategory(tester);

      expect(dialogFields(), findsOneWidget);
      await tester.enterText(dialogFields().first, 'Desserts');
      await save(tester);

      expect(catalogue.category!.nameEn, 'Desserts');
      expect(catalogue.category!.nameAr ?? '', isEmpty);
    });

    testWidgets('no language chosen (both): still one field, in the till language', (tester) async {
      await pump(tester, ContentLanguages.both, mode: MenuPaneMode.sections);
      await openNewCategory(tester);

      expect(dialogFields(), findsOneWidget);
    });
  });
}

class _Catalogue implements CatalogAdminRepository {
  Product? product;
  Category? category;

  @override
  Future<AdminResult<Product>> saveProduct(
    Product product, {
    required PosStaff by,
  }) async {
    this.product = product;
    return AdminResult.done(product);
  }

  @override
  Future<AdminResult<Category>> saveCategory(
    Category category, {
    required PosStaff by,
  }) async {
    this.category = category;
    return AdminResult.done(category);
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
