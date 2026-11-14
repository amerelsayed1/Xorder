import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/option_group.dart';

/// The platform's rules for a sizes or extras group, without a database.
///
/// The repository asks these first and then the questions only it can answer;
/// what is tested here is what a manager can get wrong on the form alone.
void main() {
  OptionGroupDraft sizes({List<OptionDraft>? options}) => OptionGroupDraft(
    nameEn: 'Size',
    isVariant: true,
    options:
        options ??
        const [
          OptionDraft(nameEn: 'Regular', price: Money(8500)),
          OptionDraft(nameEn: 'Large', price: Money(11000)),
        ],
  );

  OptionGroupProblem? refusal(OptionGroupDraft group, {bool inLibrary = true}) =>
      OptionGroupRules.refusal(group.normalized(), inLibrary: inLibrary);

  group('what saving makes of a size group', () {
    test('a size is always required and single-select', () {
      // Forced rather than refused, as the platform does: "no size" and "two
      // sizes" mean nothing when the size is the price.
      final saved = sizes()
          .copyWith(isRequired: false, maxSelect: 4, freeOptions: 2)
          .normalized();

      expect(saved.isRequired, isTrue);
      expect(saved.maxSelect, 1);
      expect(saved.minSelect, 1);
      expect(saved.freeOptions, 0, reason: 'a free size would be a free item');
    });

    test('an extra cannot be on sale, so its sale price is dropped', () {
      const extras = OptionGroupDraft(
        nameEn: 'Extras',
        maxSelect: 3,
        options: [
          OptionDraft(
            nameEn: 'Cheese',
            price: Money(1500),
            salePrice: Money(1000),
          ),
        ],
      );

      expect(extras.normalized().options.single.salePrice, isNull);
      expect(refusal(extras), isNull, reason: 'dropped, not refused');
    });

    test('a size keeps its sale price', () {
      final onSale = sizes(
        options: const [
          OptionDraft(
            nameEn: 'Regular',
            price: Money(8500),
            salePrice: Money(7000),
          ),
        ],
      );
      expect(onSale.normalized().options.single.salePrice, const Money(7000));
      expect(refusal(onSale), isNull);
    });

    test('a required extras group needs at least one choice', () {
      const extras = OptionGroupDraft(
        nameEn: 'Sauce',
        isRequired: true,
        maxSelect: 2,
        options: [OptionDraft(nameEn: 'Garlic')],
      );
      expect(extras.normalized().minSelect, 1);
    });

    test('blank optional names are stored as none, not as empty', () {
      final saved = sizes()
          .copyWith(nameAr: '  ', displayNameEn: ' ', displayNameAr: '')
          .normalized();
      expect(saved.nameAr, isNull);
      expect(saved.displayNameEn, isNull);
      expect(saved.displayNameAr, isNull);
    });

    test('category links only survive on a category-wide group', () {
      final saved = sizes()
          .copyWith(scope: OptionGroupScope.all, categoryIds: {4, 5})
          .normalized();
      expect(saved.categoryIds, isEmpty);
    });
  });

  group('what cannot be saved', () {
    test('a group with no name', () {
      expect(refusal(sizes().copyWith(nameEn: '   ')), isNotNull);
    });

    test('a choice count outside 1 to 50', () {
      const extras = OptionGroupDraft(nameEn: 'Extras');
      expect(refusal(extras.copyWith(maxSelect: 0)), isNotNull);
      expect(refusal(extras.copyWith(maxSelect: 51)), isNotNull);
      expect(refusal(extras.copyWith(maxSelect: 50)), isNull);
    });

    test('more than 50 options', () {
      final many = [
        for (var i = 0; i < 51; i++) OptionDraft(nameEn: 'Option $i'),
      ];
      expect(
        refusal(OptionGroupDraft(nameEn: 'Extras', options: many)),
        isNotNull,
      );
      expect(
        refusal(OptionGroupDraft(nameEn: 'Extras', options: many.sublist(1))),
        isNull,
      );
    });

    test('an option that costs less than nothing', () {
      expect(
        refusal(
          const OptionGroupDraft(
            nameEn: 'Extras',
            options: [OptionDraft(nameEn: 'Refund', price: Money(-100))],
          ),
        ),
        isNotNull,
      );
    });

    test('a size sale price at or above its normal price', () {
      OptionGroupDraft at(int sale) => sizes(
        options: [
          OptionDraft(
            nameEn: 'Regular',
            price: const Money(8500),
            salePrice: Money(sale),
          ),
        ],
      );

      expect(refusal(at(8500)), isNotNull, reason: 'a sale that saves nothing');
      expect(refusal(at(9000)), isNotNull);
      expect(refusal(at(-1)), isNotNull);
      expect(refusal(at(8499)), isNull);
    });

    test('a group for chosen categories with none chosen', () {
      expect(
        refusal(sizes().copyWith(scope: OptionGroupScope.categories)),
        isNotNull,
      );
      expect(
        refusal(
          sizes().copyWith(scope: OptionGroupScope.categories, categoryIds: {3}),
        ),
        isNull,
      );
    });

    test('a group typed on one item that reaches every item', () {
      final everywhere = sizes().copyWith(scope: OptionGroupScope.all);
      expect(refusal(everywhere, inLibrary: false), isNotNull);
      expect(refusal(everywhere), isNull);
    });

    test('a required group with nothing in it', () {
      // It could never be satisfied, so its item could never be sold.
      expect(refusal(sizes(options: const [])), isNotNull);
      expect(
        refusal(const OptionGroupDraft(nameEn: 'Extras', maxSelect: 2)),
        isNull,
        reason: 'an empty optional group only offers nothing',
      );
    });

    test('an option with no name, or the same option twice', () {
      expect(
        refusal(sizes(options: const [OptionDraft(nameEn: ' ')])),
        isNotNull,
      );
      expect(
        refusal(
          sizes(
            options: const [
              OptionDraft(id: 7, nameEn: 'Regular'),
              OptionDraft(id: 7, nameEn: 'Large'),
            ],
          ),
        ),
        isNotNull,
      );
    });

    test('needing more choices than it allows', () {
      expect(
        refusal(
          const OptionGroupDraft(nameEn: 'Extras', minSelect: 3, maxSelect: 2),
        ),
        isNotNull,
      );
    });
  });

  group('the heading on the sheet', () {
    const plain = ModifierGroup(
      id: 1,
      nameEn: 'Burger sizes',
      nameAr: 'أحجام البرجر',
      modifiers: [],
    );

    test('is the name when no display name is set', () {
      expect(plain.displayName('en'), 'Burger sizes');
      expect(plain.displayName('ar'), 'أحجام البرجر');
    });

    test('is the display name in each language when set', () {
      const headed = ModifierGroup(
        id: 1,
        nameEn: 'Burger sizes',
        nameAr: 'أحجام البرجر',
        displayNameEn: 'Size',
        displayNameAr: 'الحجم',
        modifiers: [],
      );
      expect(headed.displayName('en'), 'Size');
      expect(headed.displayName('ar'), 'الحجم');
    });

    test('never crosses a language to use a display name', () {
      // An Arabic till showing "Size" because only the English heading was
      // filled in would be reading the wrong column to the cashier.
      const englishOnly = ModifierGroup(
        id: 1,
        nameEn: 'Burger sizes',
        nameAr: 'أحجام البرجر',
        displayNameEn: 'Size',
        modifiers: [],
      );
      expect(englishOnly.displayName('ar'), 'أحجام البرجر');

      const noArabic = ModifierGroup(
        id: 1,
        nameEn: 'Burger sizes',
        displayNameEn: 'Size',
        modifiers: [],
      );
      expect(noArabic.displayName('ar'), 'Size');
    });
  });
}
