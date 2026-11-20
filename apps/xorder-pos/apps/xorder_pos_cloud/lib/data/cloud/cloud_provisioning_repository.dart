import 'dart:io';

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'bootstrap_bundle.dart';
import 'bootstrap_seeder.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:shared_module/core/config/app_version.dart';
import 'package:shared_module/data/cloud/device_token_vault.dart';
import 'package:shared_module/data/sql/sql.dart';

const _uuid = Uuid();

/// What the till reports about itself when it introduces itself.
String get _platformName => Platform.operatingSystem;


/// Terminal provisioning against the **hosted platform** (POS-BE-023) — the
/// cloud counterpart of `PostgresProvisioningRepository`, chosen in
/// `providers.dart` by deployment mode.
///
/// Both paths return the same [TerminalClaim] the wizard already consumes, and
/// both end with this machine holding its device token (POS-BE-011 Option C)
/// and, best-effort, a local database seeded from the bootstrap bundle the
/// claim carried. *Best-effort* is deliberate: at claim time the wizard may not
/// have configured PostgreSQL yet, and a claim that succeeded on the platform
/// must not be reported as failed because the local seed has to wait — the
/// first sync pass re-fetches the bundle and seeds it then.
class CloudProvisioningRepository implements ProvisioningRepository {
  const CloudProvisioningRepository({
    required this.api,
    required this.vault,
    required SqlDatabase database,
    required this.config,
    required this.fingerprint,
    this.installLicence,
  }) : _db = database;

  final PosCloudApi api;
  final DeviceTokenVault vault;
  final SqlDatabase _db;
  final DeploymentConfig config;

  /// The hashed installation identity, from the licensing feature — the same
  /// value licence pinning uses, so the platform sees one machine, not two.
  final Future<String> Function() fingerprint;

  /// Installs the licence the bootstrap bundle carries (POS-BE-015 §5 — "a
  /// provisioned terminal is licensed without anyone typing anything").
  /// Injected because verification and storage belong to the licensing
  /// feature; best-effort, because a licence that fails to install is a
  /// banner on the start screen, never a failed setup.
  final Future<void> Function(Map<String, Object?> licence)? installLicence;

  @override
  Future<ClaimResult> claimByCode({
    required String tenantSlug,
    required String code,
  }) async {
    final reply = await api.claimTerminal(
      tenantSlug: tenantSlug.trim().toLowerCase(),
      pairingCode: code.trim().toUpperCase(),
      platform: _platformName,
      appVersion: posAppVersion,
      fingerprint: await fingerprint(),
    );
    return _finishClaim(reply);
  }

  /// The owner's account, as the login reply names it: `data.role` is
  /// `RESTAURANT_ADMIN` for the owner and `RESTAURANT_STAFF` for everyone else
  /// (`UserResource`, xorder-cloud).
  static bool _isOwner(CloudReply login) =>
      login.data['role'] == 'RESTAURANT_ADMIN';

  static const _notOwner = ClaimResult(
    code: 'NOT_OWNER',
    message: 'Only the business owner can set up a till.',
  );

