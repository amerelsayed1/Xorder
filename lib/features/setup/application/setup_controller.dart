import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../core/config/terminal_config.dart';
import '../../../data/cloud/bootstrap_bundle.dart';
import '../../../data/cloud/bootstrap_seeder.dart';
import '../../../data/postgres/local_bootstrap.dart';
import '../../../domain/models/permissions.dart';
import '../../../data/postgres/pos_database.dart';
import '../../licensing/data/licence_service.dart';
import '../../licensing/domain/license.dart';
import '../domain/setup_state.dart';

const _uuid = Uuid();

/// Drives the first-run wizard.
///
/// Everything reachable from here goes through a repository interface, so the
/// wizard runs end to end today against fakes — the same property that lets the
/// rest of the POS be built while every backend contract is still `PROPOSED`.
class SetupController extends Notifier<SetupDraft> {
  /// Every refusal this wizard shows, on the console as well as on the screen.
  ///
  /// The operator gets one sentence, in their language, about what to do next —
  /// which is the right thing to show them and the wrong thing to debug from.
  /// This is the other half: which step it happened on, and what the raw cause
  /// was, in a log somebody can read after the fact. Routed through the single
  /// state setter so no future `copyWith(error: …)` can add a refusal that
  /// never reaches the log — the failure mode that made three of this
  /// afternoon's problems invisible.
  @override
  set state(SetupDraft value) {
    final message = value.error;
    if (message != null && message != stateOrNull?.error) {
      debugPrint('setup[${value.step.name}] refused: $message');
    }
    super.state = value;
  }

  /// Seeded from the saved configuration when there is one.
  ///
  /// There is one only when the terminal was set up and then sent back here —
  /// the keystore lost its password, or an engineer reset the till. Making them
  /// retype a branch, a database address and a terminal name that are already
  /// on disk is how a five-minute callout becomes an hour, so the wizard opens
  /// with all of it filled in and only the password blank.
  @override
  SetupDraft build() {
    ref.onDispose(() => _disposed = true);

    // A licence installed on an earlier run is still installed — it is a file,
    // and it outlived the process that wrote it. Reading it back is what stops
    // a restart mid-setup from asking for a licence this machine already holds.
    Future.microtask(_restoreInstalledLicence);

    final saved = ref.watch(terminalBootProvider).config;
    if (saved == null) {
      return SetupDraft(
        installationId: ref.read(terminalProfileProvider).installationId,
      );
    }

    return SetupDraft(
      locale: saved.languageCode,
      deployment: saved.deployment,
      branchId: saved.terminal.branchId,
      branchLabel: saved.terminal.branchName,
      restaurantId: saved.terminal.restaurantId,
      branchCode: saved.terminal.branchCode,
      terminalName: saved.terminal.terminalName ?? '',
      // Kept above all: reissuing it would hand the licence server a machine it
      // has never seen, and the activation on this till would stop matching.
      terminalId: saved.terminal.terminalId,
      installationId: saved.terminal.installationId,
      claimed: saved.terminal.provisioned,
    );
  }

  /// True once this controller has been disposed, so the licence restore — the
  /// one thing here that outlives its own build — cannot touch a dead state.
  bool _disposed = false;

  /// Adopt the licence already on this machine.
  ///
  /// Only ever fills a gap: an activation the operator performs while this is
  /// in flight wins, because that is the newer intent. A machine with no
  /// licence installed lands here and changes nothing.
  Future<void> _restoreInstalledLicence() async {
    if (_disposed || state.entitlement != null) return;

    final LicenceActivationResult result;
    try {
      result = await ref.read(licenceServiceProvider).restore(state.deployment);
    } catch (_) {
      // Nobody holds this future — it is started in a microtask so the wizard
      // can paint immediately — so anything the store throws surfaces as an
      // unhandled async error rather than as a failed step. The store already
      // reports a missing or unreadable file as `null`; what is left is the
      // platform refusing to say where the support directory is, which is not
      // a licensing problem and must not stop a wizard that works perfectly
      // well without a licence already on disk. Treat an unreachable store as
      // an empty one, which is precisely what this method does with `null`.
      return;
    }
    final first = result.entitlement;
    if (_disposed || first == null || state.entitlement != null) return;

    final claims = result.claims;
    // Same correction as the activation path: a licence restored from disk is
    // read before the operator has picked anything, so it must be judged on the
    // mode it grants rather than on the draft's default.
    final entitlement = await _judgeOnCoveredMode(
      first,
      claims == null ? state.deployment : _adopt(claims),
    );
    if (_disposed || state.entitlement != null) return;

    // A NOTICE, not an error. "This licence does not cover Cloud, so the
    // terminal was set to Offline" is the wizard reporting that it did the
    // right thing on a perfectly healthy install — and it was arriving in red,
    // on the first screen, as the only coloured thing on it. The very next step
    // already says the same in a NOT LICENSED chip.
    final modeNotice = claims == null ? null : _modeChangedNotice(claims);

    state = state.copyWith(
      entitlement: entitlement,
      claims: claims,
      // Same adoption as a fresh activation: the tenant, the modes and the
      // terminal count come off the licence, not off anything typed.
      deployment: claims == null ? null : _adopt(claims),
      // `copyWith` reads a null notice as "leave it alone", so clearing needs
      // the flag — otherwise a stale notice outlives what raised it.
      notice: modeNotice,
      clearNotice: modeNotice == null,
    );
  }

  void setLocale(String locale) => state = state.copyWith(locale: locale);

