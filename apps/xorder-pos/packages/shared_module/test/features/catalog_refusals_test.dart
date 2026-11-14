import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:shared_module/features/admin_mode/admin_messages.dart';

/// Why an item or a category was refused, in words.
///
/// These used to arrive as English inside `CatalogInvalid`, so an Arabic back
/// office showed "An item needs a name." as it was. Now they are codes, and
/// the screen says them in its own language.
void main() {
  const en = EnStrings();
  const ar = ArStrings();

  test('every reason says something, in both languages', () {
    for (final problem in CatalogProblem.values) {
      final english = AdminText.refusal(en, CatalogRefused(problem));
      final arabic = AdminText.refusal(ar, CatalogRefused(problem));
      expect(english, isNotEmpty, reason: '$problem');
      expect(arabic, isNotEmpty, reason: '$problem');
      expect(arabic, isNot(english), reason: '$problem');
    }
  });

  test('the reasons are told apart, not one sentence for all', () {
    final english = {
      for (final problem in CatalogProblem.values)
        AdminText.catalogProblem(en, problem),
    };
    expect(english, hasLength(CatalogProblem.values.length));
  });

  test('the offer price says which price is wrong', () {
    expect(
      AdminText.refusal(en, const CatalogRefused(CatalogProblem.offerAbovePrice)),
      contains('offer price'),
    );
  });
}
