/// Where this terminal's authoritative server lives.
///
/// On-premises is deliberately **a configuration choice, not a second product**.
/// Both modes talk to the same Laravel API, over the same contracts, backed by
/// the same schema — `apps/api` already ships a `docker-compose.yml`
/// (app + scheduler + web + postgres) and already runs on SQLite or Postgres
/// interchangeably. A branch box is therefore packaging, not new engineering.
///
/// See `docs/pos/08-deployment-modes.md` for the reasoning and the trade-offs.
enum DeploymentMode {
  /// Terminals keep a local PostgreSQL of their own and sync it to the hosted
  /// platform. Outages are absorbed by the local database and the outbound
  /// queue; the [SyncPolicy] decides when that queue drains.
  cloud('cloud'),

  /// PostgreSQL is the source of truth and sales never leave the building.
  ///
  /// **This is not "never contacts the platform".** An offline terminal still
  /// reaches the hosted platform to activate and renew its licence, and must do
  /// so inside the window that licence grants (POS-BE-022). Missing the window
  /// blocks the *next* shift, never the open one — the same rule that governs
  /// licence expiry. What it never sends is money.
  ///
  /// Whether that database sits on this machine or on a box shared by several
  /// tills is **not a mode**, it is [DeploymentConfig.databaseHost] — and which
  /// of the two is permitted comes from the licence's `max_terminals`.
  offline('offline');

  /// Only the wire value lives on the enum. What an operator is *shown* is in
  /// `AppStrings`, reached through `app/labels.dart`: a mode is a fact about
  /// the deployment, and its name is a fact about the language the till was set
  /// up in. Keeping them apart is what let Arabic be added without touching
  /// this file's logic.
  const DeploymentMode(this.wire);

  final String wire;

  /// Wire values that predate the two-mode model.
  ///
  /// `branch_server` and `standalone` were the same mode all along — one with
  /// PostgreSQL on a LAN box, one with PostgreSQL on the till itself. They must
  /// keep parsing, because **already-signed licences carry these strings in
  /// their `modes[]` claim and cannot be re-signed**, and because a terminal
  /// upgrading in place reads a `config.json` written by the old build. A
  /// terminal that rejected either would be a till that will not boot.
  static const _legacy = <String, DeploymentMode>{
    'branch_server': DeploymentMode.offline,
    'standalone': DeploymentMode.offline,
  };

  static DeploymentMode? fromWire(String? value) {
    if (value == null) return null;
    for (final mode in DeploymentMode.values) {
      if (mode.wire == value) return mode;
    }
    return _legacy[value];
  }

  /// Does this mode need an HTTP endpoint configured?
  bool get needsBaseUrl => this == DeploymentMode.cloud;

  /// Does this terminal send **money** to the hosted platform?
  ///
  /// Only cloud does. An offline terminal reaches the platform for its licence
  /// and nothing else, which is why [SyncPolicy] is a cloud-only question: there
  /// is no queue to drain on a till whose sales stay in the building.
  bool get syncsSalesToPlatform => this == DeploymentMode.cloud;

  /// Does this mode rely on a periodic check-in rather than a continuous link?
  ///
  /// A cloud terminal is continuously visible to Super Admin because it writes
  /// there. An offline terminal is visible only when it renews, which is why its
  /// licence carries a maximum offline window (POS-BE-022).
  bool get requiresPeriodicCheckIn => this == DeploymentMode.offline;
}

/// When a terminal drains its outbound queue to the platform.
///
/// Only meaningful in [DeploymentMode.cloud]. This is a choice about when
/// **money** moves, not about whether the platform may know the till is alive:
/// licence renewal happens under both policies.
enum SyncPolicy {
  /// Drain continuously in the background, as soon as a connection allows.
  automatic('automatic'),

  /// Drain only when someone asks. The pending count stays on screen, and
  /// closing a shift always offers to drain first — an operator choosing when to
  /// sync must never be able to *forget* to.
  manual('manual');

  const SyncPolicy(this.wire);

  final String wire;

  static SyncPolicy? fromWire(String? value) => switch (value) {
    // The platform's word for the continuous policy (owner decision
    // 2026-08-26: policies are dynamic/manual). The till's own persisted
    // configs say `automatic`; both must keep parsing forever.
    'dynamic' => SyncPolicy.automatic,
    _ => SyncPolicy.values.where((p) => p.wire == value).firstOrNull,
  };
}

