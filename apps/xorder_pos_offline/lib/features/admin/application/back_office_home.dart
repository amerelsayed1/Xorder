import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/app/branch_sales_providers.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/data/postgres/postgres_branch_sales_repository.dart';
import 'package:shared_module/domain/models/home_sales.dart';
import 'package:shared_module/domain/repositories/repositories.dart';

/// Home's figures (BO-4): the open day — or the last closed one — and the day
/// before it, cut at the same time since opening.
///
/// **The local database, on every deployment.** Not [branchSalesSourceProvider]:
/// on a per-till cloud terminal that asks the platform, and POS-BE-029 answers
/// whole days only, so it cannot give "yesterday by this hour" — and a delta
/// built from one cut and one whole day would compare two different things.
/// The cost is that such a till's Home shows its own sales rather than the
/// branch's; on an offline install or a shared-LAN branch, which is where Home
/// is the only dashboard (plan 17 §2), the local database IS the branch.
///
/// Public and taking its repositories, so the database suite can hold each
/// tile to [BranchSales] for the same day without a widget in the way.
Future<HomeSales?> readHomeSales({
  required BusinessDayRepository days,
  required PostgresBranchSalesRepository sales,
  required DateTime now,
}) async {
  final day = await days.current() ?? await days.lastClosed();
  if (day == null) return null;
  final shown = (await sales.summary(day.date)).sales!;

  final before = await days.lastClosed(before: day.date);
  if (before == null) return HomeSales(day: day, sales: shown);
  final previous = (await sales.summary(
    before.date,
    until: comparisonCut(day: day, previous: before, now: now),
  )).sales!;
  return HomeSales(
    day: day,
    sales: shown,
    previousDay: before,
    previous: previous,
  );
}

/// Null on a till with no database: there is no day to show, and Home says so
/// rather than drawing zeros that would read as a day with no sales.
final homeSalesProvider = FutureProvider.autoDispose<HomeSales?>((ref) async {
  final sales = ref.watch(postgresBranchSalesProvider);
  if (sales == null) return null;
  return readHomeSales(
    days: ref.watch(businessDayRepositoryProvider),
    sales: sales,
    now: DateTime.now(),
  );
});

// No "last platform sync" here (pos-split-apps, stage 4). It read
// `cloudSyncProvider`, which the offline app never binds, for a Home card that
// had already been taken away; the offline Home has no platform to have heard
// from.
