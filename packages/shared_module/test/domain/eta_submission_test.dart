import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/domain/models/eta_submission.dart';

/// How far a receipt has got, and whether anybody should care.
///
/// The deadline arithmetic is the point. Egypt gives 24 hours from issuance,
/// and a till that cannot say which receipts are close to that is a till whose
/// operator finds out from a fine.
void main() {
  final now = DateTime.utc(2026, 9, 8, 18);

  EtaSubmission at(Duration ago, {EtaStatus status = EtaStatus.signed}) =>
      EtaSubmission(
        id: 1,
        orderId: 10,
        uuid: 'a' * 64,
        receiptNumber: 'INV-1',
        issuedAt: now.subtract(ago),
        status: status,
        deviceSerial: 'TILL-1',
      );

  group('status', () {
    test('only acceptance discharges the obligation', () {
      expect(EtaStatus.accepted.isOutstanding, isFalse);
      for (final status in [
        EtaStatus.pending,
        EtaStatus.signed,
        EtaStatus.submitted,
        EtaStatus.rejected,
      ]) {
        expect(status.isOutstanding, isTrue, reason: status.wire);
      }
    });

    test('a cancelled receipt is closed, because a person closed it', () {
      expect(EtaStatus.cancelled.isOutstanding, isFalse);
    });

    test('only a rejection needs a person', () {
      // Everything else is the drain's job. A rejection is almost always a
      // wrong field in the receipt profile, and retrying it forever would be
      // a queue that grows and never moves.
      expect(EtaStatus.rejected.needsAttention, isTrue);
      expect(EtaStatus.signed.needsAttention, isFalse);
    });

    test('an unknown wire value throws rather than guessing', () {
      // A till that read a newer status as `accepted` would stop chasing a
      // receipt that was never filed.
      expect(() => EtaStatus.fromWire('cleared'), throwsArgumentError);
      expect(EtaStatus.fromWire('accepted'), EtaStatus.accepted);
    });
  });

  group('the deadline', () {
    test('is twenty-four hours from issuance', () {
      expect(EtaSubmission.window, const Duration(hours: 24));
    });

    test('a fresh receipt is neither late nor due', () {
      final fresh = at(const Duration(minutes: 5));
      expect(fresh.isLate(now), isFalse);
      expect(fresh.isDueSoon(now), isFalse);
    });

    test('twenty hours in, it is due soon', () {
      expect(at(const Duration(hours: 20)).isDueSoon(now), isTrue);
    });

    test('nineteen hours in, it is not yet', () {
      expect(at(const Duration(hours: 19)).isDueSoon(now), isFalse);
    });

    test('exactly twenty-four hours is late, not due soon', () {
      // The boundary belongs to the worse answer. A receipt at exactly the
      // deadline has not been filed within it.
      final boundary = at(const Duration(hours: 24));
      expect(boundary.isLate(now), isTrue);
      expect(boundary.isDueSoon(now), isFalse);
    });

    test('an accepted receipt is never late, however old', () {
      // It was filed. When it was filed is the submission timestamp's job,
      // not this one's.
      final old = at(const Duration(days: 30), status: EtaStatus.accepted);
      expect(old.isLate(now), isFalse);
      expect(old.isDueSoon(now), isFalse);
    });

    test('a rejected receipt goes on being late', () {
      // The obligation is not discharged by having been refused.
      expect(
        at(const Duration(days: 2), status: EtaStatus.rejected).isLate(now),
        isTrue,
      );
    });

    test('age is measured against a clock that is passed in', () {
      expect(at(const Duration(hours: 3)).age(now), const Duration(hours: 3));
    });
  });

  group('the summary', () {
    test('an empty queue is clear and not urgent', () {
      expect(EtaQueueSummary.empty.isClear, isTrue);
      expect(EtaQueueSummary.empty.isUrgent, isFalse);
    });

    test('outstanding work alone is not urgent', () {
      // A receipt issued four minutes ago and not yet sent is the normal
      // state of a working till, not an alarm.
      const summary = EtaQueueSummary(
        outstanding: 3,
        rejected: 0,
        late: 0,
        oldest: null,
      );
      expect(summary.isClear, isFalse);
      expect(summary.isUrgent, isFalse);
    });

    test('a late receipt is urgent', () {
      const summary = EtaQueueSummary(
        outstanding: 3,
        rejected: 0,
        late: 1,
        oldest: null,
      );
      expect(summary.isUrgent, isTrue);
    });

    test('a rejection is urgent even inside the window', () {
      // Nothing will move it without a person, so waiting costs the whole
      // remaining window.
      const summary = EtaQueueSummary(
        outstanding: 1,
        rejected: 1,
        late: 0,
        oldest: null,
      );
      expect(summary.isUrgent, isTrue);
    });
  });
}