/// Whether this terminal is the restaurant's main device or a child of one
/// (`docs/pos/10-setup-architecture.md` §9).
///
/// **A tablet is always a child** (owner decision, 2026-09-12). It was being
/// walked through the desktop wizard — licence key, database build, first
/// owner — none of which a tablet should own: it is carried round the floor,
/// it holds no database, and a licence activated on it pinned the restaurant's
/// licence to the one device most likely to walk out of the building.
///
/// A child therefore answers none of those questions. It points at the main
/// device's PostgreSQL, **uses the licence the main device published there**,
/// signs in with a manager who already exists, and registers itself as one
/// more of the licence's terminals. The mode is the main device's too.
enum TerminalRole {
  /// Holds the site's database, activates the licence and builds the schema.
  /// Every desktop till is one today, including the single-till shape.
  main('main_device'),

  /// Sells through a main device's database and licence.
  child('client_terminal');

  const TerminalRole(this.wire);

  final String wire;

  /// Unknown or absent reads as [main]: every config written before this
  /// field existed belongs to a till that set itself up as one.
  static TerminalRole fromWire(String? value) =>
      value == child.wire ? child : main;
}

/// Resolved endpoint configuration for this terminal.
class DeploymentConfig {
  const DeploymentConfig({
    required this.mode,
    this.baseUrl,
    this.licenceServerUrl,
    this.tenantSlug,
    this.verifyTls = true,
    this.syncPolicy = SyncPolicy.automatic,
    this.databaseHost = localhost,
    this.databaseName = 'xorder_pos',
    this.databaseUser = 'pos_till',
    this.adminDatabaseUser = 'pos_admin',
    this.databasePort = 5432,
    this.role = TerminalRole.main,
  });

  /// The host of a database running on the till itself — the single-terminal
  /// shape, and the default for every new install.
  static const localhost = 'localhost';

  static const unconfigured = DeploymentConfig(mode: DeploymentMode.cloud);

  final DeploymentMode mode;

  /// The platform this terminal syncs to. Null in [DeploymentMode.offline].
  final String? baseUrl;

  /// Where this terminal fetches and renews its LICENCE, when it should not be
  /// the build's default (`PlatformEndpoint.base`).
  ///
  /// Null on almost every till, and that is the intended state: the address is
  /// shown on the licence step so an installer can *see* which platform is
  /// being asked, and typed over only when it is genuinely the wrong one — a
  /// staging box, a developer's own stack, a key issued from somewhere else.
  ///
  /// **Editable without weakening anything.** Every licence is Ed25519-signed
  /// and verified against a public key compiled into this binary, so a hostile
  /// address cannot produce one that passes — the most it can hand over is
  /// bytes, which "Activate from file" already accepts from anybody. The URL
  /// decides where the file comes from; the signature decides whether it counts.
  final String? licenceServerUrl;

  /// Needed because usernames are unique **per tenant**: the server resolves the
  /// tenant from this slug (or the Host subdomain) at login.
  ///
  /// Since the licence step runs *before* connection, this is normally supplied
  /// by the licence rather than typed — a licence is issued to exactly one
  /// tenant, so asking the operator to name it again invites a mismatch.
  final String? tenantSlug;

  /// A database on a LAN box often has no public certificate. Allowing a private
  /// address to be trusted is a decision the operator must make explicitly in
  /// the wizard, never a silent default — see [allowsInsecureTransport].
  final bool verifyTls;

  /// Where this terminal's PostgreSQL lives.
  ///
  /// **Every mode has one.** [localhost] is the single-till shape; a LAN address
  /// is the shared-database shape, and the licence's `max_terminals` is what
  /// decides whether the operator may choose the latter. The mode does not.
  final String databaseHost;

  /// The database name. Not secret, so it lives here in device config alongside
  /// the endpoint. The **password does not** — it goes to the OS keystore
  /// through `PosDbCredentials`, and is deliberately absent from [toJson].
  final String databaseName;

  /// The login role. Defaults to `pos_till`, which is granted `SELECT` and
  /// `INSERT` on the POS tables and nothing else — never a superuser.
  final String databaseUser;