  @override
  Future<TenantConnection> connect({
    required String tenantSlug,
    required String username,
    required String password,
  }) async {
    final slug = tenantSlug.trim().toLowerCase();
    final login = await api.login(
      tenantSlug: slug,
      username: username.trim(),
      password: password,
    );
    if (login.offline) {
      return TenantConnection(
        code: 'PLATFORM_UNREACHABLE',
        message:
            '${api.baseUrl} could not be reached. Check the platform '
            'address on the Connection step, then try again.',
      );
    }

    // A server that answers sign-in with anything other than a verdict on the
    // credentials is the WRONG SERVER — an old build, a web app, a proxy. That
    // must never be reported as a wrong password: the operator would reset
    // credentials all afternoon while the address stays wrong. 401/403 are
    // genuine refusals; anything else names the host and the status.
    final jwt = login.body['token'] as String?;
    final credentialVerdict =
        login.status == 401 || login.status == 403 || login.status == 422;
    if (!login.ok && !credentialVerdict) {
      return TenantConnection(
        code: 'WRONG_PLATFORM',
        message:
            '${api.baseUrl} answered sign-in with HTTP ${login.status} — '
            'that does not look like the XOrder platform. Check the platform '
            'address on the Connection step.',
      );
    }
    if (!login.ok || jwt == null || jwt.isEmpty) {
      // One message for every genuine refusal — the wizard must not be usable
      // to learn which usernames exist (the server is equally careful).
      return const TenantConnection(
        code: 'CREDENTIALS_REJECTED',
        message:
            'That username and password were not accepted for this '
            'restaurant. Check all three with a manager.',
      );
    }

    // Only the owner sets up a cloud till (pos-cloud-sign-in-setup, D3). The
    // server would let any account holding `pos.provision` through; the till
    // is stricter, and stops here — before a branch or terminal is read — and
    // the token is dropped with this frame.
    if (!_isOwner(login)) {
      return const TenantConnection(
        code: 'NOT_OWNER',
        message: 'Only the business owner can set up a till.',
      );
    }

    // The tenant's display name rides the login response (UserResource
    // carries its business); read it tolerantly, fall back to the slug.
    String? tenantName;
    if (login.data['restaurant'] case final Map business) {
      final name = business['name'];
      if (name is String && name.isNotEmpty) tenantName = name;
    }

    final reply = await api.listBranches(jwt: jwt);
    if (!reply.ok) {
      return TenantConnection(
        code: reply.code ?? 'CONFIG_PULL_FAILED',
        message:
            reply.message ??
            'Signed in, but the branch list could not be fetched. Try again.',
      );
    }

    final branches = <PosBranch>[
      if (reply.body['data'] is List)
        for (final entry in reply.body['data'] as List)
          if (entry is Map) ?_branchFrom(entry.cast<String, Object?>()),
    ];
    if (branches.isEmpty) {
      // A tenant with no branches cannot host a till; saying so here beats a
      // branch step with nothing to choose and no explanation.
      return const TenantConnection(
        code: 'NO_BRANCHES',
        message:
            'This restaurant has no branches yet. Add one in the '
            'dashboard first.',
      );
    }

    // The terminals the tenant ALREADY has. Non-fatal: an empty or failed read
    // just means the terminal step offers only "create a new one", which is
    // exactly right for the first till at a brand-new tenant. Failing the
    // whole sign-in over it would block setup on a list that is an
    // optimisation, not a requirement.
    final terminals = <PosTerminalSummary>[];
    final fleet = await api.listTerminals(jwt: jwt);
    if (fleet.ok && fleet.body['data'] is List) {
      for (final entry in fleet.body['data'] as List) {
        if (entry is Map) {
          final summary = _terminalFrom(entry.cast<String, Object?>());
          if (summary != null) terminals.add(summary);
        }
      }
    }

    return TenantConnection(
      tenantName: tenantName ?? slug,
      branches: branches,
      // Adoptable first, then by name, so the list opens on what the operator
      // can actually pick rather than on tills already in service.
      terminals: terminals
        ..sort((a, b) {
          if (a.isAdoptable != b.isAdoptable) return a.isAdoptable ? -1 : 1;
          return a.name.compareTo(b.name);
        }),
    );
  }

  static PosTerminalSummary? _terminalFrom(Map<String, Object?> json) {
    final id = switch (json['id']) {
      final int value => value,
      final String value => int.tryParse(value),
      _ => null,
    };
    final name = json['name'];
    if (id == null || name is! String) return null;

    return PosTerminalSummary(
      id: id,
      name: name,
      branchId: switch (json['branch_id']) {
        final int value => value,
        final String value => int.tryParse(value),
        _ => null,
      },
      state: json['state'] as String? ?? 'provisioned',
    );
  }

  /// Adopt a terminal the dashboard already created, with staff credentials
  /// and no code typed by anyone.
  ///
  /// Issues a pairing code for the chosen row and immediately redeems it. The
  /// circularity is the point: claiming is the ONE audited path that turns a
  /// provisioned row into a claimed one — device token, bootstrap bundle,
  /// seat check, audit entry — so a till adopted from the wizard is
  /// indistinguishable on the server from one paired off a code read aloud.
  /// A second way to mint a device credential is a second way to get it wrong.
  @override
  Future<ClaimResult> adoptTerminal({
    required String tenantSlug,
    required String username,
    required String password,
    required int terminalId,
  }) async {
    final slug = tenantSlug.trim().toLowerCase();

    final login = await api.login(
      tenantSlug: slug,
      username: username.trim(),
      password: password,
    );
    if (login.offline) return _offline();
    final jwt = login.body['token'] as String?;
    if (!login.ok || jwt == null || jwt.isEmpty) {
      return const ClaimResult(
        code: 'CREDENTIALS_REJECTED',
        message: 'That username and password were not accepted.',
      );
    }
    if (!_isOwner(login)) return _notOwner;

    final issued = await api.issuePairingCode(jwt: jwt, terminalId: terminalId);
    if (issued.offline) return _offline();
    if (!issued.ok) return _refusal(issued);

    final code = issued.body['pairing_code'] as String?;
    if (code == null || code.isEmpty) {
      return const ClaimResult(
        code: 'CLAIM_UNREADABLE',
        message:
            'The platform issued a setup code this till could not read. '
            'Update the app, or pair with a code from the dashboard.',
      );
    }

    return claimByCode(tenantSlug: slug, code: code);
  }

