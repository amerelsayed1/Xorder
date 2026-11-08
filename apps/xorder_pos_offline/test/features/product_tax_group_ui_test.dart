import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/option_group.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_menu_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// Putting an item on a named rate (§17).
///
/// **The picker that made the named rates usable.** `tax_group_id` has been on
/// `pos_products` since Wave M and read by the catalogue query ever since; no
/// statement in the app wrote it, so a business could define a zero-rated
/// group and had no way to put a bottle of water on it.
void main() {
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

  const zero = TaxGroup(id: 5, nameEn: 'Zero-rated', rateBp: 0);
  const reduced = TaxGroup(id: 6, nameEn: 'Reduced', rateBp: 1250);

  late _Catalogue catalogue;

  Future<void> pump(
    WidgetTester tester, {
    List<TaxGroup> groups = const [zero, reduced],
    Product? existing,
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
          taxGroupsAllProvider.overrideWith((ref) async => groups),
          // The pane lists from `catalogProvider`, not from the admin
          // repository — the admin one only writes.
          catalogProvider.overrideWith(
            (ref) async => Catalog(
              categories: const [Category(id: 1, nameEn: 'Hot Drinks')],
              products: [
                existing ??
                    const Product(
                      id: 9,
                      categoryId: 1,
                      nameEn: 'Espresso',
                      price: Money(3500),
                    ),
              ],
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
          home: const Scaffold(body: ManagementMenuPane(admin: manager)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the item editor. The row's pencil, not the row itself — tapping a
  /// product row does nothing in this pane.
  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the picker offers every rate with its percent', (tester) async {
    // The percent is on the chip because "Reduced" tells a business owner
    // nothing about what the customer pays.
    await pump(tester);
    await openEditor(tester);

    expect(find.text('TAX RATE'), findsOneWidget);
    expect(find.text('Zero-rated · 0%'), findsOneWidget);
    expect(find.text('Reduced · 12.5%'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('an item starts on the default and says so', (tester) async {
    // Null means "follow the category, or the fallback rate", which is what
    // almost every item on a menu wants.
    await pump(tester);
    await openEditor(tester);

    expect(find.byKey(const Key('product-tax-default')), findsOneWidget);
    expect(find.byKey(const Key('product-tax-5')), findsOneWidget);
  });

  testWidgets('picking a rate saves it on the item', (tester) async {
    await pump(tester);
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('product-tax-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(catalogue.saved?.taxGroupId, 5);
  });

  testWidgets('and moving it back to the default clears it', (tester) async {
    // `clearTaxGroup`: a null meaning "back to the fallback" and a null meaning
    // "unchanged" are different intentions.
    await pump(
      tester,
      existing: const Product(
        id: 9,
        categoryId: 1,
        nameEn: 'Espresso',
        price: Money(3500),
        taxGroupId: 5,
      ),
    );
    await openEditor(tester);

    await tester.tap(find.byKey(const Key('product-tax-default')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(catalogue.saved, isNotNull);
    expect(catalogue.saved!.taxGroupId, isNull);
  });

  testWidgets('with no rates configured the picker is absent', (tester) async {
    // A picker whose only option is "the default" is a question with one
    // answer.
    await pump(tester, groups: const []);
    await openEditor(tester);

    expect(find.text('TAX RATE'), findsNothing);
    expect(find.byKey(const Key('product-tax-default')), findsNothing);
    expect(find.text('Save'), findsOneWidget, reason: 'the rest still works');
  });

  testWidgets('an item can be counted in stock, in a unit', (tester) async {
    // The bottled water a business also sells: counted when bought, so how
    // much is left is a number somebody can check.
    await pump(tester);
    await openEditor(tester);

    await tester.ensureVisible(find.byKey(const Key('product-track-stock')));
    await tester.tap(find.byKey(const Key('product-track-stock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-unit-kg')));
    await tester.pump();
    await tester.tap(find.text(const EnStrings().save).last);
    await tester.pumpAndSettle();

    expect(catalogue.saved?.isStocked, isTrue);
    expect(catalogue.saved?.stockUnit, QuantityUnit.kilogram);
  });

}

/// Records what the pane asked to save. Everything else throws, so a test that
/// strays outside the product path fails loudly rather than silently passing.
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

  // The editor reads the item's sizes and extras before it opens. None here:
  // this suite is about the rate, and untouched groups are never written.
  @override
  Future<List<OptionGroupRef>> productOptionGroups(int productId) async =>
      const [];

  @override
  Future<List<LibraryGroup>> optionLibrary() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