  /// The role the Management section connects as.
  ///
  /// Deliberately NOT [databaseUser]. `bin/pos_migrate.dart` refuses to grant
  /// both sets to one role and says why: the till credential sits on a machine
  /// in a public room, often with its password in a file beside it, and it must
  /// not be able to reprice the menu or reset a PIN. That boundary existed only
  /// in the CLI until now — the app held one credential and did Management's
  /// writes as the till.
  ///
  /// Not secret, so it lives here in device config. Its PASSWORD is never
  /// stored: it is asked for when somebody opens Management and kept in memory
  /// for that session only.
  final String adminDatabaseUser;

  final int databasePort;

  /// Main device or child. See [TerminalRole].
  final TerminalRole role;

  bool get isChild => role == TerminalRole.child;

  /// When this terminal drains its queue. Every mode is offline-first — there is
  /// no online-required variant, because a desktop till always has a disk and
  /// refusing to sell without a connection buys the restaurant nothing.
  ///
  /// Ignored in [DeploymentMode.offline], where nothing drains.
  final SyncPolicy syncPolicy;

  /// True when this terminal's database is on the machine it is running on.
  bool get isSingleMachine =>
      databaseHost == localhost ||
      databaseHost == '127.0.0.1' ||
      databaseHost.isEmpty;

  /// True when the database is reached over the loopback interface.
  ///
  /// Narrower than [isSingleMachine], which counts an empty host as "this
  /// machine" for the benefit of the wizard's copy. An empty host is not a
  /// destination and must never earn a transport concession.
  bool get isLoopback {
    final host = databaseHost.trim();
    return host == localhost || host == '127.0.0.1' || host == '::1';
  }

  /// Whether [databaseName] may be quoted into DDL as an identifier.
  ///
  /// The canonical rule, here rather than in the bootstrap that runs the DDL,
  /// because the WIZARD has to be able to apply it at the point of typing. It
  /// used to live only where `CREATE DATABASE "x"` is built, so a hyphen typed
  /// on the connection screen surfaced five steps later as a raw ArgumentError
  /// about bind parameters, in the operator's error bar.
  static bool isPlainIdentifier(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

  /// A cloud API is allowed to use plaintext only on the local/LAN addresses
  /// that an installer can reasonably operate without a certificate.  Login
  /// passwords and device bearer tokens otherwise travel with every request,
  /// so accepting an explicit `http://public-host` is not a harmless override.
  static bool isPermittedPlatformUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    return _isPrivateNetworkHost(uri.host);
  }

  static bool _isPrivateNetworkHost(String rawHost) {
    final host = rawHost.toLowerCase();
    if (host == localhost || host == '::1' || host.endsWith('.local')) {
      return true;
    }

    final octets = host.split('.');
    if (octets.length != 4) return false;
    final first = int.tryParse(octets[0]);
    final second = int.tryParse(octets[1]);
    if (first == null || second == null) return false;
    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }

  bool get hasValidDatabaseName => isPlainIdentifier(databaseName);

  bool get isConfigured {
    // A child of a cloud main device has no platform address of its own and
    // needs none: its sales go into the main device's database, and the main
    // device's outbox drain is what carries them up.
    if (mode.needsBaseUrl &&
        !isChild &&
        !isPermittedPlatformUrl(baseUrl)) {
      return false;
    }
    // Every mode reads and writes PostgreSQL, so a terminal with nowhere to
    // find it is not a configuration.
    if (databaseHost.trim().isEmpty) return false;
    return true;
  }

