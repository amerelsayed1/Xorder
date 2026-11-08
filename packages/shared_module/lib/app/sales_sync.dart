import '../domain/models/sync_outcome.dart';

/// The till's conversation with a platform, as the shared shell sees it.
///
/// **pos-split-apps, stage 3.** The shell nudges a sync after every sale,
/// kicks one from the pill and the Settings menu, asks when the last pass was,
/// and reads each pass's [SyncOutcome]. None of that needs to know how the
/// pass is made. The one implementation, `CloudSync`, lives in
/// `apps/xorder_pos_cloud`, which binds it to `cloudSyncProvider`; the offline
/// app binds nothing, and every caller already treats null as "no platform".
abstract interface class SalesSync {
  /// Run a pass now, without waiting for it.
  void kick();

  /// Ask for a pass soon — coalesced, so a burst of sales is one pass.
  void nudge({DateTime Function() now});

  /// Whether a nudge is waiting to run.
  bool get nudgePending;

  /// How long since the last pass ended; null before the first.
  Duration? get sinceLastPass;

  /// Run a pass and wait for its outcome. Concurrent calls share one pass.
  Future<SyncOutcome> run();

  /// When this till last heard the platform, from the record it keeps.
  Future<DateTime?> lastSyncedAt();

  void dispose();
}
