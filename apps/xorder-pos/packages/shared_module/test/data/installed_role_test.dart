import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/config/installed_role.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// A desktop installed "Till only" is a child of the main device.
///
/// It used to open the main-device wizard — licence, code, then a database
/// screen with nothing to point at, because the installer had put no
/// PostgreSQL on it. The marker the installer now leaves is what tells the
/// app so before the first screen.
void main() {
  group('the marker', () {
    test('says child, and is read as one', () {
      expect(
        InstalledRole.tryParse('{"role": "client_terminal"}\r\n'),
        TerminalRole.child,
      );
      expect(
        InstalledRole.tryParse('{"role": "main_device"}'),
        TerminalRole.main,
      );
    });

    test('anything this build half-understands is no answer', () {
      // No guess: the platform default stands, which is what a machine with no
      // file at all gets.
      expect(InstalledRole.tryParse('{"role": "kiosk"}'), isNull);
      expect(InstalledRole.tryParse('{"role": 3}'), isNull);
      expect(InstalledRole.tryParse('{}'), isNull);
      expect(InstalledRole.tryParse('[]'), isNull);
      expect(InstalledRole.tryParse('not json'), isNull);
      expect(InstalledRole.tryParse(''), isNull);
    });
  });

  group('a desktop the installer marked "till only"', () {
    ProviderContainer boot(TerminalRole? installed) {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          installedRoleProvider.overrideWithValue(installed),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('opens on finding its main device, like a tablet', () {
      final draft = boot(TerminalRole.child).read(setupProvider);

      expect(draft.deployment.isChild, isTrue);
      expect(draft.step, SetupStep.deployment);
      expect(draft.visibleSteps, SetupDraft.childSteps);
      // Blank, not localhost: its database is never on this machine, and a
      // pre-filled `localhost` is an answer it must not be able to accept.
      expect(draft.deployment.databaseHost, '');
    });

    test('and a desktop with no marker is the main device it always was', () {
      final draft = boot(null).read(setupProvider);

      expect(draft.deployment.isChild, isFalse);
      // A main device's first screen, not a child's: on the default (cloud)
      // mode that is the owner's sign-in (pos-cloud-sign-in-setup).
      expect(draft.step, SetupStep.account);
    });
  });
}