  /// Choose cloud or offline.
  ///
  /// The licence is **kept**. It was installed before this step and is what
  /// decided which modes are on offer at all, so switching between two modes it
  /// already covers cannot invalidate it. What is discarded is the endpoint
  /// configuration, which does not survive the switch: an offline terminal has
  /// no platform address, and a cloud one has no reason to keep a LAN database
  /// address the operator typed for the other mode.
  void setMode(DeploymentMode mode) {
    // Both modes are buildable now. The only rule left is the LICENCE's: a
    // terminal may run in a mode the customer actually bought and no other,
    // which is the same check the till re-applies at every boot through
    // `LicenseVerifier.evaluateClaims` — refusing here just means an operator
    // finds out on the tile rather than two screens later.
    if (!state.licensedModes.contains(mode)) return;

    // Re-choosing the mode already in force is a no-op, full stop. The reset
    // below exists for a genuine *switch*, where the old endpoint cannot
    // survive — but an operator tapping the already-selected tile on their way
    // past must not lose a database name and platform address they typed two
    // steps later. What is entered in an input stays entered.
    if (mode == state.deployment.mode) return;

    state = state.copyWith(
      deployment: DeploymentConfig(
        mode: mode,
        tenantSlug: state.deployment.tenantSlug,
        // A one-terminal plan has no shared database to point at, so the host
        // stays on this machine and the wizard never asks.
        databaseHost: state.allowsSharedDatabase
            ? state.deployment.databaseHost
            : DeploymentConfig.localhost,
      ),
      // Switching to offline takes the pairing-code path away with it: no
      // dashboard exists to have minted a code. Reset rather than leave the
      // draft on a method whose screen is now disabled and whose button can
      // never succeed.
      method: mode == DeploymentMode.cloud ? state.method : SetupMethod.manual,
      clearError: true,
    );
  }

  /// A platform address typed without a scheme still means what the operator
  /// meant: `localhost:8100` is `http://localhost:8100`, `xorder.io` is
  /// `https://xorder.io`. A scheme-less URL silently mis-parses in the HTTP
  /// client (the host becomes the scheme), which surfaces two screens later as
  /// "could not be reached" — the exact class of trap the slug field already
  /// guards against. Private hosts default to http because nobody runs TLS on
  /// a dev loopback; anything public defaults to https, never the reverse.
  static String baseUrlFrom(String input) {
    final value = input.trim();
    if (value.isEmpty || value.contains('://')) return value;
    final host = value.split('/').first.split(':').first.toLowerCase();
    final isPrivate =
        host == 'localhost' ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.endsWith('.local');
    return '${isPrivate ? 'http' : 'https'}://$value';
  }

  void setBaseUrl(String url) => state = state.copyWith(
    deployment: state.deployment.copyWith(baseUrl: baseUrlFrom(url)),
    clearError: true,
  );

  void setDatabaseHost(String host) => state = state.copyWith(
    deployment: state.deployment.copyWith(databaseHost: host.trim()),
    clearError: true,
  );

  /// Typed only when no licence has supplied one.
  ///
  /// A licence is issued to exactly one tenant, so once it is installed the
  /// slug is a fact rather than a question. The pane renders it read-only; this
  /// guard is here because the invariant belongs to the controller, not to
  /// whichever screen happens to be showing it.
  /// A pasted `demo.xorder.io` or `https://demo.xorder.io/menu` means the
  /// tenant `demo` — operators paste what they have, and refusing the domain
  /// form reads as "wrong credentials" three fields later. Pure and public so
  /// the rule is testable on its own.
  static String slugFrom(String input) {
    var value = input.trim().toLowerCase();
    value = value.replaceFirst(RegExp(r'^[a-z]+://'), '');
    value = value.split('/').first;
    if (value.contains('.')) value = value.split('.').first;
    return value;
  }

  /// Point licence activation and renewal at a different platform.
  ///
  /// Blank returns the terminal to the build's own default. Held on the draft
  /// and pushed to [deploymentProvider] at activation time — the licence step
  /// runs long before the deployment step applies anything, and the API client
  /// reads the provider, not the draft.
  void setLicenceServer(String url) {
    final trimmed = url.trim();
    state = state.copyWith(
      deployment: trimmed.isEmpty
          ? state.deployment.copyWith(clearLicenceServerUrl: true)
          : state.deployment.copyWith(licenceServerUrl: trimmed),
      clearError: true,
    );
  }

  void setTenantSlug(String slug) {
    if (state.claims != null) return;
    state = state.copyWith(
      deployment: state.deployment.copyWith(tenantSlug: slugFrom(slug)),
      // A pull that happened under the old slug now describes the wrong
      // restaurant; forgetting it is what keeps the branch step honest.
      clearConnection: true,
    );
  }

  void setVerifyTls(bool verify) => state = state.copyWith(
    deployment: state.deployment.copyWith(verifyTls: verify),
  );

  void setDatabaseName(String name) => state = state.copyWith(
    deployment: state.deployment.copyWith(databaseName: name.trim()),
    clearError: true,
  );

  void setDatabaseUser(String user) => state = state.copyWith(
    deployment: state.deployment.copyWith(databaseUser: user.trim()),
    clearError: true,
  );

  void setDatabasePort(String port) {
    final parsed = int.tryParse(port.trim());
    if (parsed == null || parsed <= 0 || parsed > 65535) return;
    state = state.copyWith(
      deployment: state.deployment.copyWith(databasePort: parsed),
    );
  }

  /// Held on the draft only until [publishCredentials] hands it to the store.
  void setDatabasePassword(String password) =>
      state = state.copyWith(databasePassword: password, clearError: true);

