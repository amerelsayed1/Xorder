import 'lan_tls.dart';

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

  /// The name of the app that runs this mode (pos-split-apps, D4).
  ///
  /// One app per mode since 2026-11-08: "XOrder POS - Cloud" and "XOrder POS -
  /// Offline". English only, in the Arabic interface too (D8), which is why
  /// this sits on the enum beside [wire] and not in `AppStrings`: it is the
  /// product's name, not a translation of the mode.
  String get productName => switch (this) {
    DeploymentMode.cloud => 'XOrder POS - Cloud',
    DeploymentMode.offline => 'XOrder POS - Offline',
  };

  /// The mode the *other* app runs, for a message that has to name it.
  DeploymentMode get other => switch (this) {
    DeploymentMode.cloud => DeploymentMode.offline,
    DeploymentMode.offline => DeploymentMode.cloud,
  };
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

/// Whether this terminal is the business's main device or a child of one
/// (`docs/pos/10-setup-architecture.md` §9).
///
/// **A tablet is always a child** (owner decision, 2026-09-12). It was being
/// walked through the desktop wizard — licence key, database build, first
/// owner — none of which a tablet should own: it is carried round the floor,
/// it holds no database, and a licence activated on it pinned the business's
/// licence to the one device most likely to walk out of the building.
///
/// A child therefore answers none of those questions. It points at the main
/// device's PostgreSQL, **uses the licence the main device published there**,
/// signs in with a manager who already exists, and registers itself as one
/// more of the licence's terminals. The mode is the main device's too.
///
/// **A desktop can be a child as well** (owner decision, 2026-09-22): the
/// Windows installer's "Till only" choice installs no PostgreSQL and leaves a
/// marker saying so — `install-role.json`, read by `deviceRoleProvider` — and
/// such a machine walks the same child path a tablet does. A desktop with no
/// marker is a main device, which is what every desktop was until then.
enum TerminalRole {
  /// Holds the site's database, activates the licence and builds the schema.
  /// Every desktop the installer gave a database, including the single-till
  /// shape.
  main('main_device'),

  /// Sells through a main device's database and licence: every tablet, and a
  /// desktop installed "Till only".
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
    this.allowInsecureLan = false,
    this.pinnedCertificateSha256,
    this.pinnedCertificatePem,
    this.syncPolicy = SyncPolicy.automatic,
    this.databaseHost = localhost,
    this.databaseName = defaultDatabaseName,
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

  /// A technician turned encryption off for this till's LAN database.
  ///
  /// **Off by default, and only ever turned on in Management › Devices**
  /// — behind `terminal.manage`, written to the audit ledger before it takes
  /// effect, and shown on the start screen for as long as it is on. Honoured
  /// for a private address only ([LanTls.decide]); a public host ignores it.
  ///
  /// It replaced `verify_tls`, the wizard's old "trust this database without
  /// a certificate" tick, which `fromJson` still reads so that a LAN till
  /// that was working in the clear before slice C keeps working — with the
  /// warning on — rather than stopping mid-service the morning it upgrades.
  final bool allowInsecureLan;

  /// The SHA-256 of the database server's certificate, as the technician
  /// confirmed it against the main device's Management pane. Lower-case hex.
  ///
  /// With [pinnedCertificatePem], the whole of what this till trusts on the
  /// LAN: not the platform's roots, not any other certificate. Not secret — a
  /// certificate is public by nature — so it lives here, in `config.json`.
  final String? pinnedCertificateSha256;

  /// The certificate itself, in PEM, because the driver can only be told to
  /// trust a certificate, not a fingerprint. See [PinnedCertificate].
  final String? pinnedCertificatePem;

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
  /// refusing to sell without a connection buys the business nothing.
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
  bool get isLoopback => LanTls.isLoopbackHost(databaseHost);

