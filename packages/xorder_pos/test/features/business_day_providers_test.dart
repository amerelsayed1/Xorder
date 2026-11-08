import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/business_day_service.dart';

import 'package:xorder_pos_test_support/fake_business_days.dart';
import 'package:xorder_pos_test_support/fakes.dart';

/// The real providers the two sign-in doors use, not the doubles the widget
/// tests hand them (review of the business-day change, 2026-10-24): that the
/// day is opened on behalf of the person opening, that what reads the day is
/// refreshed, and that nothing inside can stop a shift opening.
void main() {
  const rana = PosStaff(
    id: 4,
    name: 'Rana',
    username: 'rana',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.shiftOpen},
    ),
  );

  ProviderContainer boot(
    FakeBusinessDays days, {
    List<Override> more = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        businessDayRepositoryProvider.overrideWithValue(days),
        ...more,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('opens the day for the person opening, and refreshes the day', () async {
    final days = FakeBusinessDays();
    final container = boot(days);

    // Cached as "no day" first, as the start screen would hold it.
    expect(await container.read(businessDayProvider.future), isNull);

    final result = await container.read(ensureBusinessDayProvider)(rana);

    expect(result.outcome, BusinessDayOutcome.opened);
    expect(days.openedBy, [rana.id], reason: 'by the person opening');
    expect(
      (await container.read(businessDayProvider.future))?.id,
      result.day!.id,
      reason: 'the Close button and Home read a refreshed day',
    );
  });

  test(
    'a day left open long ago raises the notice; today\'s does not',
    () async {
      final stale = boot(FakeBusinessDays(openDay: testDay(1, DateTime(2000))));
      final notice = await stale.read(dayNoticeProvider.future);
      expect(notice?.kind, DayNoticeKind.staleOpenDay);

      final today = DayPolicy.defaults.dateFor(DateTime.now());
      final fine = boot(FakeBusinessDays(openDay: testDay(2, today)));
      expect(await fine.read(dayNoticeProvider.future), isNull);
    },
  );

  test('nothing inside the glue can throw into the shift dialog', () async {
    // The dialog awaits this inside a `try` whose `catch` stops the shift
    // opening and prints the raw exception. A failure reading settings, say,
    // must come back as a result instead.
    final days = FakeBusinessDays();
    final container = boot(
      days,
      more: [
        dayPolicyProvider.overrideWith((ref) => throw StateError('settings')),
      ],
    );

    final result = await container.read(ensureBusinessDayProvider)(rana);

    expect(result.outcome, BusinessDayOutcome.failed);
    expect(days.opened, isEmpty);
  });
}