  void setAdminDatabasePassword(String password) =>
      state = state.copyWith(adminDatabasePassword: password, clearError: true);

  void setOwnerName(String name) =>
      state = state.copyWith(ownerName: name, clearError: true);

  void setOwnerUsername(String username) => state = state.copyWith(
    ownerUsername: username.trim().toLowerCase(),
    clearError: true,
  );

  /// Digits only, and never longer than [SetupDraft.pinLength].
  ///
  /// Enforced as it is TYPED rather than checked on submit. A PIN is entered on
  /// a keypad at the counter — there are no letters to type there — so a
  /// thirteenth digit that is silently accepted here becomes a PIN the till can
  /// never take, discovered by somebody who cannot sign in.
  void setOwnerPin(String pin) {
    final digits = pin.replaceAll(RegExp(r'[^0-9]'), '');
    state = state.copyWith(
      ownerPin: digits.length > SetupDraft.pinLength
          ? digits.substring(0, SetupDraft.pinLength)
          : digits,
      clearError: true,
    );
  }

  /// Build this machine's database, from nothing.
  ///
  /// The offline path used to start at a command line: `PosMigrator` ran only
  /// on the cloud claim path, so an offline restaurant needed somebody at a
  /// terminal with `bin/pos_migrate.dart` before the wizard could do anything.
  /// This is that command, on the screen the operator is already looking at.
  ///
  /// **Two credentials, and only one of them survives.** Creating a database
  /// and applying DDL needs an owner or superuser; selling needs `pos_till`,
  /// which is granted the least it can work with and no DDL at all. The
  /// administrator password is used here and then dropped — it is never
  /// written to disk, and the till keeps only its own.
  ///
  /// Every step is an upsert, so a run that fails halfway can simply be run
  /// again.
  Future<void> bootstrapDatabase() async {
    final s = ref.read(stringsProvider);
    final claims = state.claims;
    if (claims == null) {
      state = state.copyWith(error: s.installLicenceFirst);
      return;
    }
    // Named separately from the incomplete-fields case: "fill everything in"
    // is the wrong instruction for somebody who filled everything in and made
    // the PIN too short.
    if (state.ownerPin.isNotEmpty && !state.hasUsablePin) {
      state = state.copyWith(
        error: s.pinIsExactlyDigits(SetupDraft.pinLength),
      );
      return;
    }
    if (state.ownerName.trim().isEmpty ||
        state.ownerUsername.trim().isEmpty ||
        !state.hasUsablePin) {
      state = state.copyWith(error: s.firstPersonIncomplete);
      return;
    }
    // Checked HERE, not left to throw out of `CREATE DATABASE "x"`. The name is
    // typed on the previous screen, and letting it fail at the bottom of this
    // one produced a raw ArgumentError in the operator's error bar — Dart
    // internals, about bind parameters, in front of somebody installing a till.
    if (!state.deployment.hasValidDatabaseName) {
      state = state.copyWith(
        error: s.databaseNameInvalid(state.deployment.databaseName),
      );
      return;
    }

    state = state.copyWith(busy: true, clearError: true);

    // The admin connection: same host and database, a different role.
    final admin = state.deployment.copyWith(
      databaseUser: state.deployment.adminDatabaseUser,
    );
    final credentials = MutablePosDbCredentials()
      ..set(state.adminDatabasePassword);
    final database = PosDatabase(credentials: credentials);
    final bootstrap = LocalBootstrap(database);
    final done = <String>[];

    try {
      final created = await LocalBootstrap.createDatabase(
        admin,
        state.adminDatabasePassword,
        state.deployment.databaseName,
      );
      done.add(
        created
            ? s.createdDatabase(state.deployment.databaseName)
            : s.databaseAlreadyThere(state.deployment.databaseName),
      );

      final applied = await bootstrap.migrate(admin);
      done.add(
        applied.isEmpty
            ? s.schemaAlreadyCurrent
            : s.migrationsApplied(applied.length),
      );

      final restaurantId = await bootstrap.seedRestaurant(
        admin,
        slug: claims.tenantSlug,
        name: claims.tenantName,
      );
      final branchId = await bootstrap.seedBranch(
        admin,
        restaurantId: restaurantId,
        name: 'Main',
        code: 'MAIN',
      );
      done.add(s.restaurantSeeded(claims.tenantName));

      final roles = await bootstrap.seedSystemRoles(admin, restaurantId);
      done.add(
        roles.created == 0
            ? s.rolesAlreadyThere
            : s.rolesCreated(roles.created),
      );

      // Void, refund, discount and price-override reasons. Seeded here rather
      // than left to migration 9, which can only reach restaurants that already
      // existed when it ran — and this one is being created now.
      await bootstrap.seedReasonCodes(admin, restaurantId);

      final ownerCreated = await bootstrap.seedOwner(
        admin,
        restaurantId: restaurantId,
        branchId: branchId,
        roleId: roles.ids[SystemRoles.ownerCode]!,
        name: state.ownerName.trim(),
        username: state.ownerUsername.trim(),
        pin: state.ownerPin,
      );
      done.add(
        ownerCreated
            ? s.ownerCreated(state.ownerName.trim())
            : s.ownerAlreadyHere(state.ownerUsername.trim()),
      );

      await bootstrap.applyGrants(admin, [
        ...LocalBootstrap.tillGrants(
          database: state.deployment.databaseName,
          role: state.deployment.databaseUser,
          // Only a cloud till runs `BootstrapSeeder`; only a cloud till is
          // therefore granted what it writes. See [LocalBootstrap.tillGrants].
          cloudSeeding: state.deployment.mode == DeploymentMode.cloud,
        ),
        ...LocalBootstrap.administrativeGrants(
          role: state.deployment.adminDatabaseUser,
        ),
      ]);
      done.add(
        s.grantsApplied(
          state.deployment.databaseUser,
          state.deployment.adminDatabaseUser,
        ),
      );

      state = state.copyWith(
        busy: false,
        bootstrapped: true,
        bootstrapReport: done.join('\n'),
      );
    } on PosDbException catch (error) {
      state = state.copyWith(busy: false, error: _bootstrapFailure(error));
    } on Object catch (error, stack) {
      // The raw object still goes to the console — the screen gets the
      // sentence, the log gets the thing that actually happened.
      debugPrint('setup[bootstrapDatabase] threw: $error\n$stack');
      state = state.copyWith(busy: false, error: '$error');
    } finally {
      // The administrator connection is for this one operation. Closing it
      // also drops the password with the pool.
      await database.close();
    }
  }