  static PosBranch? _branchFrom(Map<String, Object?> json) {
    final id = switch (json['id']) {
      final int v => v,
      final String v => int.tryParse(v),
      _ => null,
    };
    if (id == null) return null;
    // BranchResource speaks bilingual columns (`name_en` / `name_ar`), the
    // bundle speaks `name` — accept all three so the two readers stay one.
    final name = [
      json['name'],
      json['name_en'],
      json['name_ar'],
    ].whereType<String>().where((value) => value.isNotEmpty).firstOrNull;
    return PosBranch(
      id: id,
      name: name ?? 'Branch $id',
      code: json['code'] is String && (json['code'] as String).isNotEmpty
          ? json['code'] as String
          : null,
      supportedOrderTypes: [
        if (json['supported_order_types'] is List)
          for (final type in json['supported_order_types'] as List)
            if (type is String) type,
      ],
    );
  }

  @override
  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
    // Unused: the platform already identifies this machine by the fingerprint
    // this repository was built with, so passing the raw id as well would be a
    // second, unhashed copy of the same identity on the wire.
    required String? installId,
  }) async {
    final slug = tenantSlug.trim().toLowerCase();

    final login = await api.login(
      tenantSlug: slug,
      username: username.trim(),
      password: password,
    );
    if (login.offline) return _offline();
    final jwt = login.body['token'] as String?;
    if (!login.ok || jwt == null || jwt.isEmpty) {
      // One message for every login failure, so the wizard cannot be used to
      // learn which usernames exist (the server is equally careful).
      return const ClaimResult(
        code: 'CREDENTIALS_REJECTED',
        message: 'That username and password were not accepted.',
      );
    }
    if (!_isOwner(login)) return _notOwner;

    // Idempotency per POS-BE-007: a register that times out and retries must
    // land on the same terminal row. One id per attempt-series, kept until
    // the platform has answered (accepted or refused) — the server replays a
    // known id instead of minting a second terminal. A fresh id on every call
    // is what let a dropped reply spend two seats (tablet-cloud-onboarding).
    final attempt = '$slug|$branchId|${terminalName.trim()}';
    final reply = await api.registerTerminal(
      jwt: jwt,
      clientTransactionId: _registrationIds.putIfAbsent(attempt, _uuid.v4),
      terminalName: terminalName.trim(),
      branchId: branchId,
      platform: _platformName,
      appVersion: posAppVersion,
      fingerprint: await fingerprint(),
    );
    // Only a reply that never arrived keeps the id for the retry.
    if (!reply.offline) _registrationIds.remove(attempt);
    return _finishClaim(reply);
  }

  /// The `client_transaction_id` of a registration whose answer has not been
  /// seen yet, by slug, branch and name.
  static final _registrationIds = <String, String>{};

  Future<ClaimResult> _finishClaim(CloudReply reply) async {
    if (reply.offline) return _offline();
    if (!reply.ok) return _refusal(reply);

    final token = reply.body['device_token'] as String?;
    final terminal = reply.body['terminal'] is Map
        ? (reply.body['terminal'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final bundle = BootstrapBundle.tryParse(reply.body['bootstrap']);

    final terminalId = terminal['id']?.toString();
    final branchId = switch (terminal['branch_id']) {
      final int id => id,
      final String id => int.tryParse(id),
      _ => null,
    };
    if (terminalId == null || branchId == null) {
      // A 2xx whose body this build cannot read is treated as a refusal, not a
      // crash — and crucially the token is NOT kept, because a token without a
      // terminal identity is a credential the till cannot account for.
      return const ClaimResult(
        code: 'CLAIM_UNREADABLE',
        message:
            'The platform answered in a shape this till does not '
            'understand. Update the app and try again.',
      );
    }

    if (token != null && token.isNotEmpty) {
      await vault.accept(token);
    }

    // Seed the local database from the bundle the claim carried — best effort,
    // see the class comment.
    final businessId = bundle?.business?.id;
    String? branchCode;
    String? branchName;
    final seeded = await _trySeed(bundle);

    // The bundle's licence embed, installed without anyone typing anything.
    final licence = bundle?.licence;
    if (licence != null && installLicence != null) {
      try {
        await installLicence!(licence);
      } on Object {
        // Best-effort by design — the start screen's licence gate reports the
        // state; a failed install here must not fail a successful claim.
      }
    }
    for (final branch in bundle?.branches ?? const <BootstrapBranch>[]) {
      if (branch.id == branchId) {
        branchCode = branch.code;
        branchName = branch.name;
      }
    }

    return ClaimResult(
      claim: TerminalClaim(
        terminalId: terminalId,
        terminalName: terminal['name']?.toString() ?? 'Terminal',
        branchId: branchId,
        branchName: branchName ?? 'Branch $branchId',
        // A branch the dashboard never gave a code still needs an invoice
        // prefix — same fallback the seeder documents: ugly on a receipt and
        // unmistakably a configuration gap, but never a till that cannot
        // finish setup over a blank field nobody knew mattered.
        branchCode: (branchCode?.isNotEmpty ?? false)
            ? branchCode
            : 'BR$branchId',
        businessId: businessId,
        syncPolicy:
            SyncPolicy.fromWire(terminal['sync_policy'] as String?) ??
            config.syncPolicy,
        // The cloud wizard no longer asks which language this till works in;
        // the business already told the dashboard.
        defaultLanguage: bundle?.business?.defaultLanguage,
      ),
      // Surfaced so the wizard can tell the operator the menu will arrive on
      // first sync rather than pretending it is already there.
      notices: _claimNotices(reply, seeded: seeded),
    );
  }

  /// Non-fatal facts the operator should hear about a successful claim.
  ///
  /// Returns codes, not prose. These were English sentences until 2026-09-16,
  /// and the wizard showed them as they arrived — so an Arabic till, claimed by
  /// an Arabic-speaking installer, read "Catalog will be fetched on first
  /// sync." The words now live in `AppStrings`; what belongs here is which
  /// thing happened. See [ClaimNotice].
  static List<ClaimNotice> _claimNotices(
    CloudReply reply, {
    required bool seeded,
  }) {
    final warnings = [
      if (reply.body['warnings'] is List)
        for (final w in reply.body['warnings'] as List)
          if (w is String) w,
    ];
    return [
      if (warnings.contains('MAX_TERMINALS_EXCEEDED'))
        ClaimNotice.overTerminalCount,
      if (!seeded) ClaimNotice.catalogueAtFirstSync,
    ];
  }

  /// Migrate then seed, swallowing database unavailability — the claim already
  /// succeeded on the platform and must be reported as such.
  Future<bool> _trySeed(BootstrapBundle? bundle) async {
    if (bundle == null || !bundle.seedable) return false;
    try {
      await PosMigrator(_db).migrate(config);
      final report = await BootstrapSeeder(
        database: _db,
        config: config,
      ).seed(bundle, force: true);
      return report.applied;
    } on Object {
      return false;
    }
  }

  ClaimResult _offline() => ClaimResult(
    code: 'PLATFORM_UNREACHABLE',
    message:
        '${api.baseUrl} could not be reached. Check the address and '
        'the connection, then try again.',
  );

  ClaimResult _refusal(CloudReply reply) {
    // Server codes pass through so the wizard can grow reactions; the messages
    // here cover the codes the contract names today (POS-BE-019).
    final message = switch (reply.code) {
      'PAIRING_CODE_INVALID' =>
        'That setup code was not recognised. Check it with whoever added this '
            'till in the dashboard.',
      'PAIRING_CODE_EXPIRED' =>
        'That setup code has expired. Issue a new one from the dashboard.',
      'PAIRING_CODE_USED' =>
        'That setup code has already been used. Issue a new one from the '
            'dashboard.',
      // The plan's terminal count is full. The fix is in the dashboard, not
      // on this machine, so say where to go rather than inviting a retry.
      'TERMINAL_SEAT_LIMIT' =>
        reply.message ??
            'This restaurant has no free terminal slots left. Revoke a till you '
                'no longer use in the dashboard, or move up a plan, then try '
                'again.',
      'SETUP_RATE_LIMITED' => 'Too many attempts. Wait a minute and try again.',
      'SETUP_SLUG_UNKNOWN' =>
        'No restaurant with that short name exists on the platform. Check the '
            'previous step.',
      // An unrecognised refusal names the server that produced it: a 404 on
      // the register route from the wrong host is indistinguishable from a
      // broken build otherwise.
      _ =>
        '${api.baseUrl} answered: ${reply.message ?? 'refused (${reply.status})'}',
    };
    return ClaimResult(code: reply.code ?? 'CLAIM_REFUSED', message: message);
  }
}
