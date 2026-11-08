import '../../../core/config/deployment.dart';

/// Why a licence is or is not usable.
enum LicenseState {
  /// Signed, in date, and matches this terminal.
  valid,

  /// Valid, but inside the renewal warning window.
  expiringSoon,

  /// Past `expiresAt` but inside the grace window. Trade continues.
  inGrace,

  /// Past expiry and past grace.
  expired,

  /// Clock is before `issuedAt` — usually a wrong system clock, occasionally a
  /// licence issued for a future term.
  notYetValid,

  /// No licence installed at all.
  missing,

  /// Malformed, or the signature does not verify against the embedded key.
  invalid,

  /// Correctly signed, but issued to a different tenant than this terminal is
  /// configured for.
  tenantMismatch,

  /// Correctly signed, but does not cover this deployment mode — e.g. a
  /// cloud-only licence installed on a branch server.
  modeNotLicensed,

  /// Correctly signed for BOTH modes, on an app that runs exactly one
  /// (pos-split-apps, D9). Nothing on the till can choose for the business,
  /// so the Super Admin reissues it for one mode. Only raised by an app with a
  /// fixed mode; the shared package without one accepts such a licence.
  modeAmbiguous,

  /// Correctly signed and bound to specific machines, none of which is this one.
  terminalNotLicensed,

  /// Suspended from the platform's dashboard (POS-BE-031, online check only).
  suspended,

  /// An online-checked till that could not reach the platform for longer than
  /// the verdict may be trusted offline (POS-BE-031).
  unconfirmed,
}

/// The signed claims inside a licence file.
class LicenseClaims {
  const LicenseClaims({
    required this.licenseId,
    required this.tenantSlug,
    required this.tenantName,
    required this.issuedAt,
    required this.expiresAt,
    this.graceDays = 14,
    this.warnDays = 30,
    this.maxTerminals = 1,
    this.maxUsers,
    this.features = const {},
    this.modes = const {DeploymentMode.cloud},
    this.fingerprints = const {},
    this.branchIds = const {},
    this.plan,
    this.maxOfflineDays,
    this.licenseVersion = 1,
  });

  /// The highest `license_version` this build understands.
  ///
  /// A licence claiming more is **evaluated, not denied** — see [licenseVersion].
  static const supportedVersion = 1;

  final String licenseId;
  final String tenantSlug;
  final String tenantName;
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// How long trade continues after expiry. Deliberately generous: the cost of
  /// a wrongly-blocked till is far higher than a fortnight of unpaid use.
  final int graceDays;

  /// How long before expiry the renewal banner appears.
  final int warnDays;

  /// Advisory offline — a fresh install cannot see its siblings. Only a server
  /// can actually count terminals, which is why POS-BE-016 exists.
  final int maxTerminals;

  /// How many people may hold an account on this customer's tills.
  ///
  /// **Enforceable here, unlike [maxTerminals].** A terminal cannot see its
  /// siblings, which is what makes the device count advisory — but every staff
  /// row lives in the one database this terminal is already reading, so the
  /// count is a fact it can check.
  ///
  /// Null means unlimited, and that reading is load-bearing in two directions:
  /// it is the correct value for a cloud licence (the platform counts staff
  /// against the tenant's plan, where it can be trusted), and it is what a
  /// licence signed before this claim existed must mean. Reading a missing cap
  /// as zero would lock every already-installed till out of adding anybody.
  final int? maxUsers;

  final Set<String> features;
  final Set<DeploymentMode> modes;

  /// Machine fingerprints this licence is pinned to. Empty means unpinned.
  final Set<String> fingerprints;

  /// Branches this licence covers. Empty means every branch of the tenant.
  final Set<int> branchIds;

  final String? plan;