  /// Whether [databaseName] may be quoted into DDL as an identifier.
  ///
  /// The canonical rule, here rather than in the bootstrap that runs the DDL,
  /// because the WIZARD has to be able to apply it at the point of typing. It
  /// used to live only where `CREATE DATABASE "x"` is built, so a hyphen typed
  /// on the connection screen surfaced five steps later as a raw ArgumentError
  /// about bind parameters, in the operator's error bar.
  static bool isPlainIdentifier(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

  /// The name a database gets when nobody has named it — and nobody should
  /// have to. The Windows installer names the one it builds; everywhere else
  /// the wizard builds one, and before 16 Oct 2026 called every one of them
  /// `xorder_pos`, so a laptop that had set up two businesses had two tills
  /// fighting over one database.
  static const defaultDatabaseName = 'xorder_pos';

  /// `demo` → `demo_db`, `good-cafe` → `good_cafe_db`: the business's own
  /// short name, made a plain identifier, so the database reads as whose it
  /// is in any PostgreSQL tool. [defaultDatabaseName] when there is no
  /// business to name it after yet.
  static String databaseNameFor(String? tenantSlug) {
    final slug = (tenantSlug ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) return defaultDatabaseName;
    return '${RegExp(r'^[0-9]').hasMatch(slug) ? 't_$slug' : slug}_db';
  }

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
  bool get isPrivateHost => LanTls.isPrivateHost(databaseHost);

  /// How the connection to [databaseHost] is protected — the one decision
  /// `PosDatabase`, the bootstrap and the backup tools all read.
  LanTlsDecision get lanTls => LanTls.decide(
    host: databaseHost,
    allowInsecureLan: allowInsecureLan,
    pinnedSha256: pinnedCertificateSha256,
    pinnedPem: pinnedCertificatePem,
  );

  /// True while a technician's "encryption off" is in force on a LAN address:
  /// what the start screen's warning and the Management pane read.
  bool get isInsecureLan => lanTls.transport == LanTransport.insecureLan;

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
  /// that traffic crosses a switch other people can reach. See [lanTls].
  bool get allowsInsecureTransport => !lanTls.transport.encrypted;

  DeploymentConfig copyWith({
    DeploymentMode? mode,
    String? baseUrl,
    String? licenceServerUrl,
    String? tenantSlug,
    bool? allowInsecureLan,
    String? pinnedCertificateSha256,
    String? pinnedCertificatePem,
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

    /// Forget the paired certificate: a new address is a new server, and the
    /// pin belonged to the old one.
    bool clearPinnedCertificate = false,
  }) => DeploymentConfig(
    mode: mode ?? this.mode,
    baseUrl: baseUrl ?? this.baseUrl,
    licenceServerUrl: clearLicenceServerUrl
        ? null
        : (licenceServerUrl ?? this.licenceServerUrl),
    tenantSlug: clearTenantSlug ? null : (tenantSlug ?? this.tenantSlug),
    allowInsecureLan: allowInsecureLan ?? this.allowInsecureLan,
    pinnedCertificateSha256: clearPinnedCertificate
        ? null
        : (pinnedCertificateSha256 ?? this.pinnedCertificateSha256),
    pinnedCertificatePem: clearPinnedCertificate
        ? null
        : (pinnedCertificatePem ?? this.pinnedCertificatePem),
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
    'allow_insecure_lan': allowInsecureLan,
    'pinned_certificate_sha256': pinnedCertificateSha256,
    'pinned_certificate_pem': pinnedCertificatePem,
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
      // `verify_tls: false` was the pre-slice-C wizard's "trust without a
      // certificate", and on a LAN address it meant plaintext. Read as the
      // override it always was, so an upgraded child keeps selling — with the
      // start-screen warning now saying so — instead of failing its first
      // connection after the update. Absent, or true, is off.
      allowInsecureLan:
          json['allow_insecure_lan'] as bool? ??
          (json['verify_tls'] == false),
      pinnedCertificateSha256: LanTls.normaliseFingerprint(
        json['pinned_certificate_sha256'] as String?,
      ),
      pinnedCertificatePem: json['pinned_certificate_pem'] as String?,
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
