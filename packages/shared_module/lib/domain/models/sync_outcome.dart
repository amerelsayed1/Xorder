/// What a sync pass reports back to the till — data, not logs.
///
/// Shared by both apps (pos-split-apps, stage 3): the cloud app produces these
/// from its outbox drain and heartbeat; the shared shell consumes them
/// (`applySyncOutcome`, the sync pill, the held-sync counts). The producer
/// lives in `apps/xorder_pos_cloud`; the words it speaks live here so the
/// offline app never links the drain.
library;

/// What one drain pass did. The sync pill renders it.
class DrainReport {
  const DrainReport({
    this.delivered = 0,
    this.quarantined = 0,
    this.deferred = 0,
    this.wentOffline = false,
  });

  final int delivered;
  final int quarantined;

  /// Held for retry — a refusal whose cure is time, not a person.
  final int deferred;

  /// True when the platform stopped answering mid-pass. The pass stops there:
  /// hammering a dead endpoint once per queued order helps nobody.
  final bool wentOffline;

  int get attempted => delivered + quarantined + deferred;
}

/// What one sync pass — heartbeat, config refresh and drain — came to.
class SyncOutcome {
  const SyncOutcome({
    required this.drain,
    this.reseeded = false,
    this.deviceTokenRejected = false,
    this.heartbeatOk = false,
    this.logoChanged = false,
  });

  final DrainReport drain;

  /// The platform answered the heartbeat. False when it could not be reached
  /// at all, which is the difference between "nothing to send" and "nobody
  /// listening" — the sync schedule needs to tell those apart.
  final bool heartbeatOk;

  /// Everything this till had to say has been said, and the platform was
  /// there to hear it.
  ///
  /// **Quarantined rows do not count against this.** A quarantined record is
  /// held for a person (POS-BE-019: the record itself is at fault, retrying
  /// will never change the answer), so letting one hold the till at the fast
  /// cadence would mean a single bad row polling the platform every half hour
  /// until somebody noticed — forever, on a till that is otherwise perfectly
  /// in sync.
  bool get settled =>
      heartbeatOk &&
      !deviceTokenRejected &&
      !drain.wentOffline &&
      drain.deferred == 0;

  /// The platform's `config_version` moved past ours, so the bundle was
  /// re-fetched and re-seeded — catalog, staff, floor, money rules.
  final bool reseeded;

  /// The business logo stored on this till changed in this pass (XORD-021): a
  /// new picture was downloaded, or the platform's was removed.
  final bool logoChanged;

  /// `DEVICE_TOKEN_INVALID` came back. The queue is untouched — money is never
  /// discarded over a credential — but the till has to be re-paired, and the
  /// UI must say so rather than showing an eternally-stuck pill.
  final bool deviceTokenRejected;
}
