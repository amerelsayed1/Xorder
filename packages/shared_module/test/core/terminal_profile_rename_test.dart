import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/terminal_profile.dart';

/// The rename from "restaurant" to "business" (2026-11-07) must not
/// unprovision a till whose profile on disk was written before it.
void main() {
  const saved = {
    'branch_code': 'MAIN',
    'branch_id': 13,
    'branch_name': 'Main',
    'terminal_name': 'Counter 1',
    'terminal_id': '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
    'provisioned': true,
  };

  test('a profile saved with restaurant_id still names its business', () {
    final profile = TerminalProfile.fromJson({...saved, 'restaurant_id': 7});
    expect(profile.businessId, 7);
    expect(profile.isSet, isTrue);
  });

  test('the new key wins, and is what is written back', () {
    final profile = TerminalProfile.fromJson({
      ...saved,
      'business_id': 8,
      'restaurant_id': 7,
    });
    expect(profile.businessId, 8);
    expect(profile.toJson()['business_id'], 8);
    expect(profile.toJson().containsKey('restaurant_id'), isFalse);
  });
}
