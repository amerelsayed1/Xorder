import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/combo.dart';
import 'package:shared_module/domain/models/combo_draft.dart';
import 'package:shared_module/domain/models/catalog.dart';

/// The rules a combo is checked against before the database is asked.
///
/// Pure, so each rule is one line here and the repository suite only has to
/// prove the database agrees.
void main() {
  ComboDraft combo({
    String name = 'Meal deal',
    int category = 1,
    int price = 8500,
    List<ComboGroupDraft>? groups,
  }) => ComboDraft(
    categoryId: category,
    nameEn: name,
    price: Money(price),
    groups:
        groups ??
        const [
          ComboGroupDraft(
            nameEn: 'Choose a drink',
            options: [ComboOptionDraft(productId: 10)],
          ),
        ],
  );

  ComboGroupDraft choice({
    String name = 'Choose a drink',
    int min = 1,
    int max = 1,
    List<ComboOptionDraft> options = const [ComboOptionDraft(productId: 10)],
  }) => ComboGroupDraft(
    nameEn: name,
    minSelect: min,
    maxSelect: max,
    options: options,
  );

  test('a complete combo is accepted', () {
    expect(ComboRules.refusal(combo()), isNull);
  });

  test('a free combo is accepted — zero is a price, negative is not', () {
    expect(ComboRules.refusal(combo(price: 0)), isNull);
    expect(
      ComboRules.refusal(combo(price: -1)),
      ComboProblem.priceNegative,
    );
  });

  test('a blank name is refused, whitespace included', () {
    expect(ComboRules.refusal(combo(name: '')), ComboProblem.nameMissing);
    expect(ComboRules.refusal(combo(name: '   ')), ComboProblem.nameMissing);
  });

  test('a combo with no category has nowhere on the grid', () {
    expect(
      ComboRules.refusal(combo(category: 0)),
      ComboProblem.categoryMissing,
    );
  });

  test('a combo with nothing to choose is refused', () {
    expect(ComboRules.refusal(combo(groups: [])), ComboProblem.noGroups);
  });

  test('a group needs a name and an item', () {
    expect(
      ComboRules.refusal(combo(groups: [choice(name: ' ')])),
      ComboProblem.groupNameMissing,
    );
    expect(
      ComboRules.refusal(combo(groups: [choice(options: const [])])),
      ComboProblem.groupEmpty,
    );
  });

  group('how many may be chosen', () {
    test('min above max is refused', () {
      expect(
        ComboRules.refusal(combo(groups: [choice(min: 3, max: 2)])),
        ComboProblem.selectionRange,
      );
    });

    test('max below one is refused', () {
      expect(
        ComboRules.refusal(combo(groups: [choice(min: 0, max: 0)])),
        ComboProblem.selectionRange,
      );
    });

    test('min below zero is refused', () {
      expect(
        ComboRules.refusal(combo(groups: [choice(min: -1)])),
        ComboProblem.selectionRange,
      );
    });

    test('an optional group is accepted: min 0', () {
      expect(
        ComboRules.refusal(combo(groups: [choice(min: 0)])),
        isNull,
      );
    });

    test('demanding more than is offered is a meal nobody can finish', () {
      expect(
        ComboRules.refusal(combo(groups: [choice(min: 2, max: 2)])),
        ComboProblem.minAboveOptions,
      );
    });
  });

  group('the items in a group', () {
    test('the same product twice is refused', () {
      expect(
        ComboRules.refusal(
          combo(
            groups: [
              choice(
                options: const [
                  ComboOptionDraft(productId: 10),
                  ComboOptionDraft(productId: 10),
                ],
              ),
            ],
          ),
        ),
        ComboProblem.duplicateOption,
      );
    });

    test('the same product in two groups is fine', () {
      expect(
        ComboRules.refusal(combo(groups: [choice(), choice(name: 'Side')])),
        isNull,
      );
    });

    test('an upgrade is zero or more', () {
      expect(
        ComboRules.refusal(
          combo(
            groups: [
              choice(
                options: [
                  ComboOptionDraft(productId: 10, priceDelta: Money(500)),
                ],
              ),
            ],
          ),
        ),
        isNull,
      );
      expect(
        ComboRules.refusal(
          combo(
            groups: [
              choice(
                options: [
                  ComboOptionDraft(productId: 10, priceDelta: Money(-1)),
                ],
              ),
            ],
          ),
        ),
        ComboProblem.deltaNegative,
      );
    });
  });

  test('editing an existing combo starts from what it holds', () {
    const chips = Product(id: 10, categoryId: 1, nameEn: 'Chips', price: Money(2500));
    final existing = Combo(
      id: 7,
      categoryId: 1,
      nameEn: 'Meal deal',
      nameAr: 'وجبة',
      price: const Money(8500),
      sku: 'MD1',
      isAvailable: false,
      groups: [
        ComboGroup(
          id: 70,
          nameEn: 'Side',
          minSelect: 0,
          maxSelect: 2,
          options: [
            ComboOption(id: 700, product: chips, priceDelta: const Money(500)),
          ],
        ),
      ],
    );

    final draft = ComboDraft.of(existing);

    expect(draft.id, 7);
    expect(draft.price.minor, 8500);
    expect(draft.isAvailable, isFalse);
    expect(draft.sku, 'MD1');
    expect(draft.groups.single.id, 70);
    expect(draft.groups.single.minSelect, 0);
    expect(draft.groups.single.options.single.productId, 10);
    expect(draft.groups.single.options.single.priceDelta.minor, 500);
    expect(ComboRules.refusal(draft), isNull);
  });
}
