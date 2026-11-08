import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/data/cloud/cloud_sync.dart';
import 'package:xorder_pos/data/cloud/outbox_drain.dart';

/// A till whose terminal has been deleted server-side must SAY so.
///
/// The bug this guards: `SyncOutcome.deviceTokenRejected` was computed by
/// CloudSync and consumed by nothing. Every sync pass failed with
/// DEVICE_TOKEN_INVALID, the UI changed in no way at all, and the only symptom
/// was a pending count climbing where nobody looks. A silent field is exactly
/// what a widget test cannot catch, so the wiring is asserted directly.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('a healthy till reports no rejection', () {
    expect(container.read(terminalRejectedProvider), isFalse);
  });

  test('a rejected device credential reaches the UI state', () {
    applySyncOutcome(
      container,
      const SyncOutcome(drain: DrainReport(), deviceTokenRejected: true),
    );

    expect(
      container.read(terminalRejectedProvider),
      isTrue,
      reason: 'the banner has nothing to render from unless this is set',
    );
  });

  test('re-pairing clears it without a restart', () {
    applySyncOutcome(
      container,
      const SyncOutcome(drain: DrainReport(), deviceTokenRejected: true),
    );
    expect(container.read(terminalRejectedProvider), isTrue);

    // The next pass succeeds — the operator re-paired the till. The warning
    // must retract itself, or it becomes a stale accusation nobody can clear
    // and operators learn to ignore the banner entirely.
    applySyncOutcome(container, const SyncOutcome(drain: DrainReport()));

    expect(container.read(terminalRejectedProvider), isFalse);
  });

  test('an ordinary pass does not raise it', () {
    applySyncOutcome(
      container,
      const SyncOutcome(drain: DrainReport(), reseeded: true),
    );

    expect(container.read(terminalRejectedProvider), isFalse);
  });
}
