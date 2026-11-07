import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/shift.dart';

/// A drawer belongs to whoever opened it.
///
/// The close used to be signable by anybody holding the capability, on the
/// reasoning that a manager cashing up at the end of the night is the normal
/// case. It made the float countable IN by one person and OUT by another, with
/// only a name on an audit row to say so — and a variance with two people to
/// argue about it is a variance nobody owns.
///
/// The identity is what settles it, never the name: two people called Ahmed is
/// a business, not a corner case.
void main() {
  PosShift shift({int? openedById}) => PosShift(
    id: 2,
    openedAt: DateTime(2026, 9, 10, 6, 32),
    openingFloat: Money(100000),
    openedByName: 'Amer',
    openedById: openedById,
  );

  test('the person who opened it is the person who may close it', () {
    expect(shift(openedById: 1).openedBy(1), isTrue);
    expect(shift(openedById: 1).openedBy(2), isFalse);
  });

  test('an unknown owner is not treated as somebody else', () {
    // A shift written before the id was recorded has nobody to compare
    // against. A till that can never be cashed up is worse than one cashed up
    // by the wrong person, so the unknown case stays open rather than locking.
    expect(shift().openedBy(1), isTrue);
    expect(shift().openedBy(99), isTrue);
  });
}