  /// True when the database is on a private/loopback address, i.e. this machine
  /// or a box on the same LAN. Only such a host may ever skip TLS.
  bool get isPrivateHost {
    final host = databaseHost.trim();
    if (host.isEmpty) return false;
    if (host == localhost || host.endsWith('.local')) return true;

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
  ///
  /// [isLoopback] needs no such decision and is never offered one. Traffic to
  /// 127.0.0.1 does not reach a network interface, so there is no path to
  /// intercept and nothing for TLS to protect — while *demanding* it would mean
  /// every single-till install had to issue itself a certificate to talk to
  /// itself. A stock PostgreSQL ships `ssl = off`, so requiring TLS here
  /// hardened nothing and instead made the commonest deployment there is — one
  /// machine, one database — unable to connect at all, with no control in the
  /// wizard to relax it, because the operator is only asked about certificates
  /// when they have typed a *LAN* address.
  ///
  /// A LAN address is a different question and keeps its explicit decision:
  /// that traffic crosses a switch other people can reach.
  bool get allowsInsecureTransport =>
      isLoopback || (!verifyTls && isPrivateHost);

  DeploymentConfig copyWith({
    DeploymentMode? mode,
    String? baseUrl,
    String? licenceServerUrl,
    String? tenantSlug,
    bool? verifyTls,
    SyncPolicy? syncPolicy,
    String? databaseHost,
    String? databaseName,
    String? databaseUser,
    String? adminDatabaseUser,
    int? databasePort,
    TerminalRole? role,

    /// Forget the tenant rather than keep it — `tenantSlug: null` cannot say
    /// that, since null means "leave it alone". Needed where a tenant that was
    /// itself read off a licence must not outlive that licence.
    bool clearTenantSlug = false,

    /// Blanking the field returns this terminal to the build's own default.
    bool clearLicenceServerUrl = false,
  }) => DeploymentConfig(
    mode: mode ?? this.mode,
    baseUrl: baseUrl ?? this.baseUrl,
    licenceServerUrl: clearLicenceServerUrl
        ? null
        : (licenceServerUrl ?? this.licenceServerUrl),
    tenantSlug: clearTenantSlug ? null : (tenantSlug ?? this.tenantSlug),
    verifyTls: verifyTls ?? this.verifyTls,
    syncPolicy: syncPolicy ?? this.syncPolicy,
    databaseHost: databaseHost ?? this.databaseHost,
    databaseName: databaseName ?? this.databaseName,
    databaseUser: databaseUser ?? this.databaseUser,
    adminDatabaseUser: adminDatabaseUser ?? this.adminDatabaseUser,
    databasePort: databasePort ?? this.databasePort,
    role: role ?? this.role,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.wire,
    'base_url': baseUrl,
    // Kept across restarts because RENEWAL uses it too: a till activated
    // against a staging platform must not silently renew against
    // production nine months later.
    'licence_server_url': licenceServerUrl,
    'tenant_slug': tenantSlug,
    'verify_tls': verifyTls,
    'sync_policy': syncPolicy.wire,
    'database_host': databaseHost,
    'database_name': databaseName,
    'database_user': databaseUser,
    'admin_database_user': adminDatabaseUser,
    'database_port': databasePort,
    'role': role.wire,
    // The database password is deliberately absent. It belongs in the OS
    // keystore, not in a config file a support engineer might email.
  };

  static DeploymentConfig fromJson(Map<String, Object?> json) {
    final mode =
        DeploymentMode.fromWire(json['mode'] as String?) ??
        DeploymentMode.cloud;
    final baseUrl = json['base_url'] as String?;

    return DeploymentConfig(
      mode: mode,
      // A config written by the old build has no `base_url` in offline mode, and
      // the branch-server variant used it for *both* the API and the database.
      baseUrl: mode.needsBaseUrl ? baseUrl : null,
      // Unlike `base_url` this is NOT mode-dependent: an offline terminal has
      // no platform address for anything else and still has to renew.
      licenceServerUrl: json['licence_server_url'] as String?,
      tenantSlug: json['tenant_slug'] as String?,
      verifyTls: json['verify_tls'] as bool? ?? true,
      // An unknown policy from a newer build falls back to automatic rather
      // than throwing: a till must boot even holding a config it half-knows.
      syncPolicy:
          SyncPolicy.fromWire(json['sync_policy'] as String?) ??
          SyncPolicy.automatic,
      databaseHost: _hostFromJson(json, mode: mode, baseUrl: baseUrl),
      databaseName: json['database_name'] as String? ?? 'xorder_pos',
      databaseUser: json['database_user'] as String? ?? 'pos_till',
      adminDatabaseUser: json['admin_database_user'] as String? ?? 'pos_admin',
      databasePort: json['database_port'] as int? ?? 5432,
      role: TerminalRole.fromWire(json['role'] as String?),
    );
  }

  /// Recover the database host from a config written before it had a field.
  ///
  /// The old `branch_server` mode kept its database on whatever host `base_url`
  /// pointed at, and the old `standalone` mode kept it on the till. Reading the
  /// host back out of `base_url` is what lets an existing branch install upgrade
  /// without an engineer retyping the address into every terminal.
  static String _hostFromJson(
    Map<String, Object?> json, {
    required DeploymentMode mode,
    required String? baseUrl,
  }) {
    final stored = (json['database_host'] as String?)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    if (mode.needsBaseUrl) return localhost;

    final host = Uri.tryParse(baseUrl ?? '')?.host ?? '';
    return host.isEmpty ? localhost : host;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
