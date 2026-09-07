import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/authorization.dart';

/// The decision every gated action in the app runs through.
///
/// Pure, so these are the cheapest tests in the suite and the ones most worth
/// having: the widgets and the repositories both ask this function, and a bug
/// here is a bug in the till *and* in the database layer that was supposed to
/// be the backstop.
void main() {
  PosStaff onRole(String code, {bool isActive = true, Set<String> extra = const {}}) =>
      PosStaff(
        id: 1,
        name: 'Rana',
        isActive: isActive,
        capabilities: extra,
        role: PosRole(
          id: 1,
          code: code,
          nameEn: code,
          capabilities: SystemRoles.seeded[code]!.capabilities,
        ),
      );

  group('check', () {
    test('nobody signed in is a denial, not a default', () {
      // An unattended till must not be a till with every permission.
      expect(Authorization.check(null, PosCapability.operate), isA<Denied>());
      // Even for something a supervisor could otherwise lend — there is nobody
      // present to lend it to.
      expect(Authorization.check(null, PosCapability.discountApply),
          isA<NeedsOverride>());
    });

    test('a disabled account holds nothing, whatever its role says', () {
      final former = onRole(SystemRoles.ownerCode, isActive: false);
      expect(former.role!.holds(PosCapability.backupManage), isTrue);
      expect(Authorization.check(former, PosCapability.backupManage), isA<Denied>());
    });

    test('a capability the role carries is simply allowed', () {
      expect(
        Authorization.check(onRole(SystemRoles.cashierCode), PosCapability.operate),
        isA<Allowed>(),
      );
    });

    test('a missing capability a supervisor could lend asks for one', () {
      final decision =
          Authorization.check(onRole(SystemRoles.cashierCode), PosCapability.orderRefund);
      expect((decision as NeedsOverride).capability, PosCapability.orderRefund);
    });

    test('a missing back-office capability is refused outright', () {
      // Nobody supervises a database restore by watching it happen, so offering
      // an override here would be a prompt that can only ever fail.
      expect(
        Authorization.check(onRole(SystemRoles.cashierCode), PosCapability.backupManage),
        isA<Denied>(),
      );
      expect(
        Authorization.check(onRole(SystemRoles.cashierCode), PosCapability.staffManage),
        isA<Denied>(),
      );
    });

    test('legacy capability names resolve to what they became', () {
      const omar = PosStaff(id: 2, name: 'Omar', capabilities: {'pos.reprint'});
      expect(Authorization.check(omar, PosCapability.receiptReprint), isA<Allowed>());
      expect(Authorization.check(omar, 'pos.reprint'), isA<Allowed>());
    });
  });

  group('approve', () {
    test('a supervisor who holds it lends it, and is named', () {
      final sara = onRole(SystemRoles.supervisorCode);
      final decision =
          Authorization.approve(approver: sara, capability: PosCapability.orderRefund);

      expect((decision as Allowed).approvedBy, sara);
      expect(decision.wasOverridden, isTrue);
    });

    test('an approver who does not hold it is refused, not treated as absent', () {
      // Otherwise a supervisor discovers their PIN "worked" for something they
      // were never granted.
      final decision = Authorization.approve(
        approver: onRole(SystemRoles.cashierCode),
        capability: PosCapability.orderRefund,
      );
      expect(decision, isA<NeedsOverride>());
    });

    test('nothing can be lent that is not lendable', () {
      final decision = Authorization.approve(
        approver: onRole(SystemRoles.ownerCode),
        capability: PosCapability.backupManage,
      );
      expect(decision, isA<Denied>());
    });

    test('a disabled supervisor cannot approve', () {
      final decision = Authorization.approve(
        approver: onRole(SystemRoles.supervisorCode, isActive: false),
        capability: PosCapability.orderRefund,
      );
      expect(decision, isA<NeedsOverride>());
    });
  });

  group('validateRole', () {
    PosRole role(String code, Set<String> capabilities) =>
        PosRole(id: 1, code: code, nameEn: code, capabilities: capabilities);

    test('the owner role keeps everything', () {
      expect(Authorization.validateRole(role(SystemRoles.ownerCode, SystemRoles.owner)),
          isNull);
      expect(
        Authorization.validateRole(
          role(SystemRoles.ownerCode, {...SystemRoles.owner}..remove(PosCapability.operate)),
        ),
        isA<OwnerMustKeepEverything>(),
      );
    });

    test('a cashier role holds nothing from the back office', () {
      expect(
        Authorization.validateRole(role(SystemRoles.cashierCode, SystemRoles.cashier)),
        isNull,
      );

      final refusal = Authorization.validateRole(
        role(SystemRoles.cashierCode, {
          ...SystemRoles.cashier,
          PosCapability.catalogManage,
          PosCapability.backupManage,
        }),
      );
      expect(
        (refusal as CashiersAreNotAdministrators).capabilities,
        {PosCapability.catalogManage, PosCapability.backupManage},
      );
    });

    test('a role a restaurant invented is its own business', () {
      // Only the two seeded roles the model depends on are constrained. A
      // restaurant that wants a "Head Barista" who can edit the menu is not
      // making a mistake the app should refuse.
      expect(
        Authorization.validateRole(
          role('head-barista', {PosCapability.operate, PosCapability.catalogManage}),
        ),
        isNull,
      );
    });
  });
}
