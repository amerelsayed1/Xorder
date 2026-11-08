import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/option_group.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_menu_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// An item that cannot be saved must say why, and must never freeze the editor.
///
/// Found driving the real till offline (report 2026-10-24, F-2): a second item
/// typed with a SKU the first already uses hit the database's unique index; the
/// resulting exception was not caught, the dialog stayed on "Saving…" with Save
/// and Cancel both disabled, and only Esc got out — losing everything typed.
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

  late _Catalogue catalogue;

  Future<void> pump(WidgetTester tester, _Catalogue repository) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    catalogue = repository;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          catalogAdminRepositoryProvider.overrideWithValue(catalogue),
          taxGroupsAllProvider.overrideWith((ref) async => const []),
          catalogProvider.overrideWith(
            (ref) async => Catalog(
              categories: const [Category(id: 1, nameEn: 'Hot Drinks')],
              products: const [
                Product(
                  id: 9,
                  categoryId: 1,
                  nameEn: 'Espresso',
                  price: Money(3500),
                  sku: 'HD-001',
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

  /// The edit pencil on the one item; "Save" is pressed on the open dialog.
  Future<void> editAndSave(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(const EnStrings().save).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a save that throws leaves the editor usable and says so', (
    tester,
  ) async {
    // What the real repository does today for a duplicate SKU: an exception,
    // not a refusal. Whatever else goes wrong in the database lands here too.
    await pump(
      tester,
      _Catalogue(
        onSave: (_) => throw PosDbException(
          PosDbFailure.query,
          'duplicate key value violates unique constraint',
        ),
      ),
    );
    await editAndSave(tester);

    const en = EnStrings();
    expect(tester.takeException(), isNull);
    expect(
      find.text(en.refusalSaveFailed),
      findsOneWidget,
      reason: 'the owner is told it did not save',
    );
    // Not stuck: Save is offered again and Cancel works.
    expect(find.text(en.save), findsWidgets);
    await tester.tap(find.text(en.cancel).last);
    await tester.pumpAndSettle();
    expect(find.text(en.refusalSaveFailed), findsNothing, reason: 'closed');
  });

  testWidgets('a SKU already in use is refused in words, and kept editable', (
    tester,
  ) async {
    await pump(
      tester,
      _Catalogue(
        onSave: (_) => const AdminResult.refused(
          CatalogRefused(CatalogProblem.skuTaken),
        ),
      ),
    );
    await editAndSave(tester);

    const en = EnStrings();
    expect(find.text(en.refusalSkuTaken), findsOneWidget);
    expect(find.text(en.save), findsWidgets, reason: 'Save is back');
  });

  test('the table count is a number, not a placeholder', () {
    // `'\$tables tables'` in a Dart string is the literal text `$tables`.
    expect(const EnStrings().tableSummary(3), '3 tables');
    expect(const ArStrings().tableSummary(3), '3 طاولة');
    expect(const EnStrings().tableSummary(0), '0 tables');
  });
}

/// A catalogue whose save does whatever the test says; everything else throws,
/// so a test that strays outside the product path fails loudly.
class _Catalogue implements CatalogAdminRepository {
  _Catalogue({required this.onSave});

  final AdminResult<Product> Function(Product product) onSave;

  @override
  Future<AdminResult<Product>> saveProduct(
    Product product, {
    required PosStaff by,
  }) async => onSave(product);

  @override
  Future<List<OptionGroupRef>> productOptionGroups(int productId) async =>
      const [];

  @override
  Future<List<LibraryGroup>> optionLibrary() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
