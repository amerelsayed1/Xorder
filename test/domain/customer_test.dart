import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/customer.dart';

/// Finding a regular at the counter.
///
/// The load-bearing claim is that the till normalises a phone number exactly
/// as the platform does. A directory splits silently — one customer becomes
/// two, and nobody finds out until somebody asks how often they order — so
/// the rule is pinned rather than trusted.
void main() {
  PosCustomer amer({String phone = '01016943505', String name = 'Amer'}) =>
      PosCustomer(id: 1, name: name, phone: phone);

  group('one number, one person', () {
    test('Arabic-Indic digits fold to the same number', () {
      expect(PosCustomer.normalisePhone('٠١٠١٦٩٤٣٥٠٥'), '01016943505');
    });

    test('Persian digits do too — a Farsi keyboard produces these', () {
      expect(PosCustomer.normalisePhone('۰۱۰۱۶۹۴۳۵۰۵'), '01016943505');
    });

    test('spaces, dashes and brackets are not part of a number', () {
      expect(PosCustomer.normalisePhone('(010) 1694-3505'), '01016943505');
    });

    test('a leading plus is kept, one in the middle is not', () {
      expect(PosCustomer.normalisePhone('+201016943505'), '+201016943505');
      expect(PosCustomer.normalisePhone('010+1694'), '0101694');
    });
  });

  group('searching', () {
    test('the tail of a number finds them', () {
      // What actually happens at a counter: somebody reads out the last four.
      expect(amer().matches('3505'), isTrue);
    });

    test('so does a name fragment, in any case', () {
      expect(amer(name: 'Amer El Sayed').matches('el say'), isTrue);
      expect(amer(name: 'Amer El Sayed').matches('AMER'), isTrue);
    });

    test('a number typed in Arabic digits still finds them', () {
      expect(amer().matches('٣٥٠٥'), isTrue);
    });

    test('an empty query matches everyone, so the list starts full', () {
      expect(amer().matches('   '), isTrue);
    });

    test('somebody else is not a match', () {
      expect(amer().matches('9999'), isFalse);
      expect(amer().matches('Mohamed'), isFalse);
    });
  });

  group('delivery', () {
    test('needs somewhere to go', () {
      expect(amer().canTakeDelivery, isFalse);
      expect(
        const PosCustomer(id: 1, name: 'A', phone: '1', address: '  ')
            .canTakeDelivery,
        isFalse,
        reason: 'whitespace is not an address',
      );
      expect(
        const PosCustomer(id: 1, name: 'A', phone: '1', address: '12 Road 9')
            .canTakeDelivery,
        isTrue,
      );
    });
  });
}