  /// A repository's refusal, in the operator's language.
  ///
  /// The tenant slug and platform address come from the wizard's own state:
  /// the repository put them into its English sentence, and this is how the
  /// Arabic one gets them back without parsing the English.
  String? _refusal(String? code, String? message) => message == null
      ? null
      : provisioningRefusal(
          ref.read(stringsProvider),
          code,
          fallback: message,
          tenant: state.deployment.tenantSlug,
          platform: state.deployment.baseUrl,
        );

  /// The next thing to try, in the operator's words.
  String _bootstrapFailure(PosDbException error) {
    final s = ref.read(stringsProvider);

    return switch (error.failure) {
      PosDbFailure.auth => s.bootstrapAuthFailed(
        state.deployment.adminDatabaseUser,
      ),
      PosDbFailure.dns || PosDbFailure.tcp => s.bootstrapUnreachable(
        state.deployment.databaseHost,
        state.deployment.databasePort,
      ),
      PosDbFailure.permissionDenied => s.permissionDenied(
        state.deployment.adminDatabaseUser,
        state.deployment.databaseName,
      ),
      _ => s.bootstrapRefused(error.raw),
    };
  }

  /// Move the password out of the wizard and into the credential store, where
  /// the connection pool reads it. Called once, when setup finishes.
  void publishCredentials() =>
      ref.read(posDbCredentialsStoreProvider).set(state.databasePassword);

  /// Make the draft's endpoint the one in force **right now**.
  ///
  /// The repositories are built from [deploymentProvider], which `next()`
  /// publishes on step transitions — but an operator who edits the platform
  /// address and then acts on a *later* step has navigation histories this
  /// cannot fully predict. Publishing at the top of every network action makes
  /// the invariant unconditional: the wizard always talks to the address on
  /// its own screen.
  void _publishDeployment() {
    ref.read(deploymentProvider.notifier).apply(state.deployment);
    publishCredentials();
  }

  /// The terminal this wizard just described.
  TerminalProfile get profile => TerminalProfile(
    branchId: state.branchId,
    branchName: state.branchLabel,
    terminalName: state.terminalName,
    terminalId: state.terminalId,
    installationId: state.installationId,
    provisioned: state.claimed,
    restaurantId: state.restaurantId,
    branchCode: state.branchCode,
  );

  /// Finish setup: publish what the wizard gathered, then put it somewhere the
  /// next launch will find it.
  ///
  /// Order matters. The configuration file and the keystore are written
  /// **before** the in-memory providers are marked complete, so a terminal that
  /// cannot save — a full disk, a keystore that refuses — never reports a
  /// finished setup it would lose on exit. The operator sees the failure now,
  /// standing at the till with the password still in hand, rather than tomorrow
  /// morning when the wizard reappears.
  Future<String?> complete() async {
    final s = ref.read(stringsProvider);
    final profile = this.profile;

    // A failed manual registration is recoverable while the installer remains
    // in the wizard, but it cannot become a completed till. Without this
    // identity every production repository deliberately resolves to its
    // unconfigured implementation and the first screen can do nothing except
    // fail while asking who is working the terminal.
    if (!profile.isSet) {
      // Name the actual gap. This guard once said "not registered" for every
      // missing field — including a missing branch invoice prefix on a till
      // whose registration had demonstrably succeeded, which sent the
      // operator to redo the one step that was fine.
      final missing = [
        if (state.terminalName.trim().isEmpty) s.missingTerminalName,
        if (profile.restaurantId == null) s.missingRestaurantIdentity,
        if (profile.branchId == null) s.missingBranch,
        if (profile.branchCode?.isEmpty ?? true) s.missingBranchPrefix,
        if (profile.terminalId?.isEmpty ?? true) s.missingTerminalId,
      ];
      final message = s.setupIncomplete(missing.join(', '));
      state = state.copyWith(error: message);
      return message;
    }

    try {
      publishCredentials();
      await ref.read(posDbCredentialsStoreProvider).save();
      await ref
          .read(terminalConfigStoreProvider)
          .write(
            SavedTerminalConfig(
              deployment: state.deployment,
              terminal: profile,
              languageCode: state.locale,
            ),
          );
    } on Exception catch (error) {
      final message = s.couldNotSaveSetup(error);
      state = state.copyWith(error: message);
      return message;
    }

    ref.read(localeProvider.notifier).apply(state.locale);
    ref.read(deploymentProvider.notifier).apply(state.deployment);
    ref.read(terminalProfileProvider.notifier).apply(profile);
    ref.read(setupCompleteProvider.notifier).markComplete();
    return null;
  }

  void setSyncPolicy(SyncPolicy policy) => state = state.copyWith(
    deployment: state.deployment.copyWith(syncPolicy: policy),
  );

