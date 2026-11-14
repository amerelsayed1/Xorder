import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/security/pin_hash.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';

/// The lockout this file exists to prevent:
///
/// every keypad in the till submits the moment [PinRules.length] digits are
/// in — there is no confirm key. The staff pane used to accept "four or more",
/// so a manager could set a six-digit PIN and hand it to somebody who could
/// then never sign in: the keypad refused the fifth digit and sent the first
/// four. One constant now decides both ends, and this asserts they agree.
void main() {
  group('PinRules', () {
    test('accepts only a PIN a keypad could actually enter', () {
      expect(PinRules.isWellFormed('1234'), isTrue);
      expect(PinRules.isWellFormed('123'), isFalse, reason: 'too short');
      expect(
        PinRules.isWellFormed('12345'),
        isFalse,
        reason: 'the keypad would submit before this digit was typed',
      );
      expect(PinRules.isWellFormed(''), isFalse);
      expect(PinRules.isWellFormed('12a4'), isFalse, reason: 'digits only');
      expect(PinRules.isWellFormed('1 34'), isFalse);
      expect(PinRules.isWellFormed('١٢٣٤'), isFalse, reason: 'ASCII digits');
    });

    test('the wizard enforces the same length the keypads do', () {
      expect(SetupDraft.pinLength, PinRules.length);
      expect(const SetupDraft(ownerPin: '1234').hasUsablePin, isTrue);
      expect(const SetupDraft(ownerPin: '12345').hasUsablePin, isFalse);
    });
  });
}
