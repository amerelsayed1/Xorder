import 'license.dart';

/// The platform's answer to `POST /api/pos/license/check` (POS-BE-031), and the
/// rules for turning it into what this till may do.
///
/// Pure: no clock of its own, no IO. The caller passes `now`, which is what
/// makes the grace window testable to the second.
///
/// **The verdict is the platform's, not ours.** On the online path the server
/// has already done the date arithmetic and applied the dashboard's suspension
/// or forced expiry; this only maps its `status` onto the gate the start screen
/// already reads. The cardinal rule is unchanged: nothing here ever cuts off an
/// open shift — every refusal is `canOpenShift: false, canSell: true`, and
/// cash-up, reprint and export are never gated (see [LicenseEntitlement]).
class OnlineVerdict {
  const OnlineVerdict({
    required this.status,
    this.startsAt,
    this.expiresAt,
    this.lifetime = false,
    this.graceDays = 0,
    this.message,
    this.cacheSeconds = defaultCacheSeconds,
  });

  /// 72 hours, the agreed default when a reply carries no `grace_policy`.
  static const defaultCacheSeconds = 259200;

  /// The longest a till will trust one answer, whatever the server says — so a
  /// bad value on the platform can never grant forever.
  static const maxCacheSeconds = 7 * 24 * 3600;

  /// The 404 `licence_not_found` answer, stored as a verdict of its own: it is
  /// as definite as any 200, and a till offline straight after hearing it must
  /// keep hearing it rather than fall back to an older "valid".
  static const notIssued = 'licence_not_found';

  /// One of `valid`, `expiring_soon`, `in_grace`, `expired`, `suspended`,
  /// `not_yet_valid`, `unknown`, or [notIssued].
  final String status;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool lifetime;
  final int graceDays;
  final String? message;
  final int cacheSeconds;

  /// How long this answer may stand in for the platform, clamped.
  Duration get trustFor =>
      Duration(seconds: cacheSeconds.clamp(0, maxCacheSeconds));

  /// Whether this is an answer at all. `unknown`, or a status this build has
  /// never heard of, is not one: it is never cached over a good verdict and
  /// never blocks — the till carries on with what it last knew.
  bool get isDefinite => switch (status) {
    'valid' ||
    'expiring_soon' ||
    'in_grace' ||
    'expired' ||
    'suspended' ||
    'not_yet_valid' ||
    notIssued => true,
    _ => false,
  };

  /// Never throws: a reply this build cannot read is null, and the caller
  /// treats it as no reply.
  static OnlineVerdict? tryParse(Map<String, Object?> json) {
    final status = json['status'];
    if (status is! String || status.isEmpty) return null;
    final policy = json['grace_policy'];
    final seconds = policy is Map ? policy['cache_seconds'] : null;
    return OnlineVerdict(
      status: status,
      startsAt: _date(json['starts_at']),
      expiresAt: _date(json['expires_at']),
      lifetime: json['lifetime'] == true,
      graceDays: json['grace_days'] is int ? json['grace_days'] as int : 0,
      message: json['message'] is String ? json['message'] as String : null,
      cacheSeconds: seconds is int && seconds >= 0
          ? seconds
          : defaultCacheSeconds,
    );
  }

  Map<String, Object?> toJson() => {
    'status': status,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'lifetime': lifetime,
    'grace_days': graceDays,
    'message': message,
    'grace_policy': {'cache_seconds': cacheSeconds},
  };