  /// Switching path clears the claim: the branch and till name on the draft
  /// came from the response to the old one, and leaving them behind would show
  /// an operator settings they never chose.
  void setMethod(SetupMethod method) {
    // A pairing code is minted by a dashboard, and an offline deployment has
    // none. The pane disables the tile; this is the same rule where it
    // belongs, so a mode switch cannot strand a draft on a method that has no
    // way to complete.
    if (method == SetupMethod.pairingCode &&
        state.deployment.mode != DeploymentMode.cloud) {
      return;
    }

    state = state.copyWith(
      method: method,
      clearError: true,
      clearClaim: true,
      clearConnection: true,
    );
  }

  void setPairingCode(String code) => state = state.copyWith(
    pairingCode: code.trim().toUpperCase(),
    clearError: true,
  );

  void setOperatorUsername(String username) => state = state.copyWith(
    operatorUsername: username.trim(),
    clearError: true,
    clearConnection: true,
  );

  void setOperatorPassword(String password) => state = state.copyWith(
    operatorPassword: password,
    clearError: true,
    clearConnection: true,
  );

  void setLicenceKey(String key) =>
      state = state.copyWith(licenceKey: key, clearError: true);

  void setBranch(int id, String label) =>
      state = state.copyWith(branchId: id, branchLabel: label);

  void setTerminalName(String name) => state = state.copyWith(
    terminalName: name,
    // Generated on this device and never reissued: it is what the server
    // ties shifts and orders to.
    terminalId: state.terminalId ?? _uuid.v4(),
  );

  void setPrinter(String? name) => state = state.copyWith(printerName: name);
  void setDrawer(bool attached) =>
      state = state.copyWith(drawerAttached: attached);
  void setScanner(bool attached) =>
      state = state.copyWith(scannerAttached: attached);

  /// Probe the configured endpoint.
  ///
  /// **The database is tested in every mode**, not just when it is on another
  /// machine, because that is where the money goes — a cloud terminal writes its
  /// sale locally first and syncs afterwards. In cloud mode the platform address
  /// is checked as well, but only the database can fail setup: a platform that
  /// is briefly down must not stop an installer finishing.
  ///
  /// Reporting which of the four things failed is the whole value: an installer
  /// sent to fix the firewall when the password is wrong will not fix it.
  Future<bool> testConnection() async {
    final config = state.deployment;

    state = state.copyWith(busy: true, clearError: true);

    if (config.mode.needsBaseUrl) {
      final baseUrl = config.baseUrl?.trim() ?? '';

      // Nothing typed is not the same as nothing answering, and saying "could
      // not reach null" sent an installer to check a network cable over a field
      // they had simply not filled in yet.
      if (baseUrl.isEmpty) {
        state = state.copyWith(
          busy: false,
          error: ref.read(stringsProvider).platformAddressRequired,
        );
        return false;
      }

      final reachable = await ref
          .read(connectivityProbeProvider)
          .canReach(config);
      if (!reachable) {
        state = state.copyWith(
          busy: false,
          error: ref.read(stringsProvider).couldNotReach(baseUrl),
        );
        return false;
      }
    }

    // Probe with what the operator just typed, not with whatever the store
    // holds from an earlier attempt.
    ref.read(posDbCredentialsStoreProvider).set(state.databasePassword);
    final failure = await ref.read(posDatabaseProvider).probe(config);

    // Success used to be SILENT — the error bar cleared and nothing took its
    // place, so the only difference between "it worked" and "the button does
    // nothing" was the absence of red. A test whose good outcome is invisible
    // is a test nobody trusts.
    state = state.copyWith(
      busy: false,
      error: _describe(failure, config),
      notice: failure == null
          ? ref.read(stringsProvider).connectionOk(config.databaseName)
          : null,
      clearNotice: failure != null,
    );
    return failure == null;
  }

  /// Which of the four things went wrong, in the operator's language. An
  /// installer sent to open a firewall port when the password is wrong will
  /// not fix it, so each failure names its own cause.
  String? _describe(PosDbFailure? failure, DeploymentConfig config) {
    final s = ref.read(stringsProvider);

    return switch (failure) {
      null => null,
      PosDbFailure.dns => s.dnsFailure(),
      PosDbFailure.tcp => s.tcpFailure(config.databasePort),
      PosDbFailure.auth => s.authFailure(config.databaseUser),
      PosDbFailure.tls => s.tlsFailure(),
      PosDbFailure.missingDatabase => s.missingDatabase(config.databaseName),
      PosDbFailure.permissionDenied => s.permissionDenied(
        config.databaseUser,
        config.databaseName,
      ),
      // Reached it, authenticated, and the statement itself failed — which is
      // a different thing from there being no database to run it against.
      PosDbFailure.query ||
      PosDbFailure.unknown => s.queryFailure(config.databaseName),
    };
  }

