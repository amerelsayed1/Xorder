/// Where this terminal's authoritative server lives.
///
/// On-premises is deliberately **a configuration choice, not a second product**.
/// All three modes talk to the same Laravel API, over the same contracts, backed
/// by the same schema — `apps/api` already ships a `docker-compose.yml`
/// (app + scheduler + web + postgres) and already runs on SQLite or Postgres
/// interchangeably. A branch box is therefore packaging, not new engineering.
///
/// See `docs/pos/08-deployment-modes.md` for the reasoning and the trade-offs.
enum DeploymentMode {
  /// Terminals talk to the hosted platform. Outages are absorbed by each
  /// terminal's own queue.
  cloud('cloud'),

  /// A server inside the branch is the source of truth for every till on the
  /// LAN, and optionally syncs upstream when the internet is available.
  ///
  /// This is the mode that solves **multi-till consistency during an outage** —
  /// two offline tills cannot otherwise be stopped from seating the same table.
  /// That, not "offline support", is the honest reason to choose it.
  branchServer('branch_server'),

  /// Islanded: no server of its own, one till, local database only.
  ///
  /// **This is not "never contacts the platform".** Every client must be
  /// trackable from Super Admin (POS-BE-022), so an islanded terminal sells
  /// offline indefinitely but must check in within the window its licence
  /// grants. Missing that window blocks the *next* shift, never the open one —
  /// the same rule that governs licence expiry.
  standalone('standalone');

  /// Only the wire value lives on the enum. What an operator is *shown* is in
  /// `AppStrings`, reached through `app/labels.dart`: a mode is a fact about
  /// the deployment, and its name is a fact about the language the till was set
  /// up in. Keeping them apart is what let Arabic be added without touching
  /// this file's logic.
  const DeploymentMode(this.wire);

  final String wire;

  static DeploymentMode? fromWire(String? value) =>
      DeploymentMode.values.where((m) => m.wire == value).firstOrNull;

  /// Does this mode need an HTTP endpoint configured?
  bool get needsBaseUrl => this != DeploymentMode.standalone;

  /// Can this terminal reach the hosted platform *itself* — for licence
  /// refresh and the public QR menu?
  ///
  /// Only cloud talks to it directly. A branch server forwards on the till's
  /// behalf but does not proxy the platform to it, and an islanded terminal has
  /// no path at all — so both must tolerate a licence that cannot be
  /// re-validated on demand.
  bool get canReachPlatform => this == DeploymentMode.cloud;

  /// Does this mode rely on a periodic check-in rather than a continuous link?
  ///
  /// Cloud and branch-server terminals are continuously visible to Super Admin:
  /// one writes to the platform, the other forwards through a mandatory
  /// upstream. An islanded terminal is visible only when it checks in, which is
  /// why its licence carries a maximum offline window (POS-BE-022).
  bool get requiresPeriodicCheckIn => this == DeploymentMode.standalone;
}

/// When a terminal drains its outbound queue to the server.
///
/// This is a choice about when **money** moves, not about whether the platform
/// may know the till is alive: the heartbeat is automatic under both policies.
/// A manual-sync terminal that stopped reporting is still visibly stopped.
enum SyncPolicy {
  /// Drain continuously in the background, as soon as a connection allows.
  automatic('automatic'),

  /// Drain only when someone asks. The pending count stays on screen, and
  /// closing a shift always offers to drain first — an operator choosing when to
  /// sync must never be able to *forget* to.
  manual('manual');

  const SyncPolicy(this.wire);

  final String wire;

  static SyncPolicy? fromWire(String? value) =>
      SyncPolicy.values.where((p) => p.wire == value).firstOrNull;
}

/// Resolved endpoint configuration for this terminal.
class DeploymentConfig {
  const DeploymentConfig({
    required this.mode,
    this.baseUrl,
    this.upstreamUrl,
    this.tenantSlug,
    this.verifyTls = true,
    this.syncPolicy = SyncPolicy.automatic,
    this.databaseName = 'xorder_pos',
    this.databaseUser = 'pos_till',
    this.databasePort = 5432,
  });

  static const unconfigured = DeploymentConfig(mode: DeploymentMode.cloud);

  final DeploymentMode mode;

  /// The API this terminal writes to. Null only for [DeploymentMode.standalone].
  final String? baseUrl;

  /// Where a branch server forwards to when the internet is up.
  ///
  /// **Required for [DeploymentMode.branchServer].** An islanded branch server
  /// was previously offered and has been withdrawn: every client must be
  /// trackable from Super Admin (POS-BE-022), and a branch box that forwards
  /// nowhere is a whole restaurant the platform cannot see.
  final String? upstreamUrl;

