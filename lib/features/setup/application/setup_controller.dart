import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../data/postgres/pos_database.dart';
import '../../licensing/data/licence_service.dart';
import '../domain/setup_state.dart';

const _uuid = Uuid();

/// Drives the first-run wizard.
///
/// Everything reachable from here goes through a repository interface, so the
/// wizard runs end to end today against fakes — the same property that lets the
/// rest of the POS be built while every backend contract is still `PROPOSED`.
class SetupController extends Notifier<SetupDraft> {
  @override
  SetupDraft build() => const SetupDraft();

  void setLocale(String locale) => state = state.copyWith(locale: locale);

  void setMode(DeploymentMode mode) {
    // Changing mode discards a licence already checked against the old one — a
    // cloud licence does not necessarily cover a branch server.
    state = SetupDraft(
      step: state.step,
      locale: state.locale,
      deployment: DeploymentConfig(mode: mode, tenantSlug: state.deployment.tenantSlug),
      licenceKey: state.licenceKey,
    );
  }

  void setBaseUrl(String url) => state = state.copyWith(
        deployment: state.deployment.copyWith(baseUrl: url.trim()),
        clearError: true,
      );

  void setUpstreamUrl(String url) =>
      state = state.copyWith(deployment: state.deployment.copyWith(upstreamUrl: url.trim()));

  void setTenantSlug(String slug) => state = state.copyWith(
        deployment: state.deployment.copyWith(tenantSlug: slug.trim().toLowerCase()),
      );

