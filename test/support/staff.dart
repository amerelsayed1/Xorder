import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';

/// A member of staff holding exactly [capabilities] through a role.
PosStaff staffWith(Set<String> capabilities, {int id = 9}) => PosStaff(
  id: id,
  name: 'Test',
  username: 'test$id',
  role: PosRole(
    id: id,
    code: 'test-$id',
    nameEn: 'Test',
    capabilities: capabilities,
  ),
);