  /// How long this terminal may go without reaching the platform (POS-BE-022).
  ///
  /// **Null means unlimited, and that is the correct value for cloud** — a cloud
  /// till writes to the platform continuously, so a check-in window would only
  /// ever fire on one that was already failing at something more important.
  /// Absent from a licence issued before the claim existed, which must keep
  /// meaning unlimited: reading a missing window as zero would expire every
  /// licence already in the field the moment a till was updated.
  ///
  /// Parsed here; the window is not yet enforced. Enforcement needs a durable
  /// "last reached the platform" timestamp, which arrives with the configuration
  /// cache — see `docs/pos/10-setup-architecture.md` §13.
  final int? maxOfflineDays;

  /// Schema version of the claims object — **not** a generation counter.
  ///
  /// Defaults to 1, which is what every licence signed so far implies by not
  /// carrying the key at all. A value above [supportedVersion] means the issuer
  /// knows claims this build does not, and the rule is to **evaluate what is
  /// understood rather than deny**: refusing would brick a till holding a
  /// licence issued for a newer build, which is the cardinal rule inverted.
  final int licenseVersion;

  /// True when this licence was issued against a claims schema newer than this
  /// build. Advisory — never a reason to refuse trade.
  bool get isNewerThanApp => licenseVersion > supportedVersion;

  DateTime get graceEndsAt => expiresAt.add(Duration(days: graceDays));

  static LicenseClaims fromJson(Map<String, Object?> json) => LicenseClaims(
    licenseId: json['license_id'] as String,
    tenantSlug: json['tenant_slug'] as String,
    tenantName: json['tenant_name'] as String? ?? '',
    issuedAt: DateTime.parse(json['issued_at'] as String),
    expiresAt: DateTime.parse(json['expires_at'] as String),
    graceDays: (json['grace_days'] as num?)?.toInt() ?? 14,
    warnDays: (json['warn_days'] as num?)?.toInt() ?? 30,
    maxTerminals: (json['max_terminals'] as num?)?.toInt() ?? 1,
    maxUsers: (json['max_users'] as num?)?.toInt(),
    features: {...?(json['features'] as List?)?.map((e) => '$e')},
    modes: {
      ...?(json['modes'] as List?)
          ?.map((e) => DeploymentMode.fromWire('$e'))
          .whereType<DeploymentMode>(),
    },
    fingerprints: {...?(json['fingerprints'] as List?)?.map((e) => '$e')},
    branchIds: {
      ...?(json['branch_ids'] as List?)
          ?.map((e) => int.tryParse('$e'))
          .whereType<int>(),
    },
    plan: json['plan'] as String?,
    // Absent, null, or unparseable all mean unlimited. The server emits
    // this today; until now the client simply did not read it.
    maxOfflineDays: _int(json['max_offline_days']),
    licenseVersion: _int(json['license_version']) ?? 1,
  );

  /// Read an integer without trusting its type.
  ///
  /// `as num?` throws on a string, and `claimsOf` turns a throw into
  /// [LicenceFileDamaged] — a refusal to trade. These two claims are exactly
  /// the ones a *newer* issuer is most likely to send in a shape this build did
  /// not expect, so a wrong type here has to degrade to the default rather than
  /// take a business offline. Accepts a numeric string because JSON emitters
  /// disagree about large integers.
  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'license_id': licenseId,
    'tenant_slug': tenantSlug,
    'tenant_name': tenantName,
    'issued_at': issuedAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'grace_days': graceDays,
    'warn_days': warnDays,
    'max_terminals': maxTerminals,
    'max_users': maxUsers,
    'features': features.toList(),
    'modes': modes.map((m) => m.wire).toList(),
    'fingerprints': fingerprints.toList(),
    'branch_ids': branchIds.toList(),
    'plan': plan,
    'max_offline_days': maxOfflineDays,
    'license_version': licenseVersion,
  };
}

/// What the terminal may actually do, given the licence state.
///
/// **The governing rule: never brick a till mid-service.** A POS that refuses to
/// sell during Friday dinner because a licence lapsed does not collect the
/// renewal — it loses the customer, and possibly their unsynced takings with it.
///
/// So an expired licence stops the *next* shift from opening; it never
/// interrupts one already open, and cash-up, reprint and export are never gated
/// at all. Recovering your own money records is not a licensable feature.
class LicenseEntitlement {
  const LicenseEntitlement({
    required this.state,
    required this.canOpenShift,
    required this.canSell,
    required this.canChangeConfiguration,
    this.daysRemaining,
    this.notice,
  });

