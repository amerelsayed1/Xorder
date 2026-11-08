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
import 'package:shared_module/domain/models/combo_draft.dart';
import 'package:shared_module/domain/models/content_languages.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_combos_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The combo editor, driven the way a manager drives it.
///
/// The rules themselves are `combo_draft_test.dart`'s and the database's are
/// `combos_admin_test.dart`'s. What only a widget test can say is that the
/// boxes become the right draft — a price typed as `85.00` is 8500 minor
/// units, a group's id survives being edited — that a rule broken is said in
/// words before the repository is asked, that a refusal from the repository
/// is shown without closing the dialog, and that a save reaches the list.
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

  const meals = Category(id: 1, nameEn: 'Meals', nameAr: 'وجبات');
  const drinksCategory = Category(id: 2, nameEn: 'Drinks');
  const burger = Product(id: 10, categoryId: 1, nameEn: 'Burger', price: Money(4500));
  const chips = Product(id: 11, categoryId: 1, nameEn: 'Chips', price: Money(2500));
  const cola = Product(id: 12, categoryId: 2, nameEn: 'Cola', price: Money(1500));

  ComboDraft existing({bool available = true}) => ComboDraft(
    id: 7,
    categoryId: 1,
    nameEn: 'Burger meal',
    nameAr: 'وجبة برجر',
    price: const Money(8500),
    sku: 'BM1',
    taxGroupId: 3,
    isAvailable: available,
    groups: const [
      ComboGroupDraft(
        id: 70,
        nameEn: 'Burger',
        options: [ComboOptionDraft(productId: 10)],
      ),
      ComboGroupDraft(
        id: 71,
        nameEn: 'Side',
        minSelect: 0,
        maxSelect: 2,
        options: [
          ComboOptionDraft(productId: 11),
          ComboOptionDraft(productId: 12, priceDelta: Money(500)),
        ],
      ),
    ],
  );

  Future<_Combos?> pump(
    WidgetTester tester, {
    _Combos? repository,
    bool offline = true,
    Locale locale = const Locale('en'),
    ContentLanguages languages = ContentLanguages.both,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final combos = offline ? (repository ?? _Combos()) : null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(english: locale.languageCode == 'en'),
          catalogAdminRepositoryProvider.overrideWithValue(combos),
          contentLanguagesProvider.overrideWith((ref) async => languages),
          catalogProvider.overrideWith(
            (ref) async => Catalog(
              categories: const [meals, drinksCategory],
              products: const [burger, chips, cola],
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
          home: const Scaffold(body: ManagementCombosPane(admin: manager)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return combos;
  }

  /// A tap that first scrolls the dialog's list to the thing — the editor is
  /// taller than the dialog once a group is open.
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pump();
  }

  /// Open a dropdown and choose the entry showing [label]. The open menu
  /// repeats the selected entry, so the last match is the one in the menu.
  Future<void> choose(WidgetTester tester, String key, String label) async {
    await tapKey(tester, key);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  Finder error() => find.byKey(const Key('combo-error'));

  group('the list', () {
    testWidgets('says so when there is nothing yet', (tester) async {
      await pump(tester);

      expect(find.text('No combos yet.'), findsOneWidget);
      expect(find.byKey(const Key('combos-new')), findsOneWidget);
    });

    testWidgets('a row says what is in it, and marks a retired one', (
      tester,
    ) async {
      await pump(
        tester,
        repository: _Combos([existing(), existing(available: false).copyWith()]),
      );

      // 2 choices, 3 items — and the category it sits in.
      expect(find.text('Meals · 2 choice(s) · 3 item(s)'), findsOneWidget);
      expect(
        find.text('Meals · 2 choice(s) · 3 item(s) · Retired'),
        findsOneWidget,
      );
      // The price, in major units, on each row.
      expect(find.text('85.00 EGP'), findsNWidgets(2));
    });

    testWidgets('a cloud till has no editor, only a pointer', (tester) async {
      await pump(tester, offline: false);

      expect(find.byKey(const Key('combos-new')), findsNothing);
      expect(find.byType(ManagementCombosPane), findsOneWidget);
    });

    testWidgets('in Arabic it is the owner\'s word for it', (tester) async {
      await pump(tester, locale: const Locale('ar'));

      expect(find.text('الكومبو'), findsOneWidget);
    });
  });

  group('content languages (XORD-005)', () {
    testWidgets('Arabic only: one name box, group names Arabic, English mirrors', (
      tester,
    ) async {
      final repository = (await pump(
        tester,
        languages: ContentLanguages.arabic,
      ))!;

      await tapKey(tester, 'combos-new');
      expect(find.byKey(const Key('combo-name')), findsNothing);
      expect(find.byKey(const Key('combo-name-ar')), findsOneWidget);

      await type(tester, 'combo-name-ar', 'وجبة برجر');
      await type(tester, 'combo-price', '85');
      await tapKey(tester, 'combo-add-group');
      expect(find.byKey(const Key('combo-group-name-0')), findsNothing);
      await type(tester, 'combo-group-name-ar-0', 'اختر جانبا');
      await tapKey(tester, 'combo-add-option-0');
      await choose(tester, 'combo-option-product-0-0', 'Chips');
      await tapKey(tester, 'combo-save');

      final saved = repository.saved.single;
      expect(saved.nameAr, 'وجبة برجر');
      expect(saved.nameEn, 'وجبة برجر');
      expect(saved.groups.single.nameAr, 'اختر جانبا');
      expect(saved.groups.single.nameEn, 'اختر جانبا');
    });

    testWidgets('English only, editing: the hidden Arabic names survive', (
      tester,
    ) async {
      final repository = (await pump(
        tester,
        repository: _Combos([
          const ComboDraft(
            id: 7,
            categoryId: 1,
            nameEn: 'Burger meal',
            nameAr: 'وجبة برجر',
            price: Money(8500),
            groups: [
              ComboGroupDraft(
                id: 70,
                nameEn: 'Burger',
                nameAr: 'برجر',
                options: [ComboOptionDraft(productId: 10)],
              ),
            ],
          ),
        ]),
        languages: ContentLanguages.english,
      ))!;

      await tapKey(tester, 'combo-row-7');
      expect(find.byKey(const Key('combo-name-ar')), findsNothing);
      expect(find.byKey(const Key('combo-group-name-ar-0')), findsNothing);

      await type(tester, 'combo-name', 'Burger deal');
      await tapKey(tester, 'combo-save');

      final saved = repository.saved.single;
      expect(saved.nameEn, 'Burger deal');
      expect(saved.nameAr, 'وجبة برجر');
      expect(saved.groups.single.nameAr, 'برجر');
    });

    testWidgets('XORD-035: Arabic only runs right to left', (tester) async {
      await pump(tester, languages: ContentLanguages.arabic);
      await tapKey(tester, 'combos-new');

      expect(
        Directionality.of(tester.element(find.byKey(const Key('combo-name-ar')))),
        TextDirection.rtl,
      );
    });

    testWidgets('XORD-035: English only runs left to right', (tester) async {
      await pump(tester, languages: ContentLanguages.english);
      await tapKey(tester, 'combos-new');

      expect(
        Directionality.of(tester.element(find.byKey(const Key('combo-name')))),
        TextDirection.ltr,
      );
    });

    testWidgets('no language chosen (both): one name box, in the till language', (tester) async {
      // XORD-035: no second-language box on any till form.
      await pump(tester);

      await tapKey(tester, 'combos-new');

      expect(find.byKey(const Key('combo-name')), findsOneWidget);
      expect(find.byKey(const Key('combo-name-ar')), findsNothing);
    });
  });

  group('making one', () {
    testWidgets('typed boxes become the draft that is saved', (tester) async {
      final repository = (await pump(tester))!;

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', ' Burger meal ');
      // Major units, never through a double: 85.00 is 8500, not 8499.99….
      await type(tester, 'combo-price', '85.00');
      await type(tester, 'combo-sku', 'BM1');

      await tapKey(tester, 'combo-add-group');
      await type(tester, 'combo-group-name-0', 'Choose a side');
      await type(tester, 'combo-group-min-0', '0');
      await type(tester, 'combo-group-max-0', '2');

      await tapKey(tester, 'combo-add-option-0');
      await choose(tester, 'combo-option-product-0-0', 'Chips');
      await tapKey(tester, 'combo-add-option-0');
      await choose(tester, 'combo-option-product-0-1', 'Cola');
      await type(tester, 'combo-option-delta-0-1', '5.00');

      await tapKey(tester, 'combo-save');

      final saved = repository.saved.single;
      expect(saved.id, 0);
      expect(saved.categoryId, 1, reason: 'the first category is the default');
      // Trimmed by the dialog's name resolution (XORD-005); the repository
      // trims again, so the stored value is the same either way.
      expect(saved.nameEn, 'Burger meal');
      expect(saved.price.minor, 8500);
      expect(saved.sku, 'BM1');
      expect(saved.taxGroupId, isNull);
      expect(saved.isAvailable, isTrue);

      final group = saved.groups.single;
      expect(group.id, 0);
      expect(group.nameEn, 'Choose a side');
      expect(group.minSelect, 0);
      expect(group.maxSelect, 2);
      expect(group.options.map((o) => o.productId), [11, 12]);
      expect(group.options.map((o) => o.priceDelta.minor), [0, 500]);

      // The dialog closed and the list shows what was made.
      expect(find.byKey(const Key('combo-save')), findsNothing);
      expect(find.text('Meals · 1 choice(s) · 2 item(s)'), findsOneWidget);
    });

    testWidgets('a category can be chosen', (tester) async {
      final repository = (await pump(tester))!;

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', 'Cola deal');
      await type(tester, 'combo-price', '10');
      await choose(tester, 'combo-category', 'Drinks');
      await tapKey(tester, 'combo-add-group');
      await type(tester, 'combo-group-name-0', 'Drink');
      await tapKey(tester, 'combo-add-option-0');
      await choose(tester, 'combo-option-product-0-0', 'Cola');
      await tapKey(tester, 'combo-save');

      expect(repository.saved.single.categoryId, 2);
    });

    testWidgets('a new combo has no retire switch — nothing to retire yet', (
      tester,
    ) async {
      await pump(tester);

      await tapKey(tester, 'combos-new');

      expect(find.byKey(const Key('combo-available')), findsNothing);
    });
  });

  group('a rule broken is said before the repository is asked', () {
    testWidgets('a blank name', (tester) async {
      final repository = (await pump(tester))!;

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-price', '10');
      await tapKey(tester, 'combo-save');

      expect(
        find.text(
          'A combo needs a name — it is what the kitchen ticket prints.',
        ),
        findsOneWidget,
      );
      expect(repository.saved, isEmpty);
      expect(find.byKey(const Key('combo-save')), findsOneWidget);
    });

    testWidgets('a price that is not a number', (tester) async {
      final repository = (await pump(tester))!;

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', 'Meal');
      await type(tester, 'combo-price', 'eighty');
      await tapKey(tester, 'combo-save');

      expect(error(), findsOneWidget);
      expect(repository.saved, isEmpty);
    });

    testWidgets('no choices at all', (tester) async {
      final repository = (await pump(tester))!;

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', 'Meal');
      await type(tester, 'combo-price', '10');
      await tapKey(tester, 'combo-save');

      expect(
        find.text(
          'Add at least one choice — a combo with nothing in it cannot be '
          'sold.',
        ),
        findsOneWidget,
      );
      expect(repository.saved, isEmpty);
    });

    testWidgets('a choice with nothing to pick', (tester) async {
      final repository = (await pump(tester))!;

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', 'Meal');
      await type(tester, 'combo-price', '10');
      await tapKey(tester, 'combo-add-group');
      await type(tester, 'combo-group-name-0', 'Drink');
      await tapKey(tester, 'combo-save');

      expect(
        find.text(
          'Every choice needs at least one item, or the meal can never be '
          'completed.',
        ),
        findsOneWidget,
      );
      expect(repository.saved, isEmpty);
    });

    testWidgets('an item row left on "Item" is dropped, not saved blank', (
      tester,
    ) async {
      final repository = (await pump(tester))!;

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', 'Meal');
      await type(tester, 'combo-price', '10');
      await tapKey(tester, 'combo-add-group');
      await type(tester, 'combo-group-name-0', 'Side');
      await tapKey(tester, 'combo-add-option-0');
      await choose(tester, 'combo-option-product-0-0', 'Chips');
      await tapKey(tester, 'combo-add-option-0'); // never given a product
      await tapKey(tester, 'combo-save');

      expect(
        repository.saved.single.groups.single.options.map((o) => o.productId),
        [11],
      );
    });

    testWidgets('typing again clears the message', (tester) async {
      await pump(tester);

      await tapKey(tester, 'combos-new');
      await tapKey(tester, 'combo-save');
      expect(error(), findsOneWidget);

      await type(tester, 'combo-name', 'M');
      expect(error(), findsNothing);
    });
  });

  group('when the repository refuses', () {
    testWidgets('the reason is shown and the dialog stays open', (
      tester,
    ) async {
      final repository = _Combos()
        ..refuse = const ComboRefused(ComboProblem.skuTaken);
      await pump(tester, repository: repository);

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', 'Meal');
      await type(tester, 'combo-price', '10');
      await tapKey(tester, 'combo-add-group');
      await type(tester, 'combo-group-name-0', 'Side');
      await tapKey(tester, 'combo-add-option-0');
      await choose(tester, 'combo-option-product-0-0', 'Chips');
      await tapKey(tester, 'combo-save');

      expect(find.text('Another combo already uses that SKU.'), findsOneWidget);
      // Still open, with what was typed — a refusal must not cost the work.
      expect(find.byKey(const Key('combo-save')), findsOneWidget);
      expect(textOf(tester, 'combo-name'), 'Meal');
      expect(repository.saved, isEmpty);
    });

    testWidgets('a permission refusal reads as one', (tester) async {
      final repository = _Combos()
        ..refuse = const NotPermitted(PosCapability.catalogManage);
      await pump(tester, repository: repository);

      await tapKey(tester, 'combos-new');
      await type(tester, 'combo-name', 'Meal');
      await type(tester, 'combo-price', '10');
      await tapKey(tester, 'combo-add-group');
      await type(tester, 'combo-group-name-0', 'Side');
      await tapKey(tester, 'combo-add-option-0');
      await choose(tester, 'combo-option-product-0-0', 'Chips');
      await tapKey(tester, 'combo-save');

      expect(error(), findsOneWidget);
      expect(find.byKey(const Key('combo-save')), findsOneWidget);
    });
  });

  group('editing one', () {
    testWidgets('the boxes start from what it holds', (tester) async {
      await pump(tester, repository: _Combos([existing()]));

      await tapKey(tester, 'combo-row-7');

      expect(textOf(tester, 'combo-name'), 'Burger meal');
      expect(find.byKey(const Key('combo-name-ar')), findsNothing);
      expect(textOf(tester, 'combo-price'), '85.00');
      expect(textOf(tester, 'combo-sku'), 'BM1');
      expect(textOf(tester, 'combo-group-name-1'), 'Side');
      expect(textOf(tester, 'combo-group-min-1'), '0');
      expect(textOf(tester, 'combo-group-max-1'), '2');
      // A zero upgrade is a blank box, a real one is its amount.
      expect(textOf(tester, 'combo-option-delta-1-0'), '');
      expect(textOf(tester, 'combo-option-delta-1-1'), '5.00');
    });

    testWidgets('ids and the tax rate survive a save nobody changed', (
      tester,
    ) async {
      final repository = (await pump(
        tester,
        repository: _Combos([existing()]),
      ))!;

      await tapKey(tester, 'combo-row-7');
      await tapKey(tester, 'combo-save');

      final saved = repository.saved.single;
      expect(saved.id, 7);
      // Not editable here, so saving must not quietly reset it to the default.
      expect(saved.taxGroupId, 3);
      expect(saved.groups.map((g) => g.id), [70, 71]);
      expect(saved.price.minor, 8500);
    });

    testWidgets('it can be retired', (tester) async {
      final repository = (await pump(
        tester,
        repository: _Combos([existing()]),
      ))!;

      await tapKey(tester, 'combo-row-7');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('combo-available')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'combo-save');

      expect(repository.saved.single.isAvailable, isFalse);
      expect(find.textContaining('Retired'), findsOneWidget);
    });

    testWidgets('a choice can be removed, and its items go with it', (
      tester,
    ) async {
      final repository = (await pump(
        tester,
        repository: _Combos([existing()]),
      ))!;

      await tapKey(tester, 'combo-row-7');
      await tapKey(tester, 'combo-group-remove-1');
      await tapKey(tester, 'combo-save');

      final saved = repository.saved.single;
      expect(saved.groups.map((g) => g.id), [70]);
      expect(saved.groups.single.options.map((o) => o.productId), [10]);
    });

    testWidgets('an item can be removed from a choice', (tester) async {
      final repository = (await pump(
        tester,
        repository: _Combos([existing()]),
      ))!;

      await tapKey(tester, 'combo-row-7');
      await tapKey(tester, 'combo-option-remove-1-1');
      await tapKey(tester, 'combo-save');

      expect(
        repository.saved.single.groups.last.options.map((o) => o.productId),
        [11],
      );
    });

    testWidgets('cancel saves nothing', (tester) async {
      final repository = (await pump(
        tester,
        repository: _Combos([existing()]),
      ))!;

      await tapKey(tester, 'combo-row-7');
      await type(tester, 'combo-name', 'Changed');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.saved, isEmpty);
      expect(find.text('Burger meal'), findsOneWidget);
    });
  });
}

/// A combo store that can be LOOKED at: what was saved, and what the list
/// then shows. Everything else on [CatalogAdminRepository] is a surface this
/// pane never touches, and fails loudly if it ever does.
class _Combos implements CatalogAdminRepository {
  _Combos([List<ComboDraft> initial = const []]) : _stored = [...initial];

  final List<ComboDraft> _stored;

  /// Every draft the pane asked to save, as it arrived.
  final saved = <ComboDraft>[];

  /// When set, the next save is refused with this instead.
  AdminRefusal? refuse;

  @override
  Future<List<ComboDraft>> combos() async => [..._stored];

  @override
  Future<AdminResult<ComboDraft>> saveCombo(
    ComboDraft combo, {
    required PosStaff by,
  }) async {
    final refusal = refuse;
    if (refusal != null) return AdminResult.refused(refusal);

    saved.add(combo);
    final id = combo.id == 0 ? 100 + saved.length : combo.id;
    final stored = ComboDraft(
      id: id,
      categoryId: combo.categoryId,
      nameEn: combo.nameEn.trim(),
      nameAr: combo.nameAr,
      price: combo.price,
      taxGroupId: combo.taxGroupId,
      sku: combo.sku,
      isAvailable: combo.isAvailable,
      groups: combo.groups,
    );
    _stored
      ..removeWhere((c) => c.id == id)
      ..add(stored);
    return AdminResult.done(stored);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