  /// What this till may do on this verdict.
  LicenseEntitlement entitlement(DateTime now) {
    final days = lifetime || expiresAt == null
        ? null
        : expiresAt!.difference(now).inDays;
    return switch (status) {
      'valid' => LicenseEntitlement(
        state: LicenseState.valid,
        canOpenShift: true,
        canSell: true,
        canChangeConfiguration: true,
        daysRemaining: days,
      ),
      'expiring_soon' => LicenseEntitlement(
        state: LicenseState.expiringSoon,
        canOpenShift: true,
        canSell: true,
        canChangeConfiguration: true,
        daysRemaining: days,
        notice: LicenceExpiresIn(days ?? 0),
      ),
      'in_grace' => LicenseEntitlement(
        state: LicenseState.inGrace,
        canOpenShift: true,
        canSell: true,
        // Frozen in grace, as on the file path: renew before rewiring the till.
        canChangeConfiguration: false,
        daysRemaining: days,
        notice: LicenceInGrace(
          expiresAt == null
              ? 0
              : expiresAt!
                    .add(Duration(days: graceDays))
                    .difference(now)
                    .inDays,
        ),
      ),
      'expired' => _held(LicenseState.expired, const LicenceExpired(), days),
      'suspended' => _held(
        LicenseState.suspended,
        LicenceSuspended(message),
        days,
      ),
      'not_yet_valid' => _held(
        LicenseState.notYetValid,
        LicenceNotStarted(startsAt ?? now),
        days,
      ),
      notIssued => _held(LicenseState.missing, const LicenceNotIssued(), null),
      // Not an answer — never a refusal. See [isDefinite].
      _ => LicenseEntitlement(
        state: LicenseState.valid,
        canOpenShift: true,
        canSell: true,
        canChangeConfiguration: true,
        daysRemaining: days,
      ),
    };
  }

  /// Past the window a cached verdict may stand in for the platform.
  static LicenseEntitlement unconfirmed(DateTime lastConfirmed) =>
      _held(LicenseState.unconfirmed, LicenceUnconfirmed(lastConfirmed), null);

  /// Expired-shaped: the next shift cannot open, the open one is never cut off.
  /// Deliberately not the file path's deny, which also stops selling — the
  /// platform is the one enforcing at every money write, so the till's job is
  /// only to stop a new day starting.
  static LicenseEntitlement _held(
    LicenseState state,
    LicenceNotice notice,
    int? days,
  ) => LicenseEntitlement(
    state: state,
    canOpenShift: false,
    canSell: true,
    canChangeConfiguration: false,
    daysRemaining: days,
    notice: notice,
  );

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}

/// What the till keeps between checks (POS-BE-031): where its verdict comes
/// from, and the last definite verdict with when it was heard.
class LicenceCheckRecord {
  const LicenceCheckRecord({this.enforcement, this.verdict, this.checkedAt});

  /// `online` or `offline` as the platform last said, or null when it never
  /// has. Null is treated as `offline` — the signed file — so a till never
  /// asks an endpoint it has not been told exists.
  final String? enforcement;
  final OnlineVerdict? verdict;
  final DateTime? checkedAt;

  bool get isOnline => enforcement == 'online';

  LicenceCheckRecord copyWith({
    String? enforcement,
    OnlineVerdict? verdict,
    DateTime? checkedAt,
  }) => LicenceCheckRecord(
    enforcement: enforcement ?? this.enforcement,
    verdict: verdict ?? this.verdict,
    checkedAt: checkedAt ?? this.checkedAt,
  );

  /// The cached verdict, while it may still stand in for the platform; the
  /// unconfirmed gate once it may not; null when there is nothing cached.
  LicenseEntitlement? fromCache(DateTime now) {
    final verdict = this.verdict;
    final at = checkedAt;
    if (verdict == null || at == null) return null;
    // A clock moved backwards since the check reads as inside the window:
    // the platform still enforces every money write, and a till refusing to
    // open over its own clock correction helps nobody.
    if (now.difference(at) > verdict.trustFor) {
      return OnlineVerdict.unconfirmed(at);
    }
    return verdict.entitlement(now);
  }

  static LicenceCheckRecord? tryParse(Map<String, Object?> json) {
    final raw = json['verdict'];
    return LicenceCheckRecord(
      enforcement: json['enforcement'] is String
          ? json['enforcement'] as String
          : null,
      verdict: raw is Map ? OnlineVerdict.tryParse(raw.cast()) : null,
      checkedAt: json['checked_at'] is String
          ? DateTime.tryParse(json['checked_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toJson() => {
    'enforcement': enforcement,
    'verdict': verdict?.toJson(),
    'checked_at': checkedAt?.toUtc().toIso8601String(),
  };
}
