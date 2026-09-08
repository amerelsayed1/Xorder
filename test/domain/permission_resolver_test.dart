import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/services/permission_resolver.dart';

/// Working out what one person may actually do (§106).
///
/// Every rule here is one where the convenient answer and the safe answer
/// differ, and the safe one has to win: a disabled account keeps nothing, a
/// DENY cannot be outvoted, and a second role cannot raise a ceiling.
void main() {
  PosRole role(
    String code,
    Set<String> capabilities, {
    int id = 1,
  }) => PosRole(
    id: id,
    code: code,
    nameEn: code,
    capabilities: capabilities,
  );

  final cashier = role('cashier', {
    PosCapability.operate,
    PosCapability.receiptReprint,
  }, id: 1);
  final supervisor = role('supervisor', {
    PosCapability.operate,
    PosCapability.orderVoid,
    PosCapability.discountApply,
  }, id: 2);

  group('the two absolute steps', () {
    test('a disabled person resolves to nothing at all', () {
      // Not to a smaller set. An account that kept its low-risk permissions
      // would be a disabled account that can still sell.
      final effective = PermissionResolver.resolve(
        isActive: false,
        roles: [supervisor],
      );
      expect(effective.capabilities, isEmpty);
    });

    test('a terminal that bars somebody resolves to nothing at all', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [supervisor],
        terminalPermits: false,
      );
      expect(effective.capabilities, isEmpty);
    });

    test('a person with no roles holds nothing, which is not an error', () {
      final effective = PermissionResolver.resolve(isActive: true, roles: []);
      expect(effective.capabilities, isEmpty);
    });
  });

  group('roles', () {
    test('two roles union', () {
      // The ordinary reason for holding two: each covers half the job.
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [cashier, supervisor],
      );
      expect(
        effective.capabilities,
        containsAll(<String>[
          PosCapability.receiptReprint,
          PosCapability.orderVoid,
        ]),
      );
    });

    test('an old capability name resolves to its current one', () {
      // Rows written by an older build are still on disk.
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [role('legacy', {'pos.void'})],
      );
      expect(effective.holds(PosCapability.orderVoid), isTrue);
    });
  });

  group('overrides', () {
    PermissionOverride allow(String capability) =>
        PermissionOverride(capability: capability, effect: OverrideEffect.allow);
    PermissionOverride deny(String capability) =>
        PermissionOverride(capability: capability, effect: OverrideEffect.deny);

    test('an ALLOW adds what no role granted', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [cashier],
        overrides: [allow(PosCapability.orderRefund)],
      );
      expect(effective.holds(PosCapability.orderRefund), isTrue);
    });

    test('a DENY takes away what a role granted', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [supervisor],
        overrides: [deny(PosCapability.orderVoid)],
      );
      expect(effective.holds(PosCapability.orderVoid), isFalse);
    });

    test('DENY wins over ALLOW, whichever order they arrive in', () {
      // "This person, despite everything" is what an override is for, so the
      // safe direction has to be the one that wins.
      for (final pair in [
        [allow(PosCapability.orderVoid), deny(PosCapability.orderVoid)],
        [deny(PosCapability.orderVoid), allow(PosCapability.orderVoid)],
      ]) {
        final effective = PermissionResolver.resolve(
          isActive: true,
          roles: [cashier],
          overrides: pair,
        );
        expect(effective.holds(PosCapability.orderVoid), isFalse);
      }
    });

    test('DENY wins over a second role that grants it', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [cashier, supervisor],
        overrides: [deny(PosCapability.orderVoid)],
      );
      expect(effective.holds(PosCapability.orderVoid), isFalse);
    });

    test('what a DENY removed is remembered, not merely absent', () {
      // "Denied for this person" and "nobody ever ticked it" are different
      // facts, and a manager reviewing access needs to tell them apart.
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [supervisor],
        overrides: [deny(PosCapability.orderVoid)],
      );
      expect(effective.deniedByOverride, {PosCapability.orderVoid});
    });

    test('a DENY on something no role granted is not reported as removed', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [cashier],
        overrides: [deny(PosCapability.backupManage)],
      );
      expect(effective.deniedByOverride, isEmpty);
    });

    test('an unknown effect from a newer build is not guessed at', () {
      // Reading it as ALLOW grants a permission somebody wrote a row to
      // control; reading it as DENY silently demotes them.
      expect(OverrideEffect.fromWire('MAYBE'), isNull);
      expect(OverrideEffect.fromWire('DENY'), OverrideEffect.deny);
    });
  });

  group('limits', () {
    test('a role ceiling comes through', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [cashier],
        roleLimits: {LimitKey.discount: const PermissionLimit(maxBp: 1000)},
      );
      expect(effective.limitFor(LimitKey.discount).maxBp, 1000);
    });

    test('a personal ceiling tightens the role, it does not replace it', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [supervisor],
        roleLimits: {LimitKey.discount: const PermissionLimit(maxBp: 2000)},
        staffLimits: {LimitKey.discount: const PermissionLimit(maxBp: 500)},
      );
      expect(effective.limitFor(LimitKey.discount).maxBp, 500);
    });

    test('a personal ceiling cannot raise a role ceiling', () {
      // A per-person limit that could raise one would be authority granted
      // without a permission — the thing an audit trail could not explain.
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [supervisor],
        roleLimits: {LimitKey.discount: const PermissionLimit(maxBp: 2000)},
        staffLimits: {LimitKey.discount: const PermissionLimit(maxBp: 9000)},
      );
      expect(effective.limitFor(LimitKey.discount).maxBp, 2000);
    });

    test('tightening is per field, not per limit', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [supervisor],
        roleLimits: {
          LimitKey.discount: const PermissionLimit(maxBp: 2000),
        },
        staffLimits: {
          LimitKey.discount: const PermissionLimit(maxMinor: 5000),
        },
      );
      final limit = effective.limitFor(LimitKey.discount);
      expect(limit.maxBp, 2000);
      expect(limit.maxMinor, 5000);
    });

    test('no ceiling anywhere is unlimited', () {
      final effective = PermissionResolver.resolve(
        isActive: true,
        roles: [supervisor],
      );
      expect(effective.limitFor(LimitKey.discount).isUnlimited, isTrue);
    });

    test('the tighter of two roles wins', () {
      // Otherwise adding a role could only ever increase what a person may do,
      // which makes a limit something you escape by collecting roles.
      final tightest = PermissionResolver.tightest([
        {LimitKey.discount: const PermissionLimit(maxBp: 2000)},
        {LimitKey.discount: const PermissionLimit(maxBp: 1000)},
      ]);
      expect(tightest[LimitKey.discount]!.maxBp, 1000);
    });
  });

  group('risk levels', () {
    test('every capability has been classified by hand', () {
      // Not merely "riskOf returns something" — it always does. This asserts
      // somebody actually decided, because an unclassified capability silently
      // inherits the default and looks identical to a deliberate `high`.
      final unclassified = PosCapability.all
          .where((c) => !PosCapability.isClassified(c))
          .toList();
      expect(unclassified, isEmpty);
    });

    test('an unclassified capability is treated as dangerous', () {
      // Fails in the direction that asks a question, not the one that grants
      // access.
      expect(PosCapability.riskOf('some.new.key'), PermissionRisk.high);
    });

    test('access control is critical', () {
      for (final capability in [
        PosCapability.staffManage,
        PosCapability.terminalManage,
        PosCapability.settingsManage,
        PosCapability.backupManage,
      ]) {
        expect(
          PosCapability.riskOf(capability),
          PermissionRisk.critical,
          reason: capability,
        );
      }
    });

    test('a critical capability is never lendable, however it is listed', () {
      // Two statements of the same rule, on purpose: an overridable critical
      // permission is a manager PIN that restores a database.
      expect(PermissionRisk.critical.mayBeLent, isFalse);
      for (final capability in PosCapability.all) {
        if (PosCapability.riskOf(capability) == PermissionRisk.critical) {
          expect(PosCapability.mayBeLent(capability), isFalse, reason: capability);
        }
      }
    });

    test('a critical control is hidden, not greyed out', () {
      expect(PermissionRisk.critical.isHidden, isTrue);
      expect(PermissionRisk.high.isHidden, isFalse);
    });

    test('everything on the overridable list is lendable', () {
      // If this fails, somebody has raised a capability's risk to critical
      // without taking it off the list — and the two now disagree.
      for (final capability in PosCapability.overridable) {
        expect(PosCapability.mayBeLent(capability), isTrue, reason: capability);
      }
    });
  });
}
