import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';

void main() {
  group('system roles', () {
    test('owner retains every defined capability', () {
      expect(SystemRoles.owner, containsAll(PosCapability.all));
      expect(SystemRoles.owner.length, PosCapability.all.length);
    });

    test('cashier receives no back-office capability', () {
      expect(
        SystemRoles.cashier.intersection(PosCapability.backOffice),
        isEmpty,
      );
      expect(SystemRoles.cashier, contains(PosCapability.operate));
      expect(SystemRoles.cashier, contains(PosCapability.catalogView));
    });

    test('report.export is the owner\'s alone, never lent, never greyed', () {
      // Owner decision, 14 Sep: seeded to the owner and to nobody else, and
      // offered by no template — who else may take the sales away is decided
      // in Roles, one person at a time.
      for (final MapEntry(:key, :value) in SystemRoles.seeded.entries) {
        expect(
          value.capabilities.contains(PosCapability.reportExport),
          key == SystemRoles.ownerCode,
          reason: key,
        );
      }
      for (final MapEntry(:key, :value) in SystemRoles.templates.entries) {
        expect(
          value.capabilities,
          isNot(contains(PosCapability.reportExport)),
          reason: key,
        );
      }
      // Critical, like a backup: a copy of the data. No supervisor lends it,
      // no cashier role holds it, and the button is not drawn without it.
      expect(PosCapability.mayBeLent(PosCapability.reportExport), isFalse);
      expect(PosCapability.riskOf(PosCapability.reportExport).isHidden, isTrue);
      expect(PosCapability.backOffice, contains(PosCapability.reportExport));
    });

    test('manager can maintain a fully offline catalogue', () {
      expect(SystemRoles.manager, contains(PosCapability.catalogManage));
      expect(SystemRoles.manager, contains(PosCapability.settingsManage));
      expect(SystemRoles.manager, isNot(contains(PosCapability.backupManage)));
    });
  });

  group('staff authorization', () {
    test('combines role permissions with direct grants', () {
      final role = PosRole(
        id: 1,
        code: SystemRoles.cashierCode,
        nameEn: 'Cashier',
        capabilities: SystemRoles.cashier,
      );
      final staff = PosStaff(
        id: 7,
        name: 'Rana',
        role: role,
        capabilities: const {PosCapability.discountApply},
      );

      expect(staff.can(PosCapability.operate), isTrue);
      expect(staff.can(PosCapability.discountApply), isTrue);
      expect(staff.can(PosCapability.catalogManage), isFalse);
    });

    test('understands capability names written by older installations', () {
      const staff = PosStaff(
        id: 8,
        name: 'Omar',
        capabilities: {'pos.shift_open', 'pos.reprint'},
      );

      expect(staff.can(PosCapability.shiftOpen), isTrue);
      expect(staff.can(PosCapability.receiptReprint), isTrue);
    });
  });
}