  final LicenseState state;
  final bool canOpenShift;

  /// Selling inside an already-open shift.
  final bool canSell;
  final bool canChangeConfiguration;

  /// Days until expiry; negative once past it. Null when there is no licence.
  final int? daysRemaining;

  /// What to tell the operator, as **data rather than a sentence**.
  ///
  /// The verifier decides what is wrong; only `app/labels.dart` puts it into
  /// words. That split is what lets a licence be evaluated in a unit test, on a
  /// headless issuing script, and in either language, from the same code — a
  /// hardcoded English string here would have made the Arabic till say
  /// "Licence expired" in the middle of an otherwise Arabic screen.
  final LicenceNotice? notice;

  /// Cash-up, X/Z and reprint are **always** permitted, whatever the licence
  /// says. This is a deliberate, non-negotiable carve-out.
  bool get canCashUp => true;
  bool get canReprint => true;
  bool get canExportData => true;

  bool get isBlocking => !canSell;
  bool get needsAttention => state != LicenseState.valid;
}

/// Why a licence is in the state it is in.
///
/// One case per thing that can be wrong, each carrying the facts the sentence
/// needs — never the sentence itself. See [LicenseEntitlement.notice].
sealed class LicenceNotice {
  const LicenceNotice();
}

/// Valid, but inside the warning window the licence itself sets.
final class LicenceExpiresIn extends LicenceNotice {
  const LicenceExpiresIn(this.days);
  final int days;
}

/// Past expiry, still trading on the grace the licence grants.
final class LicenceInGrace extends LicenceNotice {
  const LicenceInGrace(this.daysLeft);
  final int daysLeft;
}

/// Past grace. The next shift cannot open; the open one is never cut off.
final class LicenceExpired extends LicenceNotice {
  const LicenceExpired();
}

/// Issued to one business, installed on a terminal set up for another. Names
/// both sides, because an installer holding the wrong file needs to know which
/// file they should have been holding.
final class LicenceTenantMismatch extends LicenceNotice {
  const LicenceTenantMismatch({
    required this.licenceTenant,
    required this.terminalTenant,
  });
  final String licenceTenant;
  final String terminalTenant;
}

final class LicenceModeNotCovered extends LicenceNotice {
  const LicenceModeNotCovered(this.mode, {this.fixedApp = false});

  /// The mode this terminal runs and the licence does not cover.
  final DeploymentMode mode;

  /// True when the mode is the app's, not a choice (pos-split-apps, BR-2).
  /// The sentence then names the app the licence IS for, because the fix is
  /// to install that one rather than to ask for another licence.
  final bool fixedApp;
}

/// Signed for both modes on an app that runs one — see
/// [LicenseState.modeAmbiguous].
final class LicenceCoversBothModes extends LicenceNotice {
  const LicenceCoversBothModes();
}

final class LicenceOtherTerminal extends LicenceNotice {
  const LicenceOtherTerminal();
}

/// Almost always a wrong system clock, so the words say so rather than
/// "not yet valid" — which sends a cashier to the wrong person.
final class LicenceNotYetValid extends LicenceNotice {
  const LicenceNotYetValid(this.startsOn);
  final DateTime startsOn;
}

final class LicenceFileDamaged extends LicenceNotice {
  const LicenceFileDamaged();
}

/// The signature did not verify against the key this build holds.
///
/// Two very different things look like this from the outside, and the file's
/// `key_id` tells them apart. A file whose key id names a key this build does
/// not hold was issued by a platform or release channel this build was not
/// made for — a debug till pointed at production, a release till handed a
/// licence from a staging issuer — and the licence itself is perfectly good.
/// A file whose key id names the key this build DOES hold, and still fails,
/// has been edited. The wording follows, because "ask your supplier to reissue
/// it" is the wrong advice for the first: the issuer would mint the same file
/// again, signed with the same key this build still cannot read.
final class LicenceUnverifiable extends LicenceNotice {
  const LicenceUnverifiable({this.signedWith, this.holds});