  /// Activate the licence — from the platform with a typed key, or from a file
  /// the supplier sent by email or on a USB stick.
  ///
  /// Neither path is a fallback for the other. A till being installed somewhere
  /// with no internet at all has only the file; a till being installed by
  /// someone who was emailed a key has only the key.
  ///
  /// **This is the first step, so what it installs configures the rest of the
  /// wizard.** The licence names its tenant, so the account step no longer asks
  /// for one; and it names the modes it covers, so the connection step starts on
  /// one the customer actually bought rather than on whatever the enum lists
  /// first.
  Future<void> activateLicence({String? fileContents}) async {
    state = state.copyWith(busy: true, clearError: true);

    // The API client resolves its address from `deploymentProvider`, and the
    // deployment step that would normally publish the draft is still five
    // screens away. Push just this one field, so an address typed on THIS
    // screen is the one the very next request uses.
    final licenceServer = state.deployment.licenceServerUrl;
    ref
        .read(deploymentProvider.notifier)
        .apply(
          licenceServer == null || licenceServer.isEmpty
              ? ref
                    .read(deploymentProvider)
                    .copyWith(clearLicenceServerUrl: true)
              : ref
                    .read(deploymentProvider)
                    .copyWith(licenceServerUrl: licenceServer),
        );

    final result = await ref
        .read(licenceServiceProvider)
        .activate(
          // At this step the licence *supplies* the tenant — it is installed
          // before anything has been signed into. So a licence being installed
          // here must not be judged against a tenant that was itself read off
          // the licence it is replacing: that made a terminal holding one
          // restaurant's licence unable to accept another's, which is exactly
          // what happens on a machine being moved, or on a developer's, and it
          // reported the refusal as the *new* licence being wrong.
          //
          // Once the terminal has been claimed, the tenant came from the
          // dashboard rather than from a file, and the check must bite.
          deployment: state.claimed
              ? state.deployment
              : state.deployment.copyWith(clearTenantSlug: true),
          key: state.licenceKey,
          fileContents: fileContents,
        );

    final claims = result.claims;
    final adopted = claims == null ? state.deployment : _adopt(claims);
    final entitlement = await _judgeOnCoveredMode(result.entitlement, adopted);

    // `result.notice` speaks for the first verdict, and it is the only thing
    // that speaks at all when there was no verdict to give — an unrecognised
    // key or a file that is not a licence never reach the verifier. Only when
    // _judgeOnCoveredMode actually replaced the verdict does its notice
    // replace that one, so a mode refusal it has just overturned stops being
    // reported.
    final notice =
        entitlement == null || identical(entitlement, result.entitlement)
        ? result.notice
        : (entitlement.canOpenShift ? null : entitlement.notice);

    // The licence's own notice wins — an expiry warning outranks a mode change
    // — and it is the only one of the two that is a problem. A mode the licence
    // did not cover is the wizard doing its job, so it goes in the notice bar;
    // a silent flip must still not be the outcome.
    final modeChanged = notice != null || claims == null
        ? null
        : _modeChangedNotice(claims);

    state = state.copyWith(
      busy: false,
      entitlement: entitlement,
      claims: claims,
      deployment: claims == null ? null : adopted,
      error: notice?.text(ref.read(stringsProvider)),
      notice: modeChanged,
      clearNotice: modeChanged == null,
    );
    // Anything reading the installed licence must see the new one immediately.
    ref.invalidate(licenceEntitlementProvider);
  }

  /// Re-judge a licence against the mode it actually puts this terminal in.
  ///
  /// The mode gate is the same class of problem as the tenant gate above, and
  /// the answer is the same: a licence *supplies* the mode, so judging it
  /// against whatever the draft happened to be sitting on asks the licence to
  /// justify a choice it was never shown. `DeploymentConfig.unconfigured` is
  /// cloud, so before this an offline-only licence — read on a machine whose
  /// operator had not reached the mode screen, and now cannot, because the
  /// licence step comes first — came back `modeNotLicensed` and stopped the
  /// wizard on step 2 with no way forward. [_adopt] would then quietly move the
  /// draft to `offline` anyway, leaving a refusal on screen that no longer
  /// described the terminal.
  ///
  /// Only the mode verdict is revisited. Expiry, tenant, signature and
  /// fingerprint stand exactly as given — those are refusals of the licence
  /// itself, not of a question the wizard had not asked yet.
  Future<LicenseEntitlement?> _judgeOnCoveredMode(
    LicenseEntitlement? verdict,
    DeploymentConfig adopted,
  ) async {
    if (verdict?.state != LicenseState.modeNotLicensed) return verdict;

    final service = ref.read(licenceServiceProvider);
    // Sound because activation persists a licence even when it refuses trade —
    // "the operator needs the status screen to show what they actually
    // installed" — so the file backing this verdict is on disk either way.
    final file = await service.installed();
    if (file == null) return verdict;

    return service.evaluate(file, adopted);
  }

  /// Fold what the licence knows into the deployment config.
  ///
  /// The tenant is taken from the licence rather than typed, because a licence
  /// is issued to exactly one tenant and asking the operator to name it again
  /// only creates a mismatch to diagnose later.
  DeploymentConfig _adopt(LicenseClaims claims) {
    final current = state.deployment;

    return current.copyWith(
      tenantSlug: claims.tenantSlug,
      mode: _coveredMode(claims, current.mode),
      databaseHost: claims.maxTerminals > 1
          ? current.databaseHost
          : DeploymentConfig.localhost,
    );
  }

  /// The mode this licence permits, nearest to the one already chosen.
  ///
  /// A licence that does not cover the chosen mode moves the terminal to one
  /// it does. That is correct — the alternative is a setup that completes and
  /// then reports `modeNotLicensed` at the first boot — but it used to happen
  /// in SILENCE, so an operator who picked Offline could reach the summary
  /// screen still believing they had. [_modeChangedNotice] is what says so.
  DeploymentMode _coveredMode(LicenseClaims claims, DeploymentMode chosen) {
    final covered = claims.modes.isEmpty
        ? DeploymentMode.values.toSet()
        : claims.modes;

    return covered.contains(chosen) ? chosen : covered.first;
  }

