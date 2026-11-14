import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:shared_module/core/security/pin_hash.dart';

/// Two rules that used to be enforced only where they were finally USED, which
/// is several screens after the point they are typed.
void main() {
  group('the database name', () {
    test('a hyphen is refused, because DDL quotes it as an identifier', () {
      // `CREATE DATABASE "xorder-pos"` cannot take a bind parameter, so the
      // name is quoted into the statement and has to be an identifier. This
      // used to throw an ArgumentError out of the bootstrap and land in the
      // operator's error bar as Dart internals, five steps after typing.
      expect(DeploymentConfig.isPlainIdentifier('xorder-pos'), isFalse);
      expect(DeploymentConfig.isPlainIdentifier('xorder_pos'), isTrue);
    });

    test('it may not start with a digit, and may not be empty', () {
      expect(DeploymentConfig.isPlainIdentifier('2fast'), isFalse);
      expect(DeploymentConfig.isPlainIdentifier(''), isFalse);
      expect(DeploymentConfig.isPlainIdentifier('_till'), isTrue);
    });

    test('the connection step will not advance on a name DDL cannot take', () {
      const bad = SetupDraft(
        step: SetupStep.deployment,
        deployment: DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseName: 'xorder-pos',
        ),
        databasePassword: 'secret',
      );
      expect(bad.canAdvance, isFalse);

      const good = SetupDraft(
        step: SetupStep.deployment,
        deployment: DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseName: 'xorder_pos',
        ),
        databasePassword: 'secret',
      );
      expect(good.canAdvance, isTrue);
    });
  });

  group('the first person\'s PIN', () {
    test('is exactly as long as a keypad can enter', () {
      SetupDraft withPin(String pin) => SetupDraft(ownerPin: pin);

      expect(withPin('123').hasUsablePin, isFalse, reason: 'too short');
      expect(withPin('1234').hasUsablePin, isTrue);
      expect(
        withPin('12345').hasUsablePin,
        isFalse,
        reason: 'the keypad submits on the fourth digit — a fifth is unusable',
      );
      expect(SetupDraft.pinLength, PinRules.length);
    });

    test('is digits, because a keypad has nothing else on it', () {
      expect(const SetupDraft(ownerPin: '12a4').hasUsablePin, isFalse);
      expect(const SetupDraft(ownerPin: '1 34').hasUsablePin, isFalse);
    });

    test('every refusal reaches the console, not only the screen', () {
      // The operator gets one sentence about what to do next, which is the
      // wrong thing to debug from. Routed through the single state setter so
      // no future `copyWith(error: …)` can add a refusal that never logs.
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      final logged = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      addTearDown(() => debugPrint = previous);

      controller.state = container
          .read(setupProvider)
          .copyWith(error: 'something was refused');

      expect(logged, isNotEmpty);
      expect(logged.first, contains('something was refused'));
      // Names the step, which is the first thing anybody reading the log needs.
      expect(logged.first, contains('setup['));
    });

    test('the setter refuses what the till could never accept', () {
      // Enforced as it is TYPED. A fifth digit accepted here becomes a PIN the
      // till cannot take, discovered later by somebody who cannot sign in.
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setOwnerPin('12ab34');
      expect(container.read(setupProvider).ownerPin, '1234');

      controller.setOwnerPin('9999999999999999');
      expect(
        container.read(setupProvider).ownerPin,
        '9999',
        reason: 'truncated to the length rather than silently over it',
      );
    });
  });
}