  /// Needed because usernames are unique **per tenant**: the server resolves the
  /// tenant from this slug (or the Host subdomain) at login.
  final String? tenantSlug;

  /// A branch box on a LAN often has no public certificate. Allowing a private
  /// address to be trusted is a decision the operator must make explicitly in
  /// the wizard, never a silent default — see [allowsInsecureTransport].
  final bool verifyTls;

  /// The database on the branch server. Set in the setup wizard.
  ///
  /// Not secret, so it lives here in device config alongside the endpoint. The
  /// **password does not** — it goes to the OS keystore through
  /// `PosDbCredentials`, and is deliberately absent from [toJson].
  final String databaseName;

  /// The login role. Defaults to `pos_till`, which is granted `SELECT` and
  /// `INSERT` on the POS tables and nothing else — never a superuser.
  final String databaseUser;

  final int databasePort;

  /// When this terminal drains its queue. Every mode is offline-first — there is
  /// no online-required variant, because a desktop till always has a disk and
  /// refusing to sell without a connection buys the restaurant nothing.
  final SyncPolicy syncPolicy;

  bool get isConfigured {
    if (mode.needsBaseUrl && (baseUrl?.isEmpty ?? true)) return false;
    // A branch server with nowhere to forward to is not a configuration, it is
    // an invisible restaurant. See [upstreamUrl].
    if (mode == DeploymentMode.branchServer && (upstreamUrl?.isEmpty ?? true)) return false;
    return true;
  }

  /// True when this endpoint is a private/loopback address, i.e. a box on the
  /// same LAN. Only such a host may ever be exempted from TLS verification.
  bool get isPrivateHost {
    final host = Uri.tryParse(baseUrl ?? '')?.host ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.local')) return true;

    final octets = host.split('.');
    if (octets.length != 4) return false;
    final first = int.tryParse(octets.first);
    final second = int.tryParse(octets[1]);
    if (first == null || second == null) return false;

    // RFC 1918 plus loopback.
    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }

  /// Refuse to skip certificate checks against a public host. A cashier
  /// mistyping a hostname must not silently downgrade the till to plaintext.
  bool get allowsInsecureTransport => !verifyTls && isPrivateHost;

  DeploymentConfig copyWith({
    DeploymentMode? mode,
    String? baseUrl,
    String? upstreamUrl,
    String? tenantSlug,
    bool? verifyTls,
    SyncPolicy? syncPolicy,
    String? databaseName,
    String? databaseUser,
    int? databasePort,
  }) =>
      DeploymentConfig(
        mode: mode ?? this.mode,
        baseUrl: baseUrl ?? this.baseUrl,
        upstreamUrl: upstreamUrl ?? this.upstreamUrl,
        tenantSlug: tenantSlug ?? this.tenantSlug,
        verifyTls: verifyTls ?? this.verifyTls,
        syncPolicy: syncPolicy ?? this.syncPolicy,
        databaseName: databaseName ?? this.databaseName,
        databaseUser: databaseUser ?? this.databaseUser,
        databasePort: databasePort ?? this.databasePort,
      );

  Map<String, Object?> toJson() => {
        'mode': mode.wire,
        'base_url': baseUrl,
        'upstream_url': upstreamUrl,
        'tenant_slug': tenantSlug,
        'verify_tls': verifyTls,
        'sync_policy': syncPolicy.wire,
        'database_name': databaseName,
        'database_user': databaseUser,
        'database_port': databasePort,
        // The database password is deliberately absent. It belongs in the OS
        // keystore, not in a config file a support engineer might email.
      };

  static DeploymentConfig fromJson(Map<String, Object?> json) => DeploymentConfig(
        mode: DeploymentMode.fromWire(json['mode'] as String?) ?? DeploymentMode.cloud,
        baseUrl: json['base_url'] as String?,
        upstreamUrl: json['upstream_url'] as String?,
        tenantSlug: json['tenant_slug'] as String?,
        verifyTls: json['verify_tls'] as bool? ?? true,
        // An unknown policy from a newer build falls back to automatic rather
        // than throwing: a till must boot even holding a config it half-knows.
        syncPolicy: SyncPolicy.fromWire(json['sync_policy'] as String?) ?? SyncPolicy.automatic,
        databaseName: json['database_name'] as String? ?? 'xorder_pos',
        databaseUser: json['database_user'] as String? ?? 'pos_till',
        databasePort: json['database_port'] as int? ?? 5432,
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
