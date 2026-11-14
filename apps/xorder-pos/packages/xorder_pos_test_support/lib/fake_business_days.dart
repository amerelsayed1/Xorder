import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/repositories/repositories.dart';

BusinessDay testDay(int id, DateTime date, {DateTime? closedAt}) => BusinessDay(
  id: id,
  date: date,
  openedAt: date.add(const Duration(hours: 8)),
  closedAt: closedAt,
);

/// A branch's days in memory, with the two rules the database enforces: one open day, and
/// a closed date cannot be opened again.
class FakeBusinessDays implements BusinessDayRepository {
  FakeBusinessDays({
    this.openDay,
    this.closed,
    this.raceWinner,
    this.failEverything = false,
    this.failOpen = false,
  });

  BusinessDay? openDay;
  final BusinessDay? closed;

  /// A day another till opens between our read and our insert.
  final BusinessDay? raceWinner;
  final bool failEverything;
  final bool failOpen;

  final List<DateTime> opened = [];

  /// Who `open` was asked on behalf of, in order.
  final List<int> openedBy = [];

  @override
  Future<BusinessDay?> current() async {
    if (failEverything) throw StateError('database down');
    return openDay;
  }

  @override
  Future<BusinessDay?> lastClosed({DateTime? before}) async {
    if (failEverything) throw StateError('database down');
    final day = closed;
    if (day == null) return null;
    if (before != null && !day.date.isBefore(before)) return null;
    return day;
  }

  @override
  Future<BusinessDay> open({
    required DateTime date,
    required PosStaff by,
  }) async {
    if (failEverything || failOpen) throw StateError('database down');
    if (raceWinner != null) {
      openDay = raceWinner; // somebody else got there first
      throw StateError('pos_business_days_one_open');
    }
    if (closed != null && closed!.date == date) {
      throw StateError('The business day for $date is already closed.');
    }
    opened.add(date);
    openedBy.add(by.id);
    return openDay = testDay(100 + opened.length, date);
  }

  @override
  Future<DayCloseCheck> check() => throw UnimplementedError();

  @override
  Future<BusinessDay> close({
    required BusinessDay day,
    required PosStaff by,
    bool force = false,
    String? forceReason,
  }) => throw UnimplementedError();
}
