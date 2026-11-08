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
import 'package:xorder_pos/features/admin_mode/admin_messages.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_extras_pane.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_menu_pane.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// Sizes and extras in the back office: the Extras library, and the item
/// editor's "Options & add-ons".
///
/// Both are the cloud dashboard's screens (`ExtrasView.vue`, `ItemForm.vue`)
/// on the till, so what is pinned here is what those screens promise: that a
/// size prices the item and the form says so, that a size cannot be optional
/// or multi-choice, that a sale price belongs to sizes alone — and that an
/// item never ends up with two sets of sizes, which the cloud allows and
/// this till refuses.
void main() {
  const manager = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.catalogManage, PosCapability.staffManage},
    ),
  );

  const burgers = Category(id: 1, nameEn: 'Burgers');
  const drinks = Category(id: 2, nameEn: 'Drinks');

  const sizes = OptionGroupDraft(
    id: 5,
    revision: 1,
    nameEn: 'Burger sizes',
    displayNameEn: 'Size',
    isVariant: true,
    isRequired: true,
    minSelect: 1,
    options: [
      OptionDraft(
        id: 51,
        nameEn: 'Regular',
        price: Money(8500),
        salePrice: Money(7000),
      ),
      OptionDraft(id: 52, nameEn: 'Large', price: Money(11000)),
    ],
  );
  const sauces = OptionGroupDraft(
    id: 6,
    nameEn: 'Sauces',
    maxSelect: 3,
    options: [
      OptionDraft(id: 61, nameEn: 'Garlic', price: Money(500)),
      OptionDraft(id: 62, nameEn: 'BBQ', price: Money(500)),
    ],
  );
  const cutlery = OptionGroupDraft(
    id: 7,
    nameEn: 'Cutlery',
    scope: OptionGroupScope.all,
    options: [OptionDraft(id: 71, nameEn: 'Fork')],
  );
  const ice = OptionGroupDraft(
    id: 8,
    nameEn: 'Ice',
    scope: OptionGroupScope.categories,
    categoryIds: {1, 2},
    options: [OptionDraft(id: 81, nameEn: 'No ice')],
  );
  const drinkSizes = OptionGroupDraft(
    id: 10,
    nameEn: 'Drink sizes',
    isVariant: true,
    isRequired: true,
    minSelect: 1,
    options: [OptionDraft(id: 101, nameEn: 'Can', price: Money(2000))],
  );

  List<LibraryGroup> library() => const [
    LibraryGroup(group: sizes, itemCount: 3),
    LibraryGroup(group: sauces, itemCount: 0),
    LibraryGroup(group: cutlery, itemCount: 40),
    LibraryGroup(group: ice, itemCount: 12),
    LibraryGroup(group: drinkSizes, itemCount: 0),
  ];

  const burger = Product(
    id: 9,
    categoryId: 1,
    nameEn: 'Burger',
    price: Money(8500),
    discountedPrice: Money(7500),
  );

  Future<_Options> pump(
    WidgetTester tester,
    Widget pane, {
    _Options? repository,
    Locale locale = const Locale('en'),
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final options = repository ?? _Options(library: library());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          catalogAdminRepositoryProvider.overrideWithValue(options),
          taxGroupsAllProvider.overrideWith((ref) async => const []),
          catalogProvider.overrideWith(
            (ref) async => Catalog(
              categories: const [burgers, drinks],
              products: const [burger],
              modifierGroups: const [],
              syncedAt: DateTime.utc(2026),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: pane),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return options;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// The switch inside a labelled switch row. The row's centre can fall on
  /// its label, which is not the thing that toggles.
  Finder switchIn(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(Switch),
  );

  Future<void> flip(WidgetTester tester, String key) async {
    await tester.tap(switchIn(key));
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String key) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(TextField),
          matchRoot: true,
        ),
      )
      .controller!
      .text;

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump();
  }

  group('the Extras library', () {
    testWidgets('each row says what it is and where it reaches', (
      tester,
    ) async {
      await pump(tester, const ManagementExtrasPane(admin: manager));

      // Linked one by one: by how many items, or that nothing uses it yet.
      expect(find.text('2 option(s) · 3 item(s)'), findsOneWidget);
      expect(find.text('2 option(s) · Not used yet'), findsOneWidget);
      // Applied wholesale: by its scope, not by a count of links it has none of.
      expect(find.text('1 option(s) · All items'), findsOneWidget);
      expect(find.text('1 option(s) · 2 categor(y/ies)'), findsOneWidget);

      // The heading the cashier reads, only where it differs from the name.
      expect(find.text('On the menu: Size'), findsOneWidget);
      expect(find.textContaining('On the menu:'), findsOneWidget);

      // The two size groups, and nothing else, are marked as sizes.
      expect(find.text('Size / variant'), findsNWidgets(2));
    });

    testWidgets(
      'turning on sizes hides Required and Max select, and the save forces '
      'them on',
      (tester) async {
        final options = await pump(
          tester,
          const ManagementExtrasPane(admin: manager),
        );

        await tapKey(tester, 'extras-new');
        await type(tester, 'extras-name', 'Pizza sizes');
        expect(find.byKey(const Key('extras-required')), findsOneWidget);
        await type(tester, 'extras-max', '4');

        await flip(tester, 'extras-variant');
        expect(find.byKey(const Key('extras-required')), findsNothing);
        expect(find.byKey(const Key('extras-max')), findsNothing);
        expect(find.text(const EnStrings().itemVariantHint), findsOneWidget);

        await tapKey(tester, 'extras-add-option');
        await type(tester, 'extras-option-0-name', 'Medium');
        await type(tester, 'extras-option-0-price', '120');
        await tapKey(tester, 'menu-dialog-save');

        final saved = options.savedGroups.single;
        expect(saved.isVariant, isTrue);
        // A size with no choice, or with two, means nothing when the size is
        // the price — whatever the hidden box said before it was hidden.
        expect(saved.isRequired, isTrue);
        expect(saved.maxSelect, 1);
        expect(saved.options.single.price, const Money(12000));
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets('a sale price is offered on sizes and nowhere else', (
      tester,
    ) async {
      final options = await pump(
        tester,
        const ManagementExtrasPane(admin: manager),
      );

      await tapKey(tester, 'extras-new');
      await type(tester, 'extras-name', 'Sauces');
      await tapKey(tester, 'extras-add-option');
      expect(find.byKey(const Key('extras-option-0-sale')), findsNothing);

      await flip(tester, 'extras-variant');
      expect(find.byKey(const Key('extras-option-0-sale')), findsOneWidget);
      await type(tester, 'extras-option-0-sale', '3');

      // Back to extras: the column goes, and so does what was typed in it.
      await flip(tester, 'extras-variant');
      expect(find.byKey(const Key('extras-option-0-sale')), findsNothing);
      await type(tester, 'extras-option-0-name', 'Garlic');
      await tapKey(tester, 'menu-dialog-save');

      final option = options.savedGroups.single.options.single;
      expect(option.salePrice, isNull);
      expect(option.price, Money.zero, reason: 'a blank price is free');
    });

    testWidgets('categories are asked for only when it applies by category', (
      tester,
    ) async {
      final options = await pump(
        tester,
        const ManagementExtrasPane(admin: manager),
      );

      await tapKey(tester, 'extras-new');
      await type(tester, 'extras-name', 'Ice');
      expect(find.byKey(const Key('extras-categories')), findsNothing);
      expect(find.text(const EnStrings().extrasScopeItemsHint), findsOneWidget);

      await tapKey(tester, 'extras-scope-all');
      expect(find.byKey(const Key('extras-categories')), findsNothing);

      await tapKey(tester, 'extras-scope-categories');
      expect(find.byKey(const Key('extras-category-1')), findsOneWidget);
      expect(find.byKey(const Key('extras-category-2')), findsOneWidget);
      await tapKey(tester, 'extras-category-2');

      await tapKey(tester, 'extras-add-option');
      await type(tester, 'extras-option-0-name', 'No ice');
      await tapKey(tester, 'menu-dialog-save');

      final saved = options.savedGroups.single;
      expect(saved.scope, OptionGroupScope.categories);
      expect(saved.categoryIds, {2});
    });

    testWidgets('deleting a group in use says how many items lose it', (
      tester,
    ) async {
      final options = await pump(
        tester,
        const ManagementExtrasPane(admin: manager),
      );

      await tapKey(tester, 'extra-delete-5');
      expect(
        find.text(
          'Delete this extra? It will be removed from the 3 item(s) currently '
          'using it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(options.deleted.single.id, 5);
      expect(find.byKey(const Key('extra-row-5')), findsNothing);

      // One nothing uses gets the ordinary question.
      await tapKey(tester, 'extra-delete-6');
      expect(
        find.text('Are you sure you want to delete this?'),
        findsOneWidget,
      );
    });

    testWidgets('a refusal is said in Arabic on an Arabic back office', (
      tester,
    ) async {
      const refusal = OptionGroupRefused(
        OptionGroupProblem.wouldGiveSecondSizes,
        names: ['Burger'],
      );
      await pump(
        tester,
        const ManagementExtrasPane(admin: manager),
        repository: _Options(library: library())..refuseLibrary = refusal,
        locale: const Locale('ar'),
      );

      await tapKey(tester, 'extras-new');
      await type(tester, 'extras-name', 'House sizes');
      await tapKey(tester, 'extras-add-option');
      await type(tester, 'extras-option-0-name', 'Regular');
      await tapKey(tester, 'menu-dialog-save');

      final arabic = AdminText.refusal(const ArStrings(), refusal);
      expect(find.text(arabic), findsOneWidget);
      expect(arabic, contains('أحجام'));
      expect(find.textContaining('already has sizes'), findsNothing);
      // Still open, with what was typed still in it.
      expect(textOf(tester, 'extras-name'), 'House sizes');
    });
  });

  group("the item's options", () {
    Future<void> openBurger(WidgetTester tester) async {
      // The row's pencil — the categories' pencils come first.
      await tester.tap(find.byIcon(Icons.edit_outlined).last);
      await tester.pumpAndSettle();
    }

    testWidgets('typed and library groups are saved after the item, in order', (
      tester,
    ) async {
      final options = await pump(
        tester,
        const ManagementMenuPane(admin: manager),
      );
      await openBurger(tester);

      await tapKey(tester, 'product-add-group');
      await type(tester, 'group-0-name', 'Toppings');
      await tapKey(tester, 'group-0-add-option');
      await type(tester, 'group-0-option-0-name', 'Cheese');
      await type(tester, 'group-0-option-0-price', '15');

      await tapKey(tester, 'product-add-from-library');
      // Only what is linked item by item, and not already here: a group that
      // applies by category or everywhere reaches the item by itself.
      expect(find.byKey(const Key('library-pick-6')), findsOneWidget);
      expect(find.byKey(const Key('library-pick-7')), findsNothing);
      expect(find.byKey(const Key('library-pick-8')), findsNothing);
      await tapKey(tester, 'library-pick-6');
      // Read-only, with its options listed the way the cloud joins them.
      expect(find.text('From library  Garlic، BBQ'), findsOneWidget);

      await tapKey(tester, 'menu-dialog-save');

      expect(options.calls, ['saveProduct', 'setProductOptionGroups']);
      final (productId, refs) = options.attached.single;
      expect(productId, 9);
      expect(refs, hasLength(2));
      final typed = (refs[0] as InlineGroupRef).group;
      expect(typed.nameEn, 'Toppings');
      expect(typed.options.single.price, const Money(1500));
      expect((refs[1] as SharedGroupRef).groupId, 6);
    });

    testWidgets("a new item's groups are linked by the id its save returned", (
      tester,
    ) async {
      final options = await pump(
        tester,
        const ManagementMenuPane(admin: manager),
      );
      await tester.tap(find.text(const EnStrings().addItem));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Chicken burger');
      await type(tester, 'product-price', '95');
      await tapKey(tester, 'product-add-from-library');
      await tapKey(tester, 'library-pick-6');
      await tapKey(tester, 'menu-dialog-save');

      expect(options.savedProducts.single.id, 0);
      expect(options.attached.single.$1, 77);
    });

    testWidgets('untouched groups are not written again', (tester) async {
      // Every write of an item's groups is a row on the ledger; correcting a
      // name must not read as rearranging its extras.
      final options = await pump(
        tester,
        const ManagementMenuPane(admin: manager),
        repository: _Options(
          library: library(),
          refs: {9: const [OptionGroupRef.shared(6)]},
        ),
      );
      await openBurger(tester);
      await tapKey(tester, 'menu-dialog-save');

      expect(options.calls, ['saveProduct']);
    });

    testWidgets(
      'with a library size group the price fields mirror its default size',
      (tester) async {
        final options = await pump(
          tester,
          const ManagementMenuPane(admin: manager),
          repository: _Options(
            library: library(),
            refs: {9: const [OptionGroupRef.shared(5)]},
          ),
        );
        await openBurger(tester);

        final price = tester.widget<TextField>(
          find.byKey(const Key('product-price')),
        );
        expect(price.readOnly, isTrue);
        expect(textOf(tester, 'product-price'), '85.00');
        expect(textOf(tester, 'product-offer'), '70.00');
        expect(
          find.text(
            'Priced by its sizes below. The price above mirrors the default — '
            'the first size listed — so edit that size to change it.',
          ),
          findsOneWidget,
        );

        await tapKey(tester, 'menu-dialog-save');
        final saved = options.savedProducts.single;
        expect(saved.price, const Money(8500));
        expect(saved.discountedPrice, const Money(7000));
      },
    );

    testWidgets('a typed size group is mirrored as it is typed', (
      tester,
    ) async {
      final options = await pump(
        tester,
        const ManagementMenuPane(admin: manager),
        repository: _Options(
          library: library(),
          refs: {
            9: const [
              OptionGroupRef.inline(
                OptionGroupDraft(
                  id: 20,
                  nameEn: 'Size',
                  isVariant: true,
                  isRequired: true,
                  minSelect: 1,
                  options: [
                    OptionDraft(id: 201, nameEn: 'Small', price: Money(6000)),
                    OptionDraft(
                      id: 202,
                      nameEn: 'Large',
                      price: Money(9000),
                      salePrice: Money(8000),
                    ),
                  ],
                ),
              ),
            ],
          },
        ),
      );
      await openBurger(tester);

      expect(textOf(tester, 'product-price'), '60.00');
      expect(textOf(tester, 'product-offer'), '', reason: 'Small has no sale');
      expect(find.byKey(const Key('group-0-option-0-default')), findsOneWidget);
      expect(find.byKey(const Key('group-0-option-1-default')), findsNothing);

      await type(tester, 'group-0-option-0-price', '65');
      expect(textOf(tester, 'product-price'), '65.00');

      await tapKey(tester, 'menu-dialog-save');
      expect(options.savedProducts.single.price, const Money(6500));
      expect(options.savedProducts.single.discountedPrice, isNull);
      final group = (options.attached.single.$2.single as InlineGroupRef).group;
      expect(group.id, 20, reason: 'edited in place, never recreated');
      expect(group.options.first.id, 201);
    });

    testWidgets("switching a group to sizes carries the item's price into it", (
      tester,
    ) async {
      await pump(tester, const ManagementMenuPane(admin: manager));
      await openBurger(tester);

      await tapKey(tester, 'product-add-group');
      expect(find.byKey(const Key('group-0-option-0-price')), findsNothing);
      await flip(tester, 'group-0-variant');

      // The 85 and the 75 the owner already had did not vanish when the
      // fields above turned read-only; they became the first size.
      expect(textOf(tester, 'group-0-option-0-price'), '85.00');
      expect(textOf(tester, 'group-0-option-0-sale'), '75.00');
      expect(find.byKey(const Key('group-0-option-0-default')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('product-price'))).readOnly,
        isTrue,
      );
      // Sizes are required and one choice, so neither box is offered.
      expect(find.byKey(const Key('group-0-required')), findsNothing);
      expect(find.byKey(const Key('group-0-max')), findsNothing);
    });

    testWidgets('an item with sizes cannot be given a second set', (
      tester,
    ) async {
      await pump(
        tester,
        const ManagementMenuPane(admin: manager),
        repository: _Options(
          library: library(),
          refs: {9: const [OptionGroupRef.shared(5)]},
        ),
      );
      await openBurger(tester);

      await tapKey(tester, 'product-add-group');
      expect(
        tester.widget<Switch>(switchIn('group-1-variant')).onChanged,
        isNull,
        reason: 'the other group is already the sizes',
      );

      await tapKey(tester, 'product-add-from-library');
      expect(
        tester
            .widget<PopupMenuItem<LibraryGroup>>(
              find.byKey(const Key('library-pick-10')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<PopupMenuItem<LibraryGroup>>(
              find.byKey(const Key('library-pick-6')),
            )
            .enabled,
        isTrue,
      );
    });

    testWidgets('a refused list is said in Arabic and the dialog stays open', (
      tester,
    ) async {
      const refusal = OptionGroupRefused(
        OptionGroupProblem.secondSizes,
        names: ['Burger sizes', 'Portion'],
      );
      await pump(
        tester,
        const ManagementMenuPane(admin: manager),
        repository: _Options(library: library())..refuseGroups = refusal,
        locale: const Locale('ar'),
      );
      await openBurger(tester);
      await tapKey(tester, 'product-add-from-library');
      await tapKey(tester, 'library-pick-6');
      await tapKey(tester, 'menu-dialog-save');

      expect(
        find.text(AdminText.refusal(const ArStrings(), refusal)),
        findsOneWidget,
      );
      expect(find.textContaining('one set of sizes'), findsNothing);
      expect(find.byKey(const Key('menu-dialog-save')), findsOneWidget);
    });

    testWidgets('"Manage extras" leaves for the library', (tester) async {
      var opened = false;
      await pump(
        tester,
        ManagementMenuPane(admin: manager, onOpenExtras: () => opened = true),
      );
      await openBurger(tester);
      expect(find.text('Manage extras →'), findsOneWidget);

      await tapKey(tester, 'product-manage-extras');
      expect(opened, isTrue);
      expect(find.byType(Dialog), findsNothing);
    });
  });

  test('the library is authored only where the menu is', () {
    // On a cloud till the platform's Extras page is the author, and the next
    // sync would erase a group made here.
    expect(
      managementPanesFor(admin: manager, authorsItsOwnCatalogue: false),
      isNot(contains(ManagementPane.extras)),
    );
    expect(
      managementPanesFor(admin: manager, authorsItsOwnCatalogue: true),
      contains(ManagementPane.extras),
    );
    expect(tabOf(ManagementPane.extras), BackOfficeTab.menu);
  });
}

/// A catalogue that remembers what the screens asked of it. Anything else
/// throws, so a screen that strays onto another write fails loudly.
class _Options implements CatalogAdminRepository {
  _Options({required this.library, this.refs = const {}});

  List<LibraryGroup> library;
  final Map<int, List<OptionGroupRef>> refs;

  AdminRefusal? refuseLibrary;
  AdminRefusal? refuseGroups;

  final calls = <String>[];
  final savedGroups = <OptionGroupDraft>[];
  final deleted = <OptionGroupDraft>[];
  final savedProducts = <Product>[];
  final attached = <(int, List<OptionGroupRef>)>[];

  @override
  Future<List<LibraryGroup>> optionLibrary() async => library;

  @override
  Future<List<OptionGroupRef>> productOptionGroups(int productId) async =>
      refs[productId] ?? const [];

  @override
  Future<AdminResult<OptionGroupDraft>> saveOptionGroup(
    OptionGroupDraft group, {
    required PosStaff by,
  }) async {
    calls.add('saveOptionGroup');
    final refusal = refuseLibrary;
    if (refusal != null) return AdminResult.refused(refusal);
    savedGroups.add(group);
    final stored = group.normalized().copyWith(
      id: group.id == 0 ? 100 + savedGroups.length : group.id,
    );
    library = [
      for (final entry in library)
        if (entry.group.id != stored.id) entry,
      LibraryGroup(group: stored, itemCount: 0),
    ];
    return AdminResult.done(stored);
  }

  @override
  Future<AdminResult<void>> deleteOptionGroup(
    OptionGroupDraft group, {
    required PosStaff by,
  }) async {
    calls.add('deleteOptionGroup');
    deleted.add(group);
    library = [
      for (final entry in library)
        if (entry.group.id != group.id) entry,
    ];
    return const AdminResult<void>.done(null);
  }

  @override
  Future<AdminResult<Product>> saveProduct(
    Product product, {
    required PosStaff by,
  }) async {
    calls.add('saveProduct');
    savedProducts.add(product);
    return AdminResult.done(product.id == 0 ? product.copyWith(id: 77) : product);
  }

  @override
  Future<AdminResult<List<OptionGroupRef>>> setProductOptionGroups(
    int productId,
    List<OptionGroupRef> groups, {
    required PosStaff by,
  }) async {
    calls.add('setProductOptionGroups');
    attached.add((productId, groups));
    final refusal = refuseGroups;
    if (refusal != null) return AdminResult.refused(refusal);
    return AdminResult.done(groups);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