  /// The `key_id` the file says signed it.
  final String? signedWith;

  /// The key id this build verifies with; null where the caller has no idea.
  final String? holds;

  /// Whether the two name different keys.
  bool get otherKey =>
      signedWith != null && holds != null && signedWith != holds;
}

final class LicenceMissing extends LicenceNotice {
  const LicenceMissing();
}

/// Asked to check a key when nothing exists to check it against. Saying "that
/// key was not recognised" would send the operator hunting for a typo.
final class NoLicenceServer extends LicenceNotice {
  const NoLicenceServer();
}

final class NotALicenceFile extends LicenceNotice {
  const NotALicenceFile();
}

/// The platform answered, and it does not know this key.
///
/// **Names the address it asked.** A key is issued by one platform and checked
/// against whichever one this build points at — and those are not always the
/// same box. A till built for production, handed a key minted on a local or
/// staging stack, will get a truthful 404 and used to report it as "that key
/// was not recognised", which sends an installer hunting for a typo in a key
/// that is perfectly good. The address is the thing that ends that hunt.
final class LicenceKeyNotRecognised extends LicenceNotice {
  const LicenceKeyNotRecognised([this.address]);

  /// The platform that refused it, or null when this build has none.
  final String? address;
}

/// The platform could not be reached at all — no route, no DNS, refused
/// connection, timeout. Nothing was learned about the key.
final class LicenceServerUnreachable extends LicenceNotice {
  const LicenceServerUnreachable(this.address);

  final String address;
}

/// Reached, and it answered with something that is neither a licence nor a
/// plain "no such key" — a 500, a proxy error page, an HTML login screen.
/// Carries the status because that is what makes it diagnosable at all.
final class LicenceServerRefused extends LicenceNotice {
  const LicenceServerRefused(this.address, this.status);

  final String address;
  final int status;
}

/// Suspended from the platform's dashboard (POS-BE-031). The reason, when the
/// operator gave one, is shown as they wrote it.
final class LicenceSuspended extends LicenceNotice {
  const LicenceSuspended([this.reason]);
  final String? reason;
}

/// The online verdict is older than the till may trust it, and the platform
/// cannot be reached to renew it (POS-BE-031).
final class LicenceUnconfirmed extends LicenceNotice {
  const LicenceUnconfirmed(this.lastConfirmed);
  final DateTime lastConfirmed;
}

/// The platform answered, and it has no live licence for this business.
final class LicenceNotIssued extends LicenceNotice {
  const LicenceNotIssued();
}

/// The platform's own verdict that the term has not begun. Unlike
/// [LicenceNotYetValid], this is not a clock problem: the server judged it.
final class LicenceNotStarted extends LicenceNotice {
  const LicenceNotStarted(this.startsOn);
  final DateTime startsOn;
}

/// The platform knows this licence and has withdrawn it. A commercial fact,
/// not a typo, so the words must not send anyone looking for one.
final class LicenceRevoked extends LicenceNotice {
  const LicenceRevoked();
}

/// The platform knows this licence and it is not withdrawn, but it covers a
/// fixed number of devices and every seat is already used by another device.
///
/// Not [LicenceRevoked] (nothing was withdrawn) and not "key not recognised"
/// (the key is right): an installer told either goes looking for a problem that
/// is not there. The fix is commercial or administrative — release the old
/// device, or buy another seat — so the words say whom to ask.
final class LicenceSeatsFull extends LicenceNotice {
  const LicenceSeatsFull(this.seats);

  /// How many devices the licence covers, when the platform said.
  final int? seats;
}

/// Throttled. The activation endpoint allows a handful of attempts per key per
/// minute, so an installer retrying a key they believe in will hit it — and
/// being told "not recognised" at that point is the opposite of the truth.
final class TooManyLicenceAttempts extends LicenceNotice {
  const TooManyLicenceAttempts();
}
