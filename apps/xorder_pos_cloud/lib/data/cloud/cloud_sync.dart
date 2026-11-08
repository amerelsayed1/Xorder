import 'dart:async';
import 'dart:io';

import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/terminal_profile.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'bootstrap_bundle.dart';
import 'bootstrap_seeder.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:shared_module/app/sales_sync.dart';
import 'package:shared_module/core/config/app_version.dart';
import 'package:shared_module/domain/models/sync_outcome.dart';

export 'package:shared_module/domain/models/sync_outcome.dart' show SyncOutcome, DrainReport;
import 'package:shared_module/data/cloud/device_token_vault.dart';
import 'logo_sync.dart';
import 'outbox_drain.dart';

/// When the next pass runs.
///
/// **Owner decision, 27 Sep 2026: every four hours, and every thirty minutes
/// until everything is through.** It replaced a flat three-minute tick that
/// ran whether or not there was anything to say and whether or not the last
/// pass had worked.
///
/// The cost was named at the time and accepted: a sale now reaches the
/// dashboard up to four hours after it is rung up, a menu change made in the
/// dashboard reaches the till up to four hours later, and the fleet registry
/// sees a healthy till as four hours stale. What buys that back is the retry —
/// a till that is offline, or that still has money queued, does not wait four
/// hours to try again.
///
/// Pure, and a class rather than two constants, because the rule is the thing
/// worth a test: "retry until it is all through" is only true if [SyncOutcome]
/// answers honestly about what is still pending.
abstract final class SyncSchedule {
  /// Nothing pending and the platform is answering.
  static const idle = Duration(hours: 4);

  /// Something is still queued, or nobody answered.
  static const retry = Duration(minutes: 30);

  /// How long after [outcome] the next pass should run.
  static Duration after(SyncOutcome outcome) =>
      outcome.settled ? idle : retry;

  /// A nudge waits this long, so a sale and its shift open, or three cash
  /// movements in a row, make one pass rather than three.
  static const nudgeDelay = Duration(seconds: 2);

  /// And never runs passes closer together than this, however busy the
  /// counter is: a heartbeat every two seconds would be noise in the
  /// platform's logs and no faster for anybody.
  static const nudgeFloor = Duration(seconds: 20);

  /// How long a nudge at [now] should wait, given when the last pass ran.
  static Duration nudgeAfter({required DateTime? lastPass, required DateTime now}) {
    if (lastPass == null) return nudgeDelay;
    final since = now.difference(lastPass);
    return since >= nudgeFloor ? nudgeDelay : nudgeFloor - since;
  }
}

/// The cloud terminal's background conversation with the platform.
///
/// One pass = heartbeat → (maybe) re-bootstrap → drain. The heartbeat comes
/// first because its response (POS-BE-022 amendment) carries `config_version`
/// and `terminal_status`, which decide whether the other two steps are even
/// worth making. Passes are serialised: a timer tick landing while a manual
/// "sync now" runs joins the same pass rather than racing it.
class CloudSync implements SalesSync {
  CloudSync({
    required PosDatabase database,
    required this.config,
    required this.api,
    required this.vault,
    required this.profile,
    this.onChanged,
  }) : _db = database,
       _drain = OutboxDrain(database: database, config: config, api: api);

  final PosDatabase _db;
  final DeploymentConfig config;
  final PosCloudApi api;
  final DeviceTokenVault vault;
  final TerminalProfile profile;

  /// Poked after any pass that changed local state — delivered sales, a
  /// re-seeded catalog — so providers can invalidate what they cache.
  final void Function(SyncOutcome outcome)? onChanged;

  final OutboxDrain _drain;
  Future<SyncOutcome>? _running;

  /// Kick a pass without waiting for it — what "Sync now" does.
  @override
  void kick() => unawaited(run());

  Timer? _nudge;
  DateTime? _lastPass;

  /// Ask for a pass soon, because something just changed that the platform
  /// should hear about: a sale, a shift, a cash movement, a customer — or a
  /// till arriving at its lock screen, where a PIN set on the dashboard a
  /// minute ago is exactly what it needs.
  ///
  /// Debounced and rate-limited by [SyncSchedule.nudgeAfter], and only on
  /// the automatic policy: a till whose operator chose to sync by hand is
  /// not synced behind their back. Before this, "automatic" meant one pass
  /// at launch and one every four hours, so a sale rung up at noon reached
  /// the dashboard at four, and a cashier added on the dashboard could not
  /// sign in until the till was restarted (16 Oct 2026).
  @override
  void nudge({DateTime Function() now = DateTime.now}) {
    if (config.syncPolicy != SyncPolicy.automatic) return;
    if (_nudge != null) return;
    final wait = SyncSchedule.nudgeAfter(lastPass: _lastPass, now: now());
    _nudge = Timer(wait, () {
      _nudge = null;
      kick();
    });
  }

  /// Whether a nudge is waiting to run.
  @override
  bool get nudgePending => _nudge != null;

  /// How long ago the last pass finished, or null before the first.
  @override
  Duration? get sinceLastPass {
    final last = _lastPass;
    return last == null ? null : DateTime.now().difference(last);
  }

  @override
  void dispose() {
    _nudge?.cancel();
    _nudge = null;
  }

  /// Run one pass, or join the one already running.
  @override
  Future<SyncOutcome> run() => _running ??= _pass().whenComplete(() {
    _running = null;
    _lastPass = DateTime.now();
  });