  void setVerifyTls(bool verify) =>
      state = state.copyWith(deployment: state.deployment.copyWith(verifyTls: verify));

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
    state = state.copyWith(deployment: state.deployment.copyWith(databasePort: parsed));
  }

  /// Held on the draft only until [publishCredentials] hands it to the store.
  void setDatabasePassword(String password) =>
      state = state.copyWith(databasePassword: password, clearError: true);

  /// Move the password out of the wizard and into the credential store, where
  /// the connection pool reads it. Called once, when setup finishes.
  void publishCredentials() =>
      ref.read(posDbCredentialsStoreProvider).set(state.databasePassword);

  void setSyncPolicy(SyncPolicy policy) =>
      state = state.copyWith(deployment: state.deployment.copyWith(syncPolicy: policy));

  /// Switching path clears the claim: the branch and till name on the draft
  /// came from the response to the old one, and leaving them behind would show
  /// an operator settings they never chose.
  void setMethod(SetupMethod method) =>
      state = state.copyWith(method: method, clearError: true, clearClaim: true);

  void setPairingCode(String code) =>
      state = state.copyWith(pairingCode: code.trim().toUpperCase(), clearError: true);

  void setOperatorUsername(String username) =>
      state = state.copyWith(operatorUsername: username.trim(), clearError: true);

  void setOperatorPassword(String password) =>
      state = state.copyWith(operatorPassword: password, clearError: true);

  void setLicenceKey(String key) => state = state.copyWith(licenceKey: key, clearError: true);

  void setBranch(int id, String label) =>
      state = state.copyWith(branchId: id, branchLabel: label);

  void setTerminalName(String name) => state = state.copyWith(
        terminalName: name,
        // Generated on this device and never reissued: it is what the server
        // ties shifts and orders to.
        terminalId: state.terminalId ?? _uuid.v4(),
      );

  void setPrinter(String? name) => state = state.copyWith(printerName: name);
  void setDrawer(bool attached) => state = state.copyWith(drawerAttached: attached);
  void setScanner(bool attached) => state = state.copyWith(scannerAttached: attached);

  /// Probe the configured endpoint. An islanded till has nothing to reach.
  ///
  /// For a branch server this tests the **database**, not just the HTTP port,
  /// because that is where the money goes. Reporting which of the four things
  /// failed is the whole value: an installer sent to fix the firewall when the
  /// password is wrong will not fix it.
  Future<bool> testConnection() async {
    final config = state.deployment;
    if (config.mode == DeploymentMode.standalone) return true;

    state = state.copyWith(busy: true, clearError: true);

    final reachable = await ref.read(connectivityProbeProvider).canReach(config);
    if (!reachable) {
      state = state.copyWith(
        busy: false,
        error: 'Could not reach ${config.baseUrl}. Check the address, and that '
            'the server is switched on and on this network.',
      );
      return false;
    }

    if (config.mode != DeploymentMode.branchServer) {
      state = state.copyWith(busy: false);
      return true;
    }

    // Probe with what the operator just typed, not with whatever the store
    // holds from an earlier attempt.
    ref.read(posDbCredentialsStoreProvider).set(state.databasePassword);
    final failure = await ref.read(posDatabaseProvider).probe(config);

    state = state.copyWith(busy: false, error: _describe(failure, config));
    return failure == null;
  }

  static String? _describe(PosDbFailure? failure, DeploymentConfig config) => switch (failure) {
        null => null,
        PosDbFailure.dns =>
          'The server name does not resolve. Use its IP address, or give the box '
              'a fixed address on the router.',
        PosDbFailure.tcp =>
          'Nothing answered on port ${config.databasePort}. Check PostgreSQL is '
              "running, that listen_addresses includes this network, and the host's "
              'firewall allows the connection.',
        PosDbFailure.auth =>
          'PostgreSQL rejected the username or password. Check the '
              '"${config.databaseUser}" role exists and the password is right.',
        PosDbFailure.tls =>
          'PostgreSQL rejected the secure connection. Check its certificate, or '
              'tick the option above if this really is a box on this network.',
        PosDbFailure.query || PosDbFailure.unknown =>
          'Connected, but the database did not answer as expected. Check that '
              '"${config.databaseName}" is the right database.',
      };

  /// Activate the licence — online if the platform is reachable, otherwise from
  /// a file the supplier sent by email or on a USB stick.
  ///
  /// An on-premises till may never see the internet, so offline activation is a
  /// first-class path here, not a fallback.
  Future<void> activateLicence({String? fileContents}) async {
    state = state.copyWith(busy: true, clearError: true);

    final result = await ref.read(licenceServiceProvider).activate(
          deployment: state.deployment,
          key: state.licenceKey,
          fileContents: fileContents,
        );

    state = state.copyWith(
      busy: false,
      entitlement: result.entitlement,
      error: result.error,
    );
    // Anything reading the installed licence must see the new one immediately.
    ref.invalidate(licenceEntitlementProvider);
  }

  /// Redeem a pairing code and adopt what the dashboard already decided about
  /// this till (POS-BE-023).
  ///
  /// The branch, the name and the terminal id all arrive from the server here,
  /// which is the point: the terminal row existed before this machine did, so
  /// Super Admin was already tracking it.
  Future<void> claimTerminal() async {
    state = state.copyWith(busy: true, clearError: true);

    final result = await ref.read(provisioningRepositoryProvider).claimByCode(
          tenantSlug: state.deployment.tenantSlug ?? '',
          code: state.pairingCode,
        );

    final claim = result.claim;
    if (claim == null) {
      state = state.copyWith(busy: false, claimed: false, error: result.message);
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
    if (branchId == null || state.terminalName.trim().isEmpty) return;

    state = state.copyWith(busy: true, clearError: true);

    final result = await ref.read(provisioningRepositoryProvider).registerManually(
          tenantSlug: state.deployment.tenantSlug ?? '',
          username: state.operatorUsername,
          password: state.operatorPassword,
          terminalName: state.terminalName.trim(),
          branchId: branchId,
        );

    final claim = result.claim;
    state = state.copyWith(
      busy: false,
      claimed: claim != null,
      terminalId: claim?.terminalId ?? state.terminalId,
      restaurantId: claim?.restaurantId,
      branchCode: claim?.branchCode,
      error: result.message,
    );
  }

  /// First catalogue pull, so the till has a menu before it ever needs one.
  Future<void> syncCatalogue() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final catalog = await ref.read(catalogRepositoryProvider).load();
      state = state.copyWith(busy: false, catalogueItems: catalog.products.length);
    } on Exception catch (error) {
      state = state.copyWith(busy: false, error: 'Catalogue download failed: $error');
    }
  }

  void next() {
    if (!state.canAdvance || state.step.isLast) return;

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

    state = state.copyWith(step: SetupStep.values[state.step.index + 1], clearError: true);
  }

  void back() {
    if (state.step.isFirst) return;
    state = state.copyWith(step: SetupStep.values[state.step.index - 1], clearError: true);
  }
}

final setupProvider = NotifierProvider<SetupController, SetupDraft>(SetupController.new);