  /// Say so when adopting a licence moved the terminal to another mode.
  ///
  /// Null when nothing moved, which is the ordinary case.
  String? _modeChangedNotice(LicenseClaims claims) {
    final chosen = state.deployment.mode;
    final landed = _coveredMode(claims, chosen);
    if (landed == chosen) return null;

    final s = ref.read(stringsProvider);

    return s.licenceModeChanged(chosen.label(s), landed.label(s));
  }

  /// Verify the slug + admin credentials and pull the tenant's configuration
  /// (the owner's phase-1 cloud flow). Everything the following steps show —
  /// the branch list above all — is what this call brought back. Registers
  /// nothing: that happens at the terminal step, once a branch and a name
  /// have been chosen from the pulled data.
  Future<void> connectTenant() async {
    state = state.copyWith(busy: true, clearError: true);
    _publishDeployment();

    final result = await ref
        .read(provisioningRepositoryProvider)
        .connect(
          tenantSlug: state.deployment.tenantSlug ?? '',
          username: state.operatorUsername,
          password: state.operatorPassword,
        );

    if (!result.succeeded) {
      state = state.copyWith(
        busy: false,
        clearConnection: true,
        error: _refusal(result.code, result.message),
      );
      return;
    }

    final branches = result.branches;
    final only = branches.length == 1 ? branches.single : null;

    // Adopt by default when the dashboard already made a till for this tenant.
    // Creating another beside it is how a two-seat restaurant ends up with
    // four rows, so the wizard opens on the first one waiting and offers
    // "create a new one" as the deliberate alternative.
    final adoptable = result.terminals.where((t) => t.isAdoptable).toList();

    state = state.copyWith(
      busy: false,
      connected: true,
      tenantName: result.tenantName,
      pulledBranches: branches,
      pulledTerminals: result.terminals,
      adoptTerminalId: adoptable.isEmpty ? null : adoptable.first.id,
      terminalName: adoptable.isEmpty ? null : adoptable.first.name,
      // One branch is not a choice; pre-answering it turns that step into a
      // confirmation, the same courtesy the pairing path already gets.
      branchId: only?.id ?? state.branchId,
      branchLabel: only?.name ?? state.branchLabel,
      branchCode: only?.code ?? state.branchCode,
    );
  }

  /// Redeem a pairing code and adopt what the dashboard already decided about
  /// this till (POS-BE-023).
  ///
  /// The branch, the name and the terminal id all arrive from the server here,
  /// which is the point: the terminal row existed before this machine did, so
  /// Super Admin was already tracking it.
  Future<void> claimTerminal() async {
    state = state.copyWith(busy: true, clearError: true);
    _publishDeployment();

    final result = await ref
        .read(provisioningRepositoryProvider)
        .claimByCode(
          tenantSlug: state.deployment.tenantSlug ?? '',
          code: state.pairingCode,
        );

    final claim = result.claim;
    if (claim == null) {
      state = state.copyWith(
        busy: false,
        claimed: false,
        error: _refusal(result.code, result.message),
      );
      return;
    }

    state = state.copyWith(
      busy: false,
      claimed: true,
      branchId: claim.branchId,
      branchLabel: claim.branchName,
      restaurantId: claim.restaurantId,
      branchCode: claim.branchCode,
      terminalName: claim.terminalName,
      terminalId: claim.terminalId,
      deployment: state.deployment.copyWith(syncPolicy: claim.syncPolicy),
      // A message on a SUCCESSFUL claim is information, not failure — the
      // seat warning and the deferred-seed note arrive here.
      notice: result.message,
    );
  }

  /// Register a hand-configured terminal against the tenant.
  ///
  /// **Failure does not block setup.** An installer standing in a restaurant
  /// with the server down must still be able to finish; the terminal registers
  /// at first sync instead. Tracking is the goal, but a dropped call during
  /// setup should not strand the person doing it.
  Future<void> registerTerminal() async {
    final branchId = state.branchId;
    final adopting = state.adoptTerminalId;
    if (adopting == null &&
        (branchId == null || state.terminalName.trim().isEmpty)) {
      return;
    }

    state = state.copyWith(busy: true, clearError: true);
    _publishDeployment();

    final provisioning = ref.read(provisioningRepositoryProvider);

    // WHO is registering. Offline registration authenticates against
    // `pos_staff` on this machine's own database, and the person doing it is
    // the administrator created two steps ago — the wizard is still holding
    // those credentials, so asking for them again would be asking somebody to
    // retype what they typed a minute earlier on the same run.
    //
    // The cloud fields are the ones the Sign in step collects, and the offline
    // path no longer has that step: it asks for the first administrator
    // instead. Reading them here sent an empty username to the till's own
    // database and was refused every time, on the last step of the wizard.
    final offline = state.deployment.mode == DeploymentMode.offline;
    final username = offline ? state.ownerUsername : state.operatorUsername;
    final password = offline ? state.ownerPin : state.operatorPassword;

    // Adopting takes the row the dashboard already created — its name, branch
    // and terminal id all come back from the server, exactly as they do on the
    // pairing-code path. Registering is the fallback for a tenant that has no
    // terminal yet, and it is the only branch of this that spends a new seat.
    final result = adopting != null
        ? await provisioning.adoptTerminal(
            tenantSlug: state.deployment.tenantSlug ?? '',
            username: username,
            password: password,
            terminalId: adopting,
          )
        : await provisioning.registerManually(
            tenantSlug: state.deployment.tenantSlug ?? '',
            username: username,
            password: password,
            terminalName: state.terminalName.trim(),
            branchId: branchId!,
          );

    final claim = result.claim;
    state = state.copyWith(
      busy: false,
      claimed: claim != null,
      terminalId: claim?.terminalId ?? state.terminalId,
      restaurantId: claim?.restaurantId,
      branchCode: claim?.branchCode,
      // An adopted terminal's branch and name are the dashboard's, not this
      // machine's — take what came back rather than leaving the guess on
      // screen for the summary step to show.
      branchId: claim?.branchId ?? state.branchId,
      branchLabel: claim?.branchName ?? state.branchLabel,
      terminalName: claim?.terminalName ?? state.terminalName,
      // Same words, opposite meanings: on a failed register the message is
      // the failure; on a successful one it is a heads-up and must not wear
      // the error bar's red.
      error: claim == null ? _refusal(result.code, result.message) : null,
      notice: claim == null ? null : result.message,
    );
  }