  Future<SyncOutcome> _pass() async {
    if (!config.mode.syncsSalesToPlatform || !vault.isSet) {
      return const SyncOutcome(drain: DrainReport());
    }

    var reseeded = false;
    var tokenRejected = false;

    final heartbeat = await api.heartbeat(await _heartbeatPayload());
    if (heartbeat.status == 401) {
      tokenRejected = true;
    } else if (heartbeat.ok) {
      final version = switch (heartbeat.body['config_version']) {
        final int v => v,
        final String v => int.tryParse(v),
        _ => null,
      };
      if (version != null && version > await _localConfigVersion()) {
        reseeded = await _refreshBootstrap();
      }
    }
    // A failed heartbeat is stale information, not lost money (POS-BE-022):
    // the drain still runs.

    final drain = tokenRejected ? const DrainReport() : await _drain.run();

    // After the bundle, because the bundle is what names the logo; and on every
    // pass, because a download that failed last time is still owed. Cheap when
    // there is nothing to fetch: one indexed row read.
    final logoChanged = tokenRejected ? false : await _syncLogo();

    final outcome = SyncOutcome(
      drain: drain,
      reseeded: reseeded,
      deviceTokenRejected: tokenRejected,
      heartbeatOk: heartbeat.ok,
      logoChanged: logoChanged,
    );
    if (reseeded || logoChanged || drain.delivered > 0 || tokenRejected) {
      onChanged?.call(outcome);
    }
    return outcome;
  }

  Future<bool> _syncLogo() async {
    final businessId = profile.businessId;
    if (businessId == null) return false;
    return LogoSync(
      database: _db,
      config: config,
      businessId: businessId,
      platformBase: api.baseUrl,
    ).run();
  }

  Future<bool> _refreshBootstrap() async {
    final reply = await api.bootstrap();
    if (!reply.ok) return false;
    final bundle = BootstrapBundle.tryParse(reply.body);
    if (bundle == null) return false;
    try {
      final report = await BootstrapSeeder(
        database: _db,
        config: config,
      ).seed(bundle);
      return report.applied;
    } on Object {
      // The catalog we have keeps selling; the seed retries next pass.
      return false;
    }
  }

  /// When the platform's bundle — menu, staff, floor, money rules — was last
  /// written into this till. Null when it never has been, or the read failed.
  ///
  /// The back office's Home shows it as "last sync". Not the time of the last
  /// sales drain, which nothing records: the pending count beside it is the
  /// honest answer to "has my money gone up", and a timestamp of a pass that
  /// sent nothing would say a till was fine while it held a day of sales.
  @override
  Future<DateTime?> lastSyncedAt() async {
    final businessId = profile.businessId;
    if (businessId == null) return null;
    try {
      final rows = await _db.query(
        config,
        'SELECT bootstrap_synced_at FROM pos_cloud_state '
        'WHERE business_id = @restaurant',
        parameters: {'restaurant': businessId},
      );
      return rows.isEmpty ? null : (rows.first[0] as DateTime?)?.toLocal();
    } on Object {
      return null;
    }
  }

  Future<int> _localConfigVersion() async {
    final businessId = profile.businessId;
    if (businessId == null) return -1;
    try {
      final rows = await _db.query(
        config,
        'SELECT config_version FROM pos_cloud_state WHERE business_id = @restaurant',
        parameters: {'restaurant': businessId},
      );
      return rows.isEmpty ? -1 : rows.first[0] as int;
    } on Object {
      return -1;
    }
  }

  /// Deliberately tiny, never carries a sale (POS-BE-022). `pending_count` and
  /// `oldest_pending_at` are the two fields Super Admin actually watches:
  /// unsynced money, per till, in real time.
  ///
  /// **Pending is what the drain will try; held is reported beside it.** Both
  /// used to be one number, so a single refused sale made `oldest_pending_at`
  /// the date of that sale for ever and the fleet view showed a till weeks
  /// behind that was in fact current (D8). Splitting them keeps the headline
  /// honest — "is this till's money moving" — while `held_count` is the money
  /// that is stuck, which is what support needs to ring about. Additive: a
  /// platform that has not added the column ignores the key.
  Future<Map<String, Object?>> _heartbeatPayload() async {
    int pending = 0;
    int held = 0;
    String? oldest;
    bool shiftOpen = false;
    try {
      final rows = await _db.query(
        config,
        '''
        SELECT count(*) FILTER (WHERE quarantined_at IS NULL),
               min(enqueued_at) FILTER (WHERE quarantined_at IS NULL),
               count(*) FILTER (WHERE quarantined_at IS NOT NULL)
        FROM (
          SELECT enqueued_at, quarantined_at FROM pos_outbox
           WHERE business_id = @restaurant AND delivered_at IS NULL
          UNION ALL
          SELECT enqueued_at, quarantined_at FROM pos_sync_outbox
           WHERE business_id = @restaurant AND delivered_at IS NULL
        ) owed
        ''',
        parameters: {'restaurant': profile.businessId},
      );
      pending = rows.first[0] as int;
      oldest = (rows.first[1] as DateTime?)?.toUtc().toIso8601String();
      held = rows.first[2] as int;

      final shifts = await _db.query(
        config,
        'SELECT 1 FROM pos_shifts WHERE terminal_id::text = @terminal '
        'AND closed_at IS NULL LIMIT 1',
        parameters: {'terminal': profile.terminalId},
      );
      shiftOpen = shifts.isNotEmpty;
    } on Object {
      // A heartbeat that cannot read its own database still says "alive".
    }

    return {
      'terminal_id': profile.terminalId,
      'app_version': posAppVersion,
      'platform': Platform.operatingSystem,
      'deployment_mode': config.mode.wire,
      'sync_policy': config.syncPolicy.wire,
      'pending_count': pending,
      'oldest_pending_at': oldest,
      'held_count': held,
      'shift_open': shiftOpen,
    };
  }
}
