import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/business_day_service.dart';

import '../support/fake_business_days.dart';

/// Opening the trading day (plan: report 2026-10-24, Part 4).
///
/// Found driving the real till offline: nothing in the product ever called
/// `BusinessDayRepository.open`, so Home said "no business day opened yet",
/// every sale kept a NULL `business_day_id`, and "Close the day" could never
/// appear. These are the rules for the missing caller, held without a database.
void main() {
  const rana = PosStaff(
    id: 4,
    name: 'Rana',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.shiftOpen},
    ),
  );
  const policy = DayPolicy(); // rolls over at 06:00

  DateTime date(int day) => DateTime(2026, 10, day);

  group('ensureBusinessDay', () {
    test('opens the day the moment belongs to', () async {
      final days = FakeBusinessDays();
      final result = await ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 14),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.opened);
      expect(result.day!.date, date(24));
      expect(days.opened, [date(24)]);
    });

    test('02:00 is still last evening: the day rolls over at 06:00', () async {
      // A business that closes at 2 a.m. takes Saturday-morning money that
      // belongs to Friday's takings.
      final days = FakeBusinessDays();
      final result = await ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 25, 2),
        by: rana,
      );

      expect(result.day!.date, date(24));
    });

    test('a day that is already open is used, not duplicated', () async {
      final days = FakeBusinessDays(openDay: testDay(1, date(24)));
      final result = await ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 9),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.reused);
      expect(result.day!.id, 1);
      expect(days.opened, isEmpty, reason: 'the database allows one open day');
    });

    test('a day left open from yesterday is still used', () async {
      // Closing is a person's decision with a blocker list; the till does not
      // close it for them, and cannot open a second one.
      final days = FakeBusinessDays(openDay: testDay(1, date(22)));
      final result = await ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 9),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.reused);
      expect(result.day!.date, date(22));
      expect(days.opened, isEmpty);
    });

    test('a date that was already closed is reported, not thrown', () async {
      // `open` refuses to resurrect a day somebody deliberately ended. A late
      // shift on that date must still open.
      final days = FakeBusinessDays(
        closed: testDay(7, date(24), closedAt: DateTime(2026, 10, 24, 23)),
      );
      final result = await ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 23, 30),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.dateAlreadyClosed);
      expect(result.day, isNull);
    });

    test('an earlier closed day does not block opening today', () async {
      final days = FakeBusinessDays(
        closed: testDay(7, date(23), closedAt: DateTime(2026, 10, 23, 23)),
      );
      final result = await ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 9),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.opened);
    });

    test('losing a race to another till takes the day it opened', () async {
      // Two tills starting at the roll-over: the loser's insert hits the
      // one-open-day index. It wants the winner's day, not an error.
      final days = FakeBusinessDays(raceWinner: testDay(9, date(23)));
      final result = await ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 6),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.reused);
      expect(result.day!.id, 9);
    });

    test('a database failure is reported and never thrown', () async {
      final result = await ensureBusinessDay(
        days: FakeBusinessDays(failEverything: true),
        policy: policy,
        now: DateTime(2026, 10, 24, 9),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.failed);
      expect(result.error, isNotNull);
    });

    test('an open that fails with nothing to take is a failure', () async {
      final result = await ensureBusinessDay(
        days: FakeBusinessDays(failOpen: true),
        policy: policy,
        now: DateTime(2026, 10, 24, 9),
        by: rana,
      );

      expect(result.outcome, BusinessDayOutcome.failed);
    });
  });

  group('dayNotice', () {
    final today = DateTime(2026, 10, 24, 12);

    test('a day open from an earlier date says so', () {
      final notice = dayNotice(
        open: testDay(1, date(22)),
        lastClosed: null,
        policy: policy,
        now: today,
        shiftOpen: true,
      );

      expect(notice?.kind, DayNoticeKind.staleOpenDay);
      expect(notice?.date, date(22));
    });

    test("today's day open is nothing to say", () {
      expect(
        dayNotice(
          open: testDay(1, date(24)),
          lastClosed: null,
          policy: policy,
          now: today,
          shiftOpen: true,
        ),
        isNull,
      );
    });

    test("selling after today's day was closed says so", () {
      final notice = dayNotice(
        open: null,
        lastClosed: testDay(1, date(24), closedAt: DateTime(2026, 10, 24, 11)),
        policy: policy,
        now: today,
        shiftOpen: true,
      );

      expect(notice?.kind, DayNoticeKind.todayAlreadyClosed);
      expect(notice?.date, date(24));
    });

    test('yesterday closed is the normal morning, not a notice', () {
      expect(
        dayNotice(
          open: null,
          lastClosed: testDay(
            1,
            date(23),
            closedAt: DateTime(2026, 10, 23, 23),
          ),
          policy: policy,
          now: today,
          shiftOpen: true,
        ),
        isNull,
      );
    });

    test('no shift open, no notice about selling', () {
      expect(
        dayNotice(
          open: null,
          lastClosed: testDay(
            1,
            date(24),
            closedAt: DateTime(2026, 10, 24, 11),
          ),
          policy: policy,
          now: today,
          shiftOpen: false,
        ),
        isNull,
      );
    });
  });
}
