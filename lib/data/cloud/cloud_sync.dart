import 'dart:async';
import 'dart:io';

import '../../core/config/deployment.dart';
import '../../core/config/terminal_profile.dart';
import '../postgres/pos_database.dart';
import 'bootstrap_bundle.dart';
import 'bootstrap_seeder.dart';
import 'cloud_api.dart';
import 'cloud_provisioning_repository.dart' show posAppVersion;
import 'device_token_vault.dart';
import 'outbox_drain.dart';

/// One sync pass, as data.
class SyncOutcome {
  const SyncOutcome({
    required this.drain,
    this.reseeded = false,
    this.deviceTokenRejected = false,
  });

  final DrainReport drain;

  /// The platform's `config_version` moved past ours, so the bundle was
  /// re-fetched and re-seeded — catalog, staff, floor, money rules.
  final bool reseeded;

  /// `DEVICE_TOKEN_INVALID` came back. The queue is untouched — money is never
  /// discarded over a credential — but the till has to be re-paired, and the
  /// UI must say so rather than showing an eternally-stuck pill.
  final bool deviceTokenRejected;
}

/// The cloud terminal's background conversation with the platform.
///
/// One pass = heartbeat → (maybe) re-bootstrap → drain. The heartbeat comes
/// first because its response (POS-BE-022 amendment) carries `config_version`
/// and `terminal_status`, which decide whether the other two steps are even
/// worth making. Passes are serialised: a timer tick landing while a manual
/// "sync now" runs joins the same pass rather than racing it.
class CloudSync {
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

  /// Kick a pass without waiting for it — what the sale screen does after
  /// settling, so "sold" and "synced" are seconds apart, not a timer apart.
  void kick() => unawaited(run());

  /// Run one pass, or join the one already running.
  Future<SyncOutcome> run() => _running ??= _pass().whenComplete(() {
    _running = null;
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

    final outcome = SyncOutcome(
      drain: drain,
      reseeded: reseeded,
      deviceTokenRejected: tokenRejected,
    );
    if (reseeded || drain.delivered > 0 || tokenRejected) {
      onChanged?.call(outcome);
    }
    return outcome;
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
  Future<DateTime?> lastSyncedAt() async {
    final restaurantId = profile.restaurantId;
    if (restaurantId == null) return null;
    try {
      final rows = await _db.query(
        config,
        'SELECT bootstrap_synced_at FROM pos_cloud_state '
        'WHERE restaurant_id = @restaurant',
        parameters: {'restaurant': restaurantId},
      );
      return rows.isEmpty ? null : (rows.first[0] as DateTime?)?.toLocal();
    } on Object {
      return null;
    }
  }

  Future<int> _localConfigVersion() async {
    final restaurantId = profile.restaurantId;
    if (restaurantId == null) return -1;
    try {
      final rows = await _db.query(
        config,
        'SELECT config_version FROM pos_cloud_state WHERE restaurant_id = @restaurant',
        parameters: {'restaurant': restaurantId},
      );
      return rows.isEmpty ? -1 : rows.first[0] as int;
    } on Object {
      return -1;
    }
  }

  /// Deliberately tiny, never carries a sale (POS-BE-022). `pending_count` and
  /// `oldest_pending_at` are the two fields Super Admin actually watches:
  /// unsynced money, per till, in real time.
  Future<Map<String, Object?>> _heartbeatPayload() async {
    int pending = 0;
    String? oldest;
    bool shiftOpen = false;
    try {
      final rows = await _db.query(
        config,
        'SELECT count(*), min(enqueued_at) FROM pos_outbox '
        'WHERE restaurant_id = @restaurant AND delivered_at IS NULL',
        parameters: {'restaurant': profile.restaurantId},
      );
      pending = rows.first[0] as int;
      oldest = (rows.first[1] as DateTime?)?.toUtc().toIso8601String();

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
      'shift_open': shiftOpen,
    };
  }
}
