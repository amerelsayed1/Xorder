import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/supplier.dart';

/// Who the restaurant buys from, and what it owes them.
void main() {
  group('validation is short on purpose', () {
    test('a name is all it takes', () {
      // A restaurant recording a delivery at seven in the morning needs to
      // write down who it came from, not fill in a form.
      const supplier = Supplier(id: 0, nameEn: 'Cairo Poultry');
      expect(supplier.isValid, isTrue);
    });

    test('a nameless supplier is refused, naming the field', () {
      const supplier = Supplier(id: 0, nameEn: '  ');
      expect(supplier.problems.single.field, SupplierField.name);
    });

    test('a tax number is nine digits when it is given at all', () {
      expect(
        const Supplier(id: 0, nameEn: 'X', taxNumber: '123456789').isValid,
        isTrue,
      );
      expect(
        const Supplier(id: 0, nameEn: 'X', taxNumber: '12345').isValid,
        isFalse,
      );
    });

    test('and no tax number at all is fine', () {
      // Most small suppliers have none on the docket.
      expect(const Supplier(id: 0, nameEn: 'X').isValid, isTrue);
      expect(const Supplier(id: 0, nameEn: 'X', taxNumber: '  ').isValid, isTrue);
    });

    test('payment terms cannot run backwards', () {
      expect(
        const Supplier(id: 0, nameEn: 'X', paymentTermDays: -1).isValid,
        isFalse,
      );
    });

    test('zero terms means cash on delivery, which is most of them', () {
      expect(const Supplier(id: 0, nameEn: 'X').isCashOnDelivery, isTrue);
      expect(
        const Supplier(id: 0, nameEn: 'X', paymentTermDays: 30)
            .isCashOnDelivery,
        isFalse,
      );
    });
  });

  group('what a supplier is owed', () {
    SupplierBalance balance({
      int invoiced = 100000,
      int paid = 0,
      int overdue = 0,
    }) => SupplierBalance(
      supplierId: 1,
      invoiced: Money(invoiced),
      paid: Money(paid),
      overdue: Money(overdue),
    );

    test('is invoiced less paid', () {
      expect(balance(invoiced: 100000, paid: 30000).outstanding.minor, 70000);
    });

    test('a fully paid supplier is settled', () {
      expect(balance(invoiced: 100000, paid: 100000).isSettled, isTrue);
    });

    test('overdue is a share of it, not a separate debt', () {
      // A restaurant does not ask "what do I owe", it asks "what do I owe
      // now" — so the two travel together rather than one screen showing each.
      final b = balance(invoiced: 100000, paid: 20000, overdue: 50000);
      expect(b.outstanding.minor, 80000);
      expect(b.overdue.minor, 50000);
    });

    test('paying more than invoiced reads as credit, not as a mistake', () {
      // A deposit, or a credit note nobody has used. It renders as a negative
      // balance and a bookkeeper will assume it is an error unless the screen
      // says otherwise.
      final b = balance(invoiced: 50000, paid: 80000);
      expect(b.isInCredit, isTrue);
      expect(b.isSettled, isTrue);
      expect(b.outstanding.minor, -30000);
    });

    test('nothing invoiced is settled and not in credit', () {
      final b = balance(invoiced: 0);
      expect(b.isSettled, isTrue);
      expect(b.isInCredit, isFalse);
    });
  });

  test('the Arabic name wins where there is one', () {
    const supplier = Supplier(
      id: 1,
      nameEn: 'Nile Dairy',
      nameAr: 'ألبان النيل',
    );
    expect(supplier.displayName('ar'), 'ألبان النيل');
    expect(supplier.displayName('en'), 'Nile Dairy');
  });

  test('and falls back rather than blanking', () {
    const supplier = Supplier(id: 1, nameEn: 'Nile Dairy');
    expect(supplier.displayName('ar'), 'Nile Dairy');
  });

  test('copyWith keeps the id — a supplier is not copied onto another', () {
    const supplier = Supplier(id: 7, nameEn: 'One');
    expect(supplier.copyWith(nameEn: 'Two').id, 7);
  });
}
