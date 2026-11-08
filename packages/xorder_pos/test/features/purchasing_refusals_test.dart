import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';

/// The two purchasing refusals the back office can now meet, in words.
///
/// Both used to be impossible to reach — the Cancel button hid one and a
/// debug assert "guarded" the other — so neither had a sentence. Now the
/// repository says them, and a refusal with no sentence is a manager reading a
/// class name.
void main() {
  const en = EnStrings();
  const ar = ArStrings();

  const held = StockHeldInAnotherUnit(
    item: 'Chicken',
    held: Quantity(10000, unit: QuantityUnit.box),
    asked: QuantityUnit.kilogram,
  );

  test('stock held in another unit names the item, how much, and both units',
      () {
    final text = AdminText.refusal(en, held);
    expect(text, contains('Chicken'));
    expect(text, contains('10'));
    // Case-blind: a unit's label is a title on a list and a word in a sentence.
    expect(
      text.toLowerCase(),
      contains(AdminText.unit(en, QuantityUnit.box).toLowerCase()),
    );
    expect(
      text.toLowerCase(),
      contains(AdminText.unit(en, QuantityUnit.kilogram).toLowerCase()),
    );
  });

  test('and in Arabic, translated, with the digits left Latin', () {
    final text = AdminText.refusal(ar, held);
    expect(text, isNot(AdminText.refusal(en, held)));
    expect(text, contains('Chicken'));
    expect(text, contains('10'));
    expect(RegExp('[٠-٩]').hasMatch(text), isFalse);
  });

  test('every reason an order cannot move says something, in both languages',
      () {
    for (final reason in const <PurchaseRefusal>[
      OrderNotEditable(PurchaseStatus.sent),
      OrderNotEditable(PurchaseStatus.partiallyReceived),
      OrderNotEditable(PurchaseStatus.received),
      OrderNotEditable(PurchaseStatus.cancelled),
      OrderHasNoLines(),
      LineQuantityNotPositive(),
      OrderAlreadyClosed(PurchaseStatus.partiallyReceived),
      OrderAlreadyClosed(PurchaseStatus.received),
      OrderAlreadyClosed(PurchaseStatus.cancelled),
      StatusFollowsTheGoods(PurchaseStatus.received),
    ]) {
      final english = AdminText.refusal(en, PurchaseRefused(reason));
      final arabic = AdminText.refusal(ar, PurchaseRefused(reason));
      expect(english, isNotEmpty, reason: '$reason');
      expect(arabic, isNot(english), reason: '$reason');
    }
  });

  test('a cancel refused over goods that arrived says why, not only no', () {
    final text = AdminText.refusal(
      en,
      const PurchaseRefused(OrderAlreadyClosed(PurchaseStatus.partiallyReceived)),
    );
    expect(text, contains('arrived'));
  });
}
