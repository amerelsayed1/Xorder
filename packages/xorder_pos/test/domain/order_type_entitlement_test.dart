import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/domain/services/order_type_entitlement.dart';

import 'package:xorder_pos_test_support/staff.dart';

/// XORD-002 — which order types a licence covers, and who may choose.
void main() {
  group('the licence', () {
    test('says nothing about order types: no restriction', () {
      expect(OrderTypeEntitlement.fromFeatures(const {}), isNull);
      expect(OrderTypeEntitlement.fromFeatures({'pos'}), isNull);
    });

    test('names some: exactly those, and drive-thru follows pos', () {
      expect(
        OrderTypeEntitlement.fromFeatures({'pos', 'dine_in', 'delivery'}),
        {OrderType.dineIn, OrderType.delivery, OrderType.driveThru},
      );
      expect(
        OrderTypeEntitlement.fromFeatures({'dine_in'}),
        {OrderType.dineIn},
        reason: 'without pos there is no drive-thru lane',
      );
    });

    test('pickup and takeaway are one thing', () {
      expect(
        OrderTypeEntitlement.fromFeatures({'pickup'}),
        {OrderType.takeaway},
      );
      expect(
        OrderTypeEntitlement.fromFeatures({'takeaway'}),
        {OrderType.takeaway},
      );
    });
  });

  group('the capability', () {
    test('is the platform\'s own spelling', () {
      expect(PosCapability.orderTypesManage, 'pos.settings.order_types.manage');
    });

    test('is catalogued, classified, grouped, and never a cashier\'s', () {
      expect(PosCapability.all, contains(PosCapability.orderTypesManage));
      expect(PosCapability.isClassified(PosCapability.orderTypesManage), isTrue);
      expect(PosCapability.backOffice, contains(PosCapability.orderTypesManage));
      expect(
        CapabilityGroup.backOffice.capabilities,
        contains(PosCapability.orderTypesManage),
      );
    });

    test('the owner and the manager hold it; the supervisor and cashier do not', () {
      expect(SystemRoles.owner, contains(PosCapability.orderTypesManage));
      expect(SystemRoles.manager, contains(PosCapability.orderTypesManage));
      expect(SystemRoles.supervisor, isNot(contains(PosCapability.orderTypesManage)));
      expect(SystemRoles.cashier, isNot(contains(PosCapability.orderTypesManage)));
    });

    test('a supervisor\'s PIN cannot lend it', () {
      expect(PosCapability.mayBeLent(PosCapability.orderTypesManage), isFalse);
      expect(
        Authorization.check(staffWith({PosCapability.operate}), PosCapability.orderTypesManage),
        isNot(isA<Allowed>()),
      );
    });

    test('a platform role carrying it is understood unchanged', () {
      expect(
        PosCapability.canonicalAll(['pos.settings.order_types.manage']),
        contains(PosCapability.orderTypesManage),
      );
    });
  });
}
