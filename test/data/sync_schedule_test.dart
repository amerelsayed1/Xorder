import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/cloud/cloud_sync.dart';
import 'package:xorder_pos/data/cloud/outbox_drain.dart';

/// When the next sync pass runs.
///
/// Owner decision, 27 Sep 2026: four hours normally, thirty minutes until
/// everything is through. The cost — a sale reaching the dashboard up to four
/// hours late — was named and accepted, and what buys it back is the retry.
/// So the claim worth holding is not the two numbers but the word "until":
/// a till with anything still queued, or one nobody answered, must come back
/// in half an hour and not in four.
void main() {
  SyncOutcome outcome({
    bool heartbeatOk = true,
    bool tokenRejected = false,
    int delivered = 0,
    int deferred = 0,
    int quarantined = 0,
    bool wentOffline = false,
  }) => SyncOutcome(
    heartbeatOk: heartbeatOk,
    deviceTokenRejected: tokenRejected,
    drain: DrainReport(
      delivered: delivered,
      deferred: deferred,
      quarantined: quarantined,
      wentOffline: wentOffline,
    ),
  );

  group('everything is through', () {
    test('an empty queue and a live platform waits four hours', () {
      expect(SyncSchedule.after(outcome()), SyncSchedule.idle);
      expect(SyncSchedule.idle, const Duration(hours: 4));
    });

    test('so does a pass that delivered everything it had', () {
      expect(SyncSchedule.after(outcome(delivered: 12)), SyncSchedule.idle);
    });
  });

  group('something is still pending', () {
    test('a platform that stopped answering is tried again in half an hour', () {
      expect(
        SyncSchedule.after(outcome(wentOffline: true)),
        SyncSchedule.retry,
      );
      expect(SyncSchedule.retry, const Duration(minutes: 30));
    });

    test('a heartbeat nobody answered is the same answer', () {
      // The drain can report a clean pass simply because it never ran.
      expect(SyncSchedule.after(outcome(heartbeatOk: false)), SyncSchedule.retry);
    });

    test('money held for retry holds the till at the fast cadence', () {
      expect(SyncSchedule.after(outcome(deferred: 1)), SyncSchedule.retry);
    });

    test('a rejected device token comes back soon, so re-pairing is felt', () {
      expect(
        SyncSchedule.after(outcome(heartbeatOk: false, tokenRejected: true)),
        SyncSchedule.retry,
      );
    });
  });

  group('a nudge', () {
    // Before this, "automatic" meant one pass at launch and one every four
    // hours: a sale rung up at noon reached the dashboard at four, and a
    // cashier added on the dashboard could not sign in without a restart.
    final t0 = DateTime.utc(2026, 10, 16, 9);

    test('with no pass yet waits only the debounce', () {
      expect(
        SyncSchedule.nudgeAfter(lastPass: null, now: t0),
        SyncSchedule.nudgeDelay,
      );
    });

    test('long after the last pass waits only the debounce', () {
      expect(
        SyncSchedule.nudgeAfter(
          lastPass: t0.subtract(const Duration(minutes: 5)),
          now: t0,
        ),
        SyncSchedule.nudgeDelay,
      );
    });

    test('right after a pass waits out the floor, so a busy counter makes '
        'one pass per floor and not one per sale', () {
      expect(
        SyncSchedule.nudgeAfter(
          lastPass: t0.subtract(const Duration(seconds: 5)),
          now: t0,
        ),
        SyncSchedule.nudgeFloor - const Duration(seconds: 5),
      );
    });
  });

  test('a quarantined row does NOT hold the till at the fast cadence', () {
    // POS-BE-019: the record itself is at fault and retrying will never change
    // the answer. Letting one count as "not yet synced" would have a single bad
    // row polling the platform every half hour forever, on a till that is
    // otherwise completely in sync — and the person who has to fix it is not
    // reading a timer.
    expect(
      SyncSchedule.after(outcome(delivered: 3, quarantined: 1)),
      SyncSchedule.idle,
    );
  });
}
