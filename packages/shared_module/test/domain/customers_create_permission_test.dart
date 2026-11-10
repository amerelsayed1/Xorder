import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/domain/models/customer.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/services/authorization.dart';

/// XORD-001 — `customers.create`, and the two rules around it.
///
/// Choosing who an order is for needs `pos.operate`. Adding somebody new needs
/// `customers.create`. The key is the platform's own string, so a cloud till's
/// roles carry it through the bootstrap bundle with no translation.
PosStaff _on(Set<String> capabilities) => PosStaff(
  id: 5,
  name: 'T',
  username: 't',
  role: PosRole(id: 5, code: 'x', nameEn: 'X', capabilities: capabilities),
);

void main() {
  group('the capability', () {
    test('is the platform\'s own spelling', () {
      expect(PosCapability.customersCreate, 'customers.create');
    });

    test('is in the catalogue, classified, and offered in the role editor', () {
      expect(PosCapability.all, contains(PosCapability.customersCreate));
      expect(PosCapability.isClassified(PosCapability.customersCreate), isTrue);
      expect(
        CapabilityGroup.values.any(
          (g) => g.capabilities.contains(PosCapability.customersCreate),
        ),
        isTrue,
      );
    });

    test('is not back-office: a cashier may hold it', () {
      expect(
        PosCapability.backOffice,
        isNot(contains(PosCapability.customersCreate)),
      );
    });

    test('every seeded role keeps adding customers, as the counter could', () {
      for (final role in [
        SystemRoles.owner,
        SystemRoles.manager,
        SystemRoles.supervisor,
        SystemRoles.cashier,
      ]) {
        expect(role, contains(PosCapability.customersCreate));
      }
    });

    test('a platform role carrying it is understood unchanged', () {
      expect(
        PosCapability.canonicalAll(['pos.operate', 'customers.create']),
        containsAll([PosCapability.operate, PosCapability.customersCreate]),
      );
    });
  });

  group('the decision', () {
    test('selling does not imply adding', () {
      final seller = _on({PosCapability.operate});
      expect(Authorization.check(seller, PosCapability.operate), isA<Allowed>());
      expect(
        Authorization.check(seller, PosCapability.customersCreate),
        isNot(isA<Allowed>()),
      );
    });

    test('nobody signed in is denied both', () {
      expect(Authorization.check(null, PosCapability.operate), isNot(isA<Allowed>()));
      expect(
        Authorization.check(null, PosCapability.customersCreate),
        isNot(isA<Allowed>()),
      );
    });

    test('a supervisor cannot lend it: adding is not a once-off approval', () {
      expect(PosCapability.mayBeLent(PosCapability.customersCreate), isFalse);
    });
  });

  group('choosing a customer for the open ticket', () {
    const mona = PosCustomer(id: 1, name: 'Mona', phone: '01012345678');

    test('needs pos.operate, and the ticket is untouched without it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(ticketProvider.notifier).setCustomer(mona), isFalse);
      expect(container.read(ticketProvider).customer, isNull);

      container
          .read(signedInStaffProvider.notifier)
          .signIn(_on({PosCapability.catalogView}));
      expect(container.read(ticketProvider.notifier).setCustomer(mona), isFalse);
      expect(container.read(ticketProvider).customer, isNull);

      container
          .read(signedInStaffProvider.notifier)
          .signIn(_on({PosCapability.operate}));
      expect(container.read(ticketProvider.notifier).setCustomer(mona), isTrue);
      expect(container.read(ticketProvider).customer, mona);

      // Taking them off again is the same act.
      expect(container.read(ticketProvider.notifier).setCustomer(null), isTrue);
      expect(container.read(ticketProvider).customer, isNull);
    });
  });
}
