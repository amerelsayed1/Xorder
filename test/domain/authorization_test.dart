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

  group('limits (Wave C)', () {
    PosStaff capped({
      String code = SystemRoles.supervisorCode,
      PermissionLimit? discount,
    }) => PosStaff(
      id: 1,
      name: 'Rana',
      role: PosRole(
        id: 1,
        code: code,
        nameEn: code,
        capabilities: SystemRoles.seeded[code]!.capabilities,
      ),
      limits: {LimitKey.discount: ?discount},
    );

    test('an allowed decision carries the ceiling that came with it', () {
      // So a caller can say "allowed, up to 10%" from one question. A limit
      // that had to be fetched separately is one somebody will not fetch.
      final decision = Authorization.check(
        capped(discount: const PermissionLimit(maxBp: 1000)),
        PosCapability.discountApply,
      );
      expect((decision as Allowed).limit!.maxBp, 1000);
    });

    test('within the ceiling is allowed', () {
      final decision = Authorization.checkWithin(
        capped(discount: const PermissionLimit(maxBp: 1000)),
        PosCapability.discountApply,
        baseMinor: 10000,
        amountMinor: 1000,
      );
      expect(decision, isA<Allowed>());
    });

    test('exactly at the ceiling is allowed', () {
      // Cross-multiplied rather than divided, so there is no rounding step
      // sitting on the boundary.
      final decision = Authorization.checkWithin(
        capped(discount: const PermissionLimit(maxBp: 1000)),
        PosCapability.discountApply,
        baseMinor: 3333,
        amountMinor: 333,
      );
      expect(decision, isA<Allowed>());
    });

    test('one piastre over it is not', () {
      final decision = Authorization.checkWithin(
        capped(discount: const PermissionLimit(maxBp: 1000)),
        PosCapability.discountApply,
        baseMinor: 3333,
        amountMinor: 334,
      );
      expect(decision, isA<DeniedByLimit>());
    });

    test('over the ceiling is a limit refusal, not a flat denial', () {
      // The distinction that turns a 30% request by a 10% cashier into a
      // manager walking over, rather than "you may not discount" — which is
      // both untrue and the wrong instruction.
      final decision = Authorization.checkWithin(
        capped(discount: const PermissionLimit(maxBp: 1000)),
        PosCapability.discountApply,
        baseMinor: 10000,
        amountMinor: 3000,
      );

      expect(decision, isA<DeniedByLimit>());
      final refused = decision as DeniedByLimit;
      expect(refused.limit.maxBp, 1000);
      expect(refused.requestedBp, 3000, reason: 'and says what was asked for');
      expect(refused.mayBeLent, isTrue, reason: 'so a supervisor can resolve it');
    });

    test('a cash ceiling binds a fixed-value request', () {
      final decision = Authorization.checkWithin(
        capped(discount: const PermissionLimit(maxMinor: 2000)),
        PosCapability.discountApply,
        baseMinor: 100000,
        amountMinor: 2500,
      );
      expect(decision, isA<DeniedByLimit>());
    });

    test('a percentage ceiling binds a fixed-value request too', () {
      // A cashier capped at 10% reaching for 50 off a 100 order is asking for
      // 50%. Checking only the cash ceiling would make the percentage one
      // avoidable by picking the other kind of discount.
      final decision = Authorization.checkWithin(
        capped(discount: const PermissionLimit(maxBp: 1000)),
        PosCapability.discountApply,
        baseMinor: 10000,
        amountMinor: 5000,
      );
      expect(decision, isA<DeniedByLimit>());
    });

    test('no ceiling permits anything', () {
      final decision = Authorization.checkWithin(
        capped(),
        PosCapability.discountApply,
        baseMinor: 10000,
        amountMinor: 10000,
      );
      expect(decision, isA<Allowed>());
    });

    test('somebody who lacks the permission is still just denied', () {
      // The size of the request is not the reason, and saying it was would
      // send a cashier to find a supervisor who cannot help either.
      final decision = Authorization.checkWithin(
        capped(code: SystemRoles.cashierCode),
        PosCapability.discountApply,
        baseMinor: 10000,
        amountMinor: 100,
      );
      expect(decision, isA<NeedsOverride>());
    });

    test("an approval is bound by the approver's ceiling, not the requester's",
        () {
      // The act is performed on the approver's authority. A supervisor capped
      // at 20% cannot approve 30% by standing next to somebody capped at 10%.
      final decision = Authorization.approve(
        approver: capped(discount: const PermissionLimit(maxBp: 2000)),
        capability: PosCapability.discountApply,
      );
      expect((decision as Allowed).limit!.maxBp, 2000);
    });
  });

  group('risk (Wave C)', () {
    test('a critical capability is denied outright, never offered', () {
      // Not NeedsOverride. There is no supervisor PIN that restores a
      // database, and offering one would be a lie with a prompt attached.
      final cashier = onRole(SystemRoles.cashierCode);
      expect(
        Authorization.check(cashier, PosCapability.backupManage),
        isA<Denied>(),
      );
      expect(
        Authorization.check(cashier, PosCapability.staffManage),
        isA<Denied>(),
      );
    });

    test('a medium capability the person lacks is offered for approval', () {
      final cashier = onRole(SystemRoles.cashierCode);
      expect(
        Authorization.check(cashier, PosCapability.discountApply),
        isA<NeedsOverride>(),
      );
    });

    test('approving a critical capability is refused, not attempted', () {
      final owner = onRole(SystemRoles.ownerCode);
      expect(
        Authorization.approve(
          approver: owner,
          capability: PosCapability.backupManage,
        ),
        isA<Denied>(),
      );
    });
  });

  group('granting (§48)', () {
    PosRole role(Set<String> capabilities, {String code = 'invented'}) =>
        PosRole(id: 5, code: code, nameEn: 'Invented', capabilities: capabilities);

    test('a manager cannot grant what they do not hold', () {
      // The rule that stops the permission model being decorative. Without it
      // anybody with staff.manage writes themselves a role holding
      // backup.manage, and the whole catalogue is one checkbox deep.
      final refusal = Authorization.validateRole(
        role({PosCapability.operate, PosCapability.backupManage}),
        editedBy: onRole(SystemRoles.managerCode),
      );

      expect(refusal, isA<CannotGrantWhatYouLack>());
      expect(
        (refusal! as CannotGrantWhatYouLack).capabilities,
        {PosCapability.backupManage},
        reason: 'and names which one, so a mistake is fixable',
      );
    });

    test('they can grant everything they do hold', () {
      expect(
        Authorization.validateRole(
          role(SystemRoles.supervisor),
          editedBy: onRole(SystemRoles.managerCode),
        ),
        isNull,
      );
    });

    test('an owner can grant anything', () {
      expect(
        Authorization.validateRole(
          role(SystemRoles.owner),
          editedBy: onRole(SystemRoles.ownerCode),
        ),
        isNull,
      );
    });

    test('taking a permission away needs no permission', () {
      // Removing authority you do not hold is safe, and refusing it would mean
      // a manager could not revoke anything an owner had granted.
      final refusal = Authorization.validateRole(
        role({PosCapability.operate}),
        editedBy: onRole(SystemRoles.cashierCode),
      );
      expect(refusal, isNull);
    });

    test('an old capability name is measured against its current one', () {
      // Otherwise a role stored under a pre-migration spelling would look like
      // an escalation to everybody.
      expect(
        Authorization.validateRole(
          role({'pos.void'}),
          editedBy: onRole(SystemRoles.supervisorCode),
        ),
        isNull,
      );
    });

    test('without an editor the shape rules still apply', () {
      // The CLI seeds roles with no signed-in person. It must still not be
      // able to write a cashier role holding the back office.
      expect(
        Authorization.validateRole(
          role({PosCapability.backupManage}, code: SystemRoles.cashierCode),
        ),
        isA<CashiersAreNotAdministrators>(),
      );
    });

    test('escalation is checked before the shape rules', () {
      // Both refusals fit; the one that names the real problem wins.
      final refusal = Authorization.validateRole(
        role({PosCapability.backupManage}, code: SystemRoles.cashierCode),
        editedBy: onRole(SystemRoles.managerCode),
      );
      expect(refusal, isA<CannotGrantWhatYouLack>());
    });
  });

  group('role templates (§49)', () {
    test('every template holds only capabilities that exist', () {
      // A template naming a key nobody defines is a checkbox that can never be
      // unticked, because the editor would not draw it.
      for (final entry in SystemRoles.templates.entries) {
        for (final capability in entry.value.capabilities) {
          expect(
            PosCapability.isKnown(capability),
            isTrue,
            reason: '${entry.key} → $capability',
          );
        }
      }
    });

    test('no template grants the database', () {
      // Templates are narrow on purpose: one granting a bit too much would
      // widen access every time somebody used it.
      for (final entry in SystemRoles.templates.entries) {
        expect(
          entry.value.capabilities,
          isNot(contains(PosCapability.backupManage)),
          reason: entry.key,
        );
      }
    });

    test('the kitchen reads the menu and nothing else', () {
      // A kitchen screen is not a place from which anybody should void a sale.
      expect(SystemRoles.templates['kitchen']!.capabilities, {
        PosCapability.catalogView,
      });
    });

    test('the accountant can see everything and change nothing', () {
      final accountant = SystemRoles.templates['accountant']!.capabilities;
      expect(accountant, contains(PosCapability.orderViewAll));
      expect(accountant, isNot(contains(PosCapability.orderVoid)));
      expect(accountant, isNot(contains(PosCapability.orderRefund)));
      expect(accountant, isNot(contains(PosCapability.catalogManage)));
    });

    test('a branch manager runs the branch, not the people', () {
      final branch = SystemRoles.templates['restaurant_manager']!.capabilities;
      expect(branch, contains(PosCapability.dayForceClose));
      expect(branch, isNot(contains(PosCapability.staffManage)));
    });

    test('no template collides with a seeded role code', () {
      // A template that shared a code with a system role would create a second
      // "cashier" the seeder then fights over.
      expect(
        SystemRoles.templates.keys.toSet().intersection(
          SystemRoles.seeded.keys.toSet(),
        ),
        isEmpty,
      );
    });
  });
}