  /// Adopt the terminal with this id, or pass null to create a new one.
  ///
  /// Clears the name when adopting: it is about to be overwritten by whatever
  /// the dashboard called that till, and leaving a stale one on screen invites
  /// the operator to "fix" a field the server owns.
  void setAdoptedTerminal(int? terminalId) {
    if (terminalId == null) {
      state = state.copyWith(clearAdoption: true, terminalName: '');
      return;
    }

    final match = state.pulledTerminals
        ?.where((t) => t.id == terminalId)
        .firstOrNull;
    state = state.copyWith(
      adoptTerminalId: terminalId,
      terminalName: match?.name ?? state.terminalName,
    );
  }

  /// First catalogue pull, so the till has a menu before it ever needs one.
  ///
  /// On a cloud terminal this is a genuine download: the bootstrap bundle is
  /// fetched from the platform and seeded into the local database, then read
  /// back. That also self-heals a registration whose automatic seed could not
  /// run — the button does what its label says, from the authoritative source.
  Future<void> syncCatalogue() async {
    state = state.copyWith(busy: true, clearError: true);
    _publishDeployment();
    try {
      await _seedFromPlatform();
      final catalog = await ref.read(catalogRepositoryProvider).load();
      state = state.copyWith(
        busy: false,
        catalogueItems: catalog.products.length,
      );
    } on _CatalogueBlocked catch (blocked) {
      state = state.copyWith(busy: false, error: blocked.message);
    } on Exception catch (error) {
      state = state.copyWith(
        busy: false,
        error: ref.read(stringsProvider).catalogueDownloadFailed(error),
      );
    }
  }

  /// Fetch the bundle and seed the local cache — cloud terminals holding a
  /// device token only. Anything less configured falls through to reading
  /// whatever the local database already holds.
  Future<void> _seedFromPlatform() async {
    // Offline terminals have no platform to pull from — the local database is
    // the world, and reading it is the whole step.
    if (state.deployment.mode != DeploymentMode.cloud) return;

    final s = ref.read(stringsProvider);
    final api = ref.read(posCloudApiProvider);
    if (api == null) {
      throw _CatalogueBlocked(s.noPlatformAddressInForce);
    }
    if (!ref.read(deviceTokenVaultProvider).isSet) {
      throw _CatalogueBlocked(s.terminalNotRegisteredYet);
    }

    final reply = await api.bootstrap();
    if (!reply.ok) {
      // The server's own message is appended untranslated — it came from the
      // platform, and this build has no way to say it in another language.
      final answer = reply.offline
          ? s.menuDownloadSilence
          : s.menuDownloadHttp(reply.status);
      throw _CatalogueBlocked(
        s.menuDownloadRefused(
          api.baseUrl,
          reply.message == null ? answer : '$answer — ${reply.message}',
        ),
      );
    }
    final bundle = BootstrapBundle.tryParse(reply.body);
    if (bundle == null || !bundle.seedable) {
      throw _CatalogueBlocked(s.menuShapeNotUnderstood(api.baseUrl));
    }

    // Forced: during setup the operator pressing "Download menu" IS the
    // precedence decision, and a half-applied earlier seed must not win a
    // config_version tie against a complete one.
    await BootstrapSeeder(
      database: ref.read(posDatabaseProvider),
      config: state.deployment,
    ).seed(bundle, force: true);
  }

  void next() {
    if (!state.canAdvance || state.isLastStep) return;

    // Every step after the connection one reads the branch database: the branch
    // list, the pairing code, the first catalogue pull. They need the endpoint
    // and the credential, which is why those are published here rather than at
    // the end of the wizard — but they also need the *restaurant*, and that is
    // not typed until the Sign in step two screens later. So this republishes on
    // every transition rather than once: a value typed on one step has to be in
    // force on the next, and going Back to change the address has to take.
    if (state.step.index >= SetupStep.deployment.index) {
      ref.read(deploymentProvider.notifier).apply(state.deployment);
      publishCredentials();
    }

    final steps = state.visibleSteps;
    state = state.copyWith(
      step: steps[steps.indexOf(state.step) + 1],
      clearError: true,
      clearNotice: true,
    );
  }

  void back() {
    if (state.isFirstStep) return;
    final steps = state.visibleSteps;
    state = state.copyWith(
      step: steps[steps.indexOf(state.step) - 1],
      clearError: true,
      clearNotice: true,
    );
  }
}

/// A reason the catalogue cannot be pulled, phrased for the operator.
///
/// Its own type so the pane shows the reason verbatim — a silent fallthrough
/// here is how "not registered" once surfaced as "no restaurant named demo
/// exists in this database", which sent the operator to check a database that
/// was never the problem.
class _CatalogueBlocked implements Exception {
  const _CatalogueBlocked(this.message);

  final String message;
}

final setupProvider = NotifierProvider<SetupController, SetupDraft>(
  SetupController.new,
);
