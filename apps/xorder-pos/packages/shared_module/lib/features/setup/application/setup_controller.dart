import 'dart:convert' show jsonEncode;
import 'dart:io' show Platform;
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../core/config/lan_tls.dart';
import '../../../core/config/platform_endpoint.dart';
import '../../../core/config/printer_config.dart';
import '../../../core/config/terminal_config.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../data/config/installer_credentials.dart';
import '../../../data/config/setup_progress_store.dart';
import '../../../data/postgres/local_bootstrap.dart';
import '../../../domain/models/content_languages.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/repositories/repositories.dart'
    show ClaimNotice, DiscoveredPrinter, PosBranch, PosTerminalSummary;
import '../../../data/postgres/pos_database.dart';
import '../../licensing/data/licence_service.dart';
import '../../licensing/data/site_licence.dart';
import '../../licensing/domain/license.dart';
import '../../licensing/domain/license_verifier.dart'
    show LicenseFile, LicenseVerifier;
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

    // The Settings bar's language switch is on every screen of this wizard,
    // and whoever is standing here has the last word — including after a
    // claim has set the business's own language. The draft used to keep the
    // claim's answer regardless, and `complete()` wrote THAT to disk and
    // applied it, so a till switched to English on the last screen booted in
    // Arabic. The draft now follows the bar.
    ref.listen<Locale>(localeProvider, (_, next) {
      if (_disposed || stateOrNull == null) return;
      if (next.languageCode != state.locale) {
        state = state.copyWith(locale: next.languageCode);
      }
    });

    // A licence installed on an earlier run is still installed — it is a file,
    // and it outlived the process that wrote it. Reading it back is what stops
    // a restart mid-setup from asking for a licence this machine already holds.
    Future.microtask(_restoreInstalledLicence);

    // The seed, not the boot snapshot: a reset deletes `config.json` mid-process
    // and the wizard must reopen as a fresh install, not as the terminal that
    // was just cleared. Seeding from the dead config is what made a till refuse
    // the next business's licence for belonging to the wrong tenant.
    final saved = ref.watch(terminalSeedProvider).config;
    // The app's one mode, or null in the shared package (pos-split-apps). A
    // fresh draft opens in it; a saved one is already in it, because the boot
    // refused a configuration the other app wrote (BR-8, `TerminalBoot`).
    final appMode = ref.read(appModeProvider);
    if (saved == null) {
      final profile = ref.read(terminalProfileProvider);
      // Decided by the device, before the first screen — a tablet is a child
      // of the main device and opens on finding it. See [TerminalRole].
      final role = ref.read(deviceRoleProvider);
      final child = role == TerminalRole.child;

      // A claim made on an earlier run is still made — the code is spent and
      // the platform holds the terminal. Reading it back is what stops a
      // restart mid-setup from asking for a pairing code that cannot be
      // redeemed twice. A child is included now: it never claims, but it does
      // register, and a registration spends a seat the same way.
      Future.microtask(_restoreProgress);

      // The draft's own mode: the app's, or — in the shared package on its
      // own — the unconfigured default.
      final cloudMain =
          (appMode ?? DeploymentConfig.unconfigured.mode) ==
              DeploymentMode.cloud &&
          !child;
      return SetupDraft(
        step: _firstStep(child: child, cloud: cloudMain),
        appMode: appMode,
        // Blank rather than localhost for a child: its database is never on
        // the tablet, and a pre-filled `localhost` is an answer it must not
        // be able to accept by pressing on.
        deployment: DeploymentConfig.unconfigured.copyWith(
          mode: appMode,
          role: role,
          databaseHost: child ? '' : null,
          // The platform the owner signs in to. It used to come off the
          // licence step, which the cloud path no longer has
          // (pos-cloud-sign-in-setup); there is one hosted platform and the
          // build names it.
          baseUrl: cloudMain ? PlatformEndpoint.base : null,
        ),
        // A reset keeps this machine's identity on purpose — the licence is
        // pinned to it — and once the file is gone the profile is the only
        // place still holding it. Minting a new one here would unpin the
        // licence this till already has.
        terminalId: profile.terminalId,
        installationId: profile.installationId,
        // Likewise the language: the screen is in Arabic because this terminal
        // was set up in Arabic, and a wizard that quietly defaulted back to
        // English would write English to disk at the end of a reconfiguration
        // nobody asked to change the language of.
        locale: ref.read(localeProvider).languageCode,
      );
    }

    return SetupDraft(
      step: _firstStep(
        child: saved.deployment.isChild,
        cloud: saved.deployment.mode == DeploymentMode.cloud,
      ),
      appMode: appMode,
      locale: saved.languageCode,
      deployment: saved.deployment,
      branchId: saved.terminal.branchId,
      branchLabel: saved.terminal.branchName,
      businessId: saved.terminal.businessId,
      branchCode: saved.terminal.branchCode,
      terminalName: saved.terminal.terminalName ?? '',
      // Kept above all: reissuing it would hand the licence server a machine it
      // has never seen, and the activation on this till would stop matching.
      terminalId: saved.terminal.terminalId,
      installationId: saved.terminal.installationId,
      claimed: saved.terminal.provisioned,
    );
  }

  /// Where the wizard opens: a child finds its main device, a cloud till signs
  /// in (it has no licence step, pos-cloud-sign-in-setup), and an offline till
  /// starts at its licence.
  static SetupStep _firstStep({required bool child, required bool cloud}) =>
      child
      ? SetupStep.deployment
      : cloud
      ? SetupStep.account
      : SetupStep.licence;

  /// True once this controller has been disposed, so the licence restore — the
  /// one thing here that outlives its own build — cannot touch a dead state.
  bool _disposed = false;

  /// Adopt the licence already on this machine.
  ///
  /// Only ever fills a gap: an activation the operator performs while this is
  /// in flight wins, because that is the newer intent. A machine with no
  /// licence installed lands here and changes nothing.
  Future<void> _restoreInstalledLicence() async {
    // A child holds no licence file; its licence is read from the main device
    // once the tablet has found it.
    if (_disposed || state.entitlement != null || state.deployment.isChild) {
      return;
    }

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
    // Judged on the draft's own mode, which is the app's (pos-split-apps). It
    // used to be re-judged on whichever mode the licence covered, and the
    // draft moved there with a notice saying so; with the mode fixed by the
    // app, a licence for the other mode is a refusal naming that app, not a
    // move.
    state = state.copyWith(
      entitlement: first,
      claims: claims,
      // Same adoption as a fresh activation: the tenant and the terminal count
      // come off the licence, not off anything typed.
      deployment: claims == null ? null : _adopt(claims),
      // `copyWith` reads a null notice as "leave it alone", so clearing needs
      // the flag — otherwise a stale notice outlives what raised it.
      clearNotice: true,
    );
  }

  /// Carry on from a claim an earlier run made.
  ///
  /// The pairing code is single-use and the device token it earned was
  /// persisted the moment it arrived, so a restart between the claim and "Open
  /// the till" left the machine with a terminal on the platform and a wizard
  /// that had never heard of it — blank at the licence step, demanding a claim
  /// at the account step, with a code that now answers `PAIRING_CODE_USED`.
  /// The only way past was "sign in instead", which nobody at the till had
  /// been told about.
  ///
  /// So the draft is rebuilt from what the claim answered and the wizard
  /// reopens on the connecting step, whose pane runs provisioning on its own.
  /// Every step of that is an upsert, so a database half-built before the
  /// restart costs nothing to finish.
  ///
  /// An offline or child till resumes from its registration the same way,
  /// but on the deployment screen: the database passwords are typed there and
  /// are in no file. A record written before a registration that never came
  /// back gives up its installation id and nothing else — see
  /// [SetupProgress.claimed].
  ///
  /// Only ever fills a gap, like [_restoreInstalledLicence]: a wizard the
  /// operator has already moved off the first screen keeps what they did.
  Future<void> _restoreProgress() async {
    if (_disposed) return;

    final SetupProgress? progress;
    try {
      progress = await ref.read(setupProgressStoreProvider).read();
    } catch (_) {
      // Started in a microtask, so an unreadable store would surface as an
      // unhandled async error rather than a failed step. The store reports a
      // missing or damaged file as null already; what is left is the platform
      // refusing to name the support directory, and a wizard that works
      // without a progress file must not be stopped by it.
      return;
    }
    if (_disposed || progress == null) return;
    // The first step of this device's path: the licence on a main device, the
    // deployment screen on a child.
    if (state.claimed || state.step != state.visibleSteps.first) return;
    // Written by the other kind of device. The role is the installer's marker
    // file, not the wizard's, so a record that disagrees with it belongs to an
    // install that no longer exists and resuming it would be guessing.
    if (progress.deployment.isChild != state.deployment.isChild) return;

    // The identity first, and on its own: it is the one thing worth taking
    // from a record whose registration never came back. This machine's
    // installation id was minted in memory when this process started, and
    // the branch database's upsert is keyed on the one the earlier run sent;
    // a re-run under the new id would be a second terminal and a second seat.
    // The profile is moved as well as the draft, because the licence service
    // fingerprints the profile's — a licence activated on the earlier run is
    // pinned to the earlier id, and judged under a fresh one it would not
    // match.
    final installationId = progress.installationId;
    if (installationId != null &&
        installationId.isNotEmpty &&
        installationId != state.installationId) {
      final profile = ref.read(terminalProfileProvider);
      ref
          .read(terminalProfileProvider.notifier)
          .apply(
            TerminalProfile(
              terminalId: profile.terminalId,
              installationId: installationId,
            ),
          );
      state = state.copyWith(installationId: installationId);
    }
    if (!progress.claimed) return;

    // The licence the bundle embedded, judged again rather than trusted: the
    // file is signed, and re-verifying costs nothing. Null when the wizard was
    // carrying none — that one is on disk and [_restoreInstalledLicence] finds
    // it, in whichever order the two microtasks land.
    var entitlement = state.entitlement;
    var claims = state.claims;
    final licence = progress.licence == null
        ? null
        : LicenseFile.tryParse(progress.licence!);
    if (licence != null) {
      entitlement = await ref
          .read(licenceServiceProvider)
          .evaluate(licence, progress.deployment);
      claims = LicenseVerifier.claimsOf(licence);
    }
    if (_disposed ||
        state.claimed ||
        state.step != state.visibleSteps.first) {
      return;
    }

    // A cloud main device carries on at the connecting step, which asks
    // nothing. An offline or child till cannot: its database passwords were
    // typed on the deployment screen and are, rightly, in no file, so it opens
    // there with everything else filled in and its registration already made
    // — the terminal step's Register button is dead on a claimed draft, so the
    // seat is not spent again on the way through.
    final cloud =
        progress.deployment.mode == DeploymentMode.cloud &&
        !progress.deployment.isChild;
    state = state.copyWith(
      step: cloud ? SetupStep.connecting : SetupStep.deployment,
      // The offline account step lets only a built database through, and a
      // till that registered had built one. Only a claimed record gets this
      // far: skipping the build on an unclaimed one would also skip asking for
      // the first administrator, whom the registration then signs in as.
      bootstrapped: progress.bootstrapped,
      locale: progress.locale,
      deployment: progress.deployment,
      entitlement: entitlement,
      claims: claims,
      licenceFile: licence,
      claimed: true,
      branchId: progress.branchId,
      branchLabel: progress.branchLabel,
      businessId: progress.businessId,
      branchCode: progress.branchCode,
      terminalName: progress.terminalName,
      terminalId: progress.terminalId,
      // Said out loud by the connecting screen's report — a notice here would
      // be cleared the moment provisioning starts — because a wizard that
      // opens on its fourth screen with nothing typed looks like a fault to
      // whoever restarted it.
      resumed: true,
    );
    if (progress.locale case final locale?) {
      ref.read(localeProvider.notifier).apply(locale);
    }
  }

  /// The claim, on disk, until the wizard finishes — see [_restoreProgress].
  ///
  /// Best effort: a progress file that cannot be written costs a restart its
  /// resume, not the claim its success. Every kind of till: this used to be
  /// cloud main devices only, on the reasoning that an offline till registers
  /// with nothing left to lose — but its registration spends a seat of the
  /// licence, and a re-run that registered again spent another.
  ///
  /// [claimed] false is the record written just before an offline or child
  /// registration is sent: the installation id it is keyed on, down on disk
  /// before the row exists, so that a process killed in between comes back as
  /// the same machine. See [SetupProgress.claimed].
  Future<void> _rememberProgress({bool claimed = true}) async {
    final terminalId = state.terminalId;
    if (terminalId == null || terminalId.isEmpty) return;

    try {
      await ref
          .read(setupProgressStoreProvider)
          .write(
            SetupProgress(
              deployment: state.deployment,
              terminalId: terminalId,
              terminalName: state.terminalName,
              locale: state.locale,
              branchId: state.branchId,
              branchLabel: state.branchLabel,
              businessId: state.businessId,
              branchCode: state.branchCode,
              licence: state.licenceFile?.serialize(),
              installationId: state.installationId,
              claimed: claimed,
              bootstrapped: state.bootstrapped,
            ),
          );
    } on Exception catch (error) {
      debugPrint('setup[progress] not written: $error');
    }
  }

  void setLocale(String locale) => state = state.copyWith(locale: locale);

  // There is no `setMode` (pos-split-apps, stage 4). Cloud and offline are two
  // apps, and the mode is the one the installer launched; a switch here could
  // only ever have been reached by the shared package's own tests, which now
  // say which app they are instead.

  /// A platform address typed without a scheme still means what the operator
  /// meant: `localhost:8100` is `http://localhost:8100`, `xorder.io` is
  /// `https://xorder.io`. A scheme-less URL silently mis-parses in the HTTP
  /// client (the host becomes the scheme), which surfaces two screens later as
  /// "could not be reached" — the exact class of trap the slug field already
  /// guards against. Private hosts default to http because nobody runs TLS on
  /// a dev loopback; anything public defaults to https, never the reverse.
  static String baseUrlFrom(String input) {
    final value = input.trim();
    if (value.isEmpty) return value;
    if (value.contains('://')) {
      final uri = Uri.tryParse(value);
      if (uri != null &&
          uri.scheme == 'http' &&
          !DeploymentConfig.isPermittedPlatformUrl(value)) {
        // Never preserve an operator's accidental public plaintext URL.  The
        // later reachability check makes a genuinely HTTPS-only server clear.
        return uri.replace(scheme: 'https').toString();
      }
      return value;
    }
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

  // Every connection edit below forgets a child's link to its main device: the
  // licence on the draft was read from the database as it was addressed then.
  //
  // The address also forgets the server's certificate: a pin belongs to the
  // server it was confirmed against, and carrying it to another address
  // would either refuse a server that is fine or — worse — be the reason a
  // technician reaches for the plaintext override.
  void setDatabaseHost(String host) => state = state.copyWith(
    deployment: state.deployment.copyWith(
      databaseHost: host.trim(),
      clearPinnedCertificate: true,
    ),
    mainDeviceLinked: false,
    clearPresentedCertificate: true,
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
    final current = state.deployment;
    final cloud = current.mode == DeploymentMode.cloud && !current.isChild;
    // Off the cloud path the licence names the tenant, and it is not retyped.
    // A cloud till has no licence step: the owner types the business address.
    if (state.claims != null && !cloud) return;
    final next = slugFrom(slug);
    // Named after the business, as the licence step used to name it
    // (`_adopt`): unless somebody else already named it. A name the installer
    // wrote replaces it at the connecting step, as before.
    final derived =
        current.databaseName == DeploymentConfig.defaultDatabaseName ||
        current.databaseName ==
            DeploymentConfig.databaseNameFor(current.tenantSlug ?? '');
    state = state.copyWith(
      deployment: current.copyWith(
        tenantSlug: next,
        databaseName: cloud && derived && next.isNotEmpty
            ? DeploymentConfig.databaseNameFor(next)
            : null,
      ),
      // A pull that happened under the old slug now describes the wrong
      // business; forgetting it is what keeps the branch step honest.
      clearConnection: true,
    );
  }

  /// Trust the certificate the server presented — the technician has compared
  /// its fingerprint with the one on the main device and pressed the button.
  ///
  /// Then tries again at once, through the same step that was refused, so
  /// the confirmation is judged by a real connection rather than by the
  /// button. Pairing also clears any plaintext override: a till that can be
  /// encrypted is.
  ///
  /// There is no "trust without a certificate" here any more. The wizard is
  /// where a till is set up, so it only ever sets one up encrypted; turning
  /// encryption off is a technician's audited act in Management.
  Future<void> trustPresentedCertificate() async {
    final presented = state.presentedCertificate;
    if (presented == null) return;
    state = state.copyWith(
      deployment: state.deployment.copyWith(
        pinnedCertificateSha256: presented.sha256,
        pinnedCertificatePem: presented.pem,
        allowInsecureLan: false,
      ),
      clearPresentedCertificate: true,
      clearError: true,
    );
    if (state.deployment.isChild) {
      await connectToMainDevice();
    } else {
      await testConnection();
    }
  }

  /// Why the secure connection to [config]'s server was refused, and — when
  /// a fingerprint comparison would settle it — the certificate to compare.
  ///
  /// Asks the server directly rather than reading the driver's error,
  /// because the driver only says *that* a certificate was refused. Nothing
  /// is retried in the clear, here or anywhere: the answer is a sentence and,
  /// at most, a fingerprint waiting for a person.
  Future<String> _explainTlsRefusal(DeploymentConfig config) async {
    final s = ref.read(stringsProvider);
    final host = config.databaseHost.trim();
    final fetch = await ref
        .read(serverCertificateProbeProvider)
        .fetch(host, config.databasePort);
    final diagnosis = LanTls.diagnose(pin: config.lanTls.pin, fetch: fetch);

    final offer = switch (diagnosis) {
      LanTlsDiagnosis.untrusted || LanTlsDiagnosis.changed =>
        fetch is CertificateFetched ? fetch.certificate : null,
      _ => null,
    };
    state = state.copyWith(
      presentedCertificate: offer,
      clearPresentedCertificate: offer == null,
    );

    return switch (diagnosis) {
      LanTlsDiagnosis.untrusted => s.tlsUntrusted,
      LanTlsDiagnosis.changed => s.tlsCertificateChanged,
      LanTlsDiagnosis.nameMismatch => s.tlsNameMismatch(host),
      LanTlsDiagnosis.notOffered => s.tlsNotOffered,
      LanTlsDiagnosis.unreachable => s.tlsFailure(),
    };
  }

  void setDatabaseName(String name) => state = state.copyWith(
    deployment: state.deployment.copyWith(databaseName: name.trim()),
    mainDeviceLinked: false,
    clearError: true,
  );

  void setDatabaseUser(String user) => state = state.copyWith(
    deployment: state.deployment.copyWith(databaseUser: user.trim()),
    mainDeviceLinked: false,
    clearError: true,
  );

  void setDatabasePort(String port) {
    final parsed = int.tryParse(port.trim());
    if (parsed == null || parsed <= 0 || parsed > 65535) return;
    state = state.copyWith(
      deployment: state.deployment.copyWith(
        databasePort: parsed,
        clearPinnedCertificate: true,
      ),
      mainDeviceLinked: false,
      clearPresentedCertificate: true,
    );
  }

  /// Held on the draft only until [publishCredentials] hands it to the store.
  void setDatabasePassword(String password) => state = state.copyWith(
    databasePassword: password,
    mainDeviceLinked: false,
    clearError: true,
  );

  /// The role that creates the database and owns its tables.
  ///
  /// Editable, because the default is only right on a machine the Windows
  /// installer prepared: `pos_admin` is something `provision.ps1` creates, and
  /// on a laptop with a hand-installed PostgreSQL the only role that can
  /// `CREATE DATABASE` is usually `postgres`. Hard-coding it turned that into
  /// an authentication failure with no field to answer it in.
  void setAdminDatabaseUser(String user) => state = state.copyWith(
    deployment: state.deployment.copyWith(adminDatabaseUser: user.trim()),
    clearError: true,
  );

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

  /// The PIN again, held to the same rules as the first — digits only, never
  /// longer than [SetupDraft.pinLength] — so the two can only differ by being
  /// different, never by one having been silently cut.
  void setOwnerPinConfirm(String pin) {
    final digits = pin.replaceAll(RegExp(r'[^0-9]'), '');
    state = state.copyWith(
      ownerPinConfirm: digits.length > SetupDraft.pinLength
          ? digits.substring(0, SetupDraft.pinLength)
          : digits,
      clearError: true,
    );
  }

  /// Which of the first-install step's two screens shows. Typed values are
  /// kept: they live in the draft, not in the screen.
  void showOwnerPage(OwnerPage page) =>
      state = state.copyWith(ownerPage: page, clearError: true);

  /// The footer's one button on the first install, before the database exists.
  /// On the first page it moves to the second; on the second it builds.
  void footerPressed() {
    // The footer closure may be one frame stale: a second press while the build
    // runs must not start a second build.
    if (state.busy) return;
    switch (state.footerAction) {
      case FooterAction.toOwnerPage:
        if (state.footerEnabled) showOwnerPage(OwnerPage.ownerAccount);
      case FooterAction.createDatabase:
        if (state.footerEnabled) bootstrapDatabase();
      case FooterAction.next || FooterAction.finish:
        break; // The wizard's own buttons, unchanged.
    }
  }

  /// Build this machine's database, from nothing.
  ///
  /// The offline path used to start at a command line: `PosMigrator` ran only
  /// on the cloud claim path, so an offline business needed somebody at a
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
    // Typed twice because it cannot be read back. Said here, with nothing
    // built: a PIN with a typo in it would be the owner's lock-out.
    if (!state.pinsMatch) {
      state = state.copyWith(error: s.pinsDoNotMatch);
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

      // The account every sale after tonight connects with, created here if
      // PostgreSQL does not already have it — see
      // [LocalBootstrap.ensureTillRole]. Before the grants, which are what
      // need it, and before the migrations, so a machine that cannot make the
      // role at all says so before it has written a schema.
      if (state.databasePassword.isNotEmpty &&
          await LocalBootstrap.ensureTillRole(
            admin,
            state.adminDatabasePassword,
            name: state.deployment.databaseUser,
            password: state.databasePassword,
          )) {
        done.add(s.tillRoleCreated(state.deployment.databaseUser));
      }

      final applied = await bootstrap.migrate(admin);
      done.add(
        applied.isEmpty
            ? s.schemaAlreadyCurrent
            : s.migrationsApplied(applied.length),
      );

      final businessId = await bootstrap.seedBusiness(
        admin,
        slug: claims.tenantSlug,
        name: claims.tenantName,
        // The language chosen on the wizard's first screen is the language the
        // menu is written in (XORD-035): one name box on every form.
        contentLanguages: ContentLanguages.fromLocale(state.locale),
      );
      final branchId = await bootstrap.seedBranch(
        admin,
        businessId: businessId,
        name: 'Main',
        code: 'MAIN',
      );
      done.add(s.businessSeeded(claims.tenantName));

      final roles = await bootstrap.seedSystemRoles(admin, businessId);
      done.add(
        roles.created == 0
            ? s.rolesAlreadyThere
            : s.rolesCreated(roles.created),
      );

      // Void, refund, discount and price-override reasons. Seeded here rather
      // than left to migration 9, which can only reach businesses that already
      // existed when it ran — and this one is being created now.
      await bootstrap.seedReasonCodes(admin, businessId);
      // The rate this branch charges, named — so products can be classified
      // and an ETA filing has something to put beside its figures.
      await bootstrap.seedTaxGroup(admin, businessId);
      // The four payment methods (§40). Migration 23 seeds businesses that
      // existed when it ran; this one did not.
      await bootstrap.seedTenderTypes(admin, businessId);
      // And what each kind of order requires (§31).
      await bootstrap.seedOrderTypes(admin, businessId);

      final owner = await bootstrap.seedOwner(
        admin,
        businessId: businessId,
        branchId: branchId,
        roleId: roles.ids[SystemRoles.ownerCode]!,
        name: state.ownerName.trim(),
        username: state.ownerUsername.trim(),
        pin: state.ownerPin,
      );
      switch (owner) {
        case OwnerCreated():
          done.add(s.ownerCreated(state.ownerName.trim()));
        case OwnerAlreadyHere():
          done.add(s.ownerAlreadyHere(state.ownerUsername.trim()));
        case AnotherOwnerActive(:final name, :final username):
          // Stopped here, before the grants, and not reported as built: the
          // person typed into this form does not exist, and a green report
          // would send the installer on to a till they cannot sign in to as
          // themselves. Every step above is an upsert, so building again once
          // the username is theirs repeats nothing.
          state = state.copyWith(
            busy: false,
            error: s.ownerAlreadyExists(name, username),
          );
          return;
      }

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
    } on TillRoleRefused catch (refusal) {
      // The administrator account's doing, so back to where its password is.
      state = state.copyWith(
        busy: false,
        ownerPage: OwnerPage.databaseAccess,
        error: s.tillRoleRefused(refusal.role, refusal.admin),
      );
    } on PosDbException catch (error) {
      state = state.copyWith(
        busy: false,
        // A password, a role or a connection that is wrong is on the first page
        // — the field is there, the button was on the second. Anything else
        // stays beside what was just typed.
        ownerPage: isAdminAccessFailure(error.failure)
            ? OwnerPage.databaseAccess
            : null,
        error: _bootstrapFailure(error),
      );
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

  /// Whether a database failure is about the administrator account or the road
  /// to it: what the first-install step's first page asks for.
  @visibleForTesting
  static bool isAdminAccessFailure(PosDbFailure failure) => switch (failure) {
    PosDbFailure.auth ||
    PosDbFailure.missingRole ||
    PosDbFailure.permissionDenied ||
    PosDbFailure.dns ||
    PosDbFailure.tcp ||
    PosDbFailure.tls => true,
    _ => false,
  };

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

  /// Everything a successful claim still has to say, in one paragraph.
  ///
  /// The repository used to hand over an English sentence and this took it at
  /// face value, which is how an Arabic wizard told an Arabic installer
  /// "Catalog will be fetched on first sync." Codes in, words out — the same
  /// division [_refusal] makes.
  String? _claimNotices(List<ClaimNotice> notices) {
    if (notices.isEmpty) return null;
    final s = ref.read(stringsProvider);
    return [for (final notice in notices) claimNotice(s, notice)].join(' ');
  }

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
      // Not the first-install reassurance `_describe` gives this failure. There
      // the next step is what builds the database; here the build has just run,
      // so "the next step creates it" would be telling the operator to wait for
      // something that already happened. What is left is a role that may log in
      // and may not CREATE DATABASE.
      PosDbFailure.missingDatabase => s.bootstrapDatabaseMissing(
        state.deployment.databaseName,
        state.deployment.adminDatabaseUser,
      ),
      // The role the DRIVER named, not the one this step happened to be
      // holding: a build connects as the administrator and grants to the till,
      // and naming the wrong one of those is how an installer ends up
      // correcting a field that was right. `pos_till` is created by the build
      // now, so what is left here is nearly always the administrator — whose
      // field is directly above this message.
      PosDbFailure.missingRole => switch (PosDbException.roleNamedIn(
        error.raw,
      )) {
        final role?
            when role != state.deployment.adminDatabaseUser =>
          s.roleMissing(role),
        final role => s.bootstrapAdminRoleMissing(
          role ?? state.deployment.adminDatabaseUser,
        ),
      },
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
    businessId: state.businessId,
    branchCode: state.branchCode,
  );

  /// The printer this wizard just pointed the till at.
  ///
  /// **The hardware step used to end here.** A printer picked in the scan was
  /// held in the draft and never written anywhere, so the till came up the next
  /// morning with no address to send a receipt to — the printing path had
  /// nothing to be configured with, and setup had appeared to configure it.
  PrinterConfig get printer => PrinterConfig(
    name: state.printerName,
    paperWidthDots: state.paperWidthDots,
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
        if (profile.businessId == null) s.missingBusinessIdentity,
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
      // The back office's database password, when this wizard was given one —
      // an offline install builds its database with it. Kept so Admin Mode can
      // be a username and a PIN; see [adminDbSecretStoreProvider] for what that
      // costs and why it was chosen. A wizard that was not given one leaves
      // Admin Mode to ask for it once, the first time.
      if (state.adminDatabasePassword.isNotEmpty) {
        await ref
            .read(adminDbSecretStoreProvider)
            .write(state.adminDatabasePassword);
      }
      // The licence, carried in memory since the first screen. It goes down
      // BEFORE the config file, because the config file is what makes this
      // machine a configured terminal at the next boot, and a configured
      // terminal that cannot find its licence opens on "Not licensed" with no
      // way to explain itself. Null when the licence was restored from disk
      // rather than activated — see [SetupDraft.licenceFile].
      if (state.licenceFile case final licence?) {
        await ref.read(licenceServiceProvider).store(licence);
      }
      await ref
          .read(terminalConfigStoreProvider)
          .write(
            SavedTerminalConfig(
              deployment: state.deployment,
              terminal: profile,
              languageCode: state.locale,
              printer: printer,
            ),
          );
      // The claim's own record is finished with once the config exists: from
      // the next boot the terminal is configured, and a progress file left
      // behind would only be read by a wizard nobody will see again — until a
      // reset, when it would resume the wrong install.
      await ref.read(setupProgressStoreProvider).clear();
    } on Exception catch (error) {
      final message = s.couldNotSaveSetup(error);
      state = state.copyWith(error: message);
      return message;
    }

    ref.read(localeProvider.notifier).apply(state.locale);
    ref.read(deploymentProvider.notifier).apply(state.deployment);
    // The licence reached disk a moment ago, and the start screen this hands
    // over to reads the INSTALLED one rather than the draft's copy.
    ref.invalidate(licenceEntitlementProvider);
    // In memory as well as on disk. Setup finishes without a restart, so a till
    // that only wrote the file would take its first sale with no printer — the
    // provider reads the boot config, and the boot config is last night's.
    ref.read(printerConfigProvider.notifier).apply(printer);
    ref.read(terminalProfileProvider.notifier).apply(profile);
    ref.read(setupCompleteProvider.notifier).markComplete();
    return null;
  }

  void setSyncPolicy(SyncPolicy policy) => state = state.copyWith(
    deployment: state.deployment.copyWith(syncPolicy: policy),
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

  /// 576 dots for an 80mm roll, 384 for 58mm. See
  /// [PrinterConfig.paperWidthDots] for why this is asked rather than guessed.
  void setPaperWidth(int dots) =>
      state = state.copyWith(paperWidthDots: dots);
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

    // The pool refuses to open without a password, so probing with an empty one
    // reported "PostgreSQL rejected the username or password" for a refusal
    // PostgreSQL never made (report 2026-10-24, F-1). Said as what it is.
    if (state.databasePassword.isEmpty) {
      state = state.copyWith(
        busy: false,
        error: ref.read(stringsProvider).databasePasswordRequired,
      );
      return false;
    }

    // Probe with what the operator just typed, not with whatever the store
    // holds from an earlier attempt.
    ref.read(posDbCredentialsStoreProvider).set(state.databasePassword);
    final failure = await ref.read(posDatabaseProvider).probe(config);

    // A database that does not exist yet is not a failure of THIS step. It is
    // the ordinary state of a first install, and the very next step is what
    // creates it — the message says exactly that, and said it in red, which
    // taught the installer something was wrong at the moment nothing was. The
    // only two outcomes that belong in red here are the ones that stop the
    // wizard: an address that cannot be reached, or a login that is refused.
    final expected = failure == PosDbFailure.missingDatabase;
    final s = ref.read(stringsProvider);

    if (failure == PosDbFailure.tls) {
      final why = await _explainTlsRefusal(config);
      state = state.copyWith(busy: false, error: why, clearNotice: true);
      return false;
    }

    // Success used to be SILENT — the error bar cleared and nothing took its
    // place, so the only difference between "it worked" and "the button does
    // nothing" was the absence of red. A test whose good outcome is invisible
    // is a test nobody trusts.
    state = state.copyWith(
      busy: false,
      error: expected ? null : _describe(failure, config),
      clearError: expected || failure == null,
      notice: switch (failure) {
        null => s.connectionOk(config.databaseName),
        _ when expected => s.missingDatabase(config.databaseName),
        _ => null,
      },
      clearNotice: failure != null && !expected,
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
      // The connection test signs in as the till and runs `SELECT 1`, so the
      // till is the only role either half could be about.
      PosDbFailure.missingRole => s.roleMissing(config.databaseUser),
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
  /// for one. It does not choose the mode: that is the app's, and a licence
  /// that does not cover it is refused here, naming the other app (BR-2).
  Future<void> activateLicence({String? fileContents}) async {
    // A child activates nothing; see [connectToMainDevice].
    if (state.deployment.isChild) return;

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
          // business's licence unable to accept another's, which is exactly
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
          // Held, not installed. This is step one of ten, and a licence written
          // here survives a wizard abandoned on any of the nine that follow —
          // an owner trying a key to see what it covers, an installer who never
          // gets past the database password. `complete()` writes it, once this
          // terminal is a terminal.
          persist: false,
        );

    final claims = result.claims;
    final adopted = claims == null ? state.deployment : _adopt(claims);
    final entitlement = result.entitlement;

    // `result.notice` speaks for the verdict, and it is the only thing that
    // speaks at all when there was no verdict to give — an unrecognised key or
    // a file that is not a licence never reach the verifier.
    final notice = result.notice;

    state = state.copyWith(
      busy: false,
      entitlement: entitlement,
      claims: claims,
      // Carried until `complete()`. A licence that refuses trade is carried
      // too: setup may well be finished on one inside its grace window, and the
      // terminal must end up holding the file its status screen describes.
      licenceFile: result.file,
      deployment: claims == null ? null : adopted,
      // Said once. A verdict is drawn by the pane's status card, headline and
      // notice together, so the error bar at the foot repeats it only when
      // there is no verdict to draw — an unrecognised key, an unreachable
      // platform, a file that is not a licence. The same sentence twice on one
      // screen read as two problems.
      error: entitlement != null && identical(entitlement.notice, notice)
          ? null
          : notice?.text(ref.read(stringsProvider)),
      clearNotice: true,
    );
  }

  /// Fold what the licence knows into the deployment config.
  ///
  /// The tenant is taken from the licence rather than typed, because a licence
  /// is issued to exactly one tenant and asking the operator to name it again
  /// only creates a mismatch to diagnose later.
  ///
  /// The mode is NOT taken from it (pos-split-apps, stage 4). It used to be:
  /// a licence that did not cover the draft's mode moved the draft to one it
  /// did, with a notice saying so. The mode is the app's now, and moving off it
  /// would turn this app into the other one; a licence that does not cover it
  /// is refused at this step instead (`modeNotLicensed`, naming that app).
  DeploymentConfig _adopt(LicenseClaims claims) {
    final current = state.deployment;
    final mode = current.mode;

    return current.copyWith(
      tenantSlug: claims.tenantSlug,
      // The platform address, supplied rather than typed (owner decision,
      // 2026-09-15). There is exactly one hosted platform and the build already
      // names it; the field on the old connection screen could only ever be
      // filled in with what `PlatformEndpoint` already says, or filled in
      // wrongly. An address the operator DID type survives — a staging box or a
      // developer's stack is the one case where it is a real question.
      baseUrl: mode.needsBaseUrl && (current.baseUrl?.isEmpty ?? true)
          ? _platformFor(current)
          : current.baseUrl,
      databaseHost: claims.maxTerminals > 1
          ? current.databaseHost
          : DeploymentConfig.localhost,
      // Named after the business, unless somebody already named it: the
      // wizard builds this database, and `demo_db` says whose it is where
      // `xorder_pos` said nothing (owner decision, 16 Oct 2026). A name the
      // installer wrote replaces it at the connecting step, as before.
      databaseName: current.databaseName == DeploymentConfig.defaultDatabaseName
          ? DeploymentConfig.databaseNameFor(claims.tenantSlug)
          : current.databaseName,
    );
  }

  /// The platform a cloud till talks to, when nobody typed one.
  ///
  /// The licence server, if the operator named one on the licence step, and
  /// the build's own default otherwise. On the cloud path the platform that
  /// licenses a till is the platform that takes its money — there is one —
  /// so a key activated against an address IS that address being named.
  /// Before this the licence step could say xorder.io and the claim two
  /// screens later still went to the build default, which on a developer's
  /// machine is the local stack: the pairing code the dashboard had just
  /// issued came back "not recognised", truthfully, from a platform that had
  /// never heard of it (16 Oct 2026).
  static String _platformFor(DeploymentConfig current) {
    final licenceServer = current.licenceServerUrl;
    return licenceServer != null && licenceServer.isNotEmpty
        ? licenceServer
        : PlatformEndpoint.base;
  }

  /// A child tablet's whole connection step: reach the main device's database
  /// with what is on screen, and adopt the licence it shares there.
  ///
  /// The shared licence does for a child what an activated one does for a main
  /// device — it names the tenant and the mode, so the tablet is asked for
  /// neither. It is judged `viaMainDevice` (see `LicenseVerifier`): signature,
  /// tenant and dates as usual, and the main device's fingerprint pin not held
  /// against a tablet that was never going to match it.
  Future<void> connectToMainDevice() async {
    final s = ref.read(stringsProvider);
    if (!state.deployment.isChild) return;

    // Said before trying, because trying would succeed against a PostgreSQL
    // that happens to run on the tablet and the tablet would be its own child.
    if (state.deployment.isLoopback) {
      state = state.copyWith(error: s.mainDeviceIsThisTablet);
      return;
    }

    state = state.copyWith(
      busy: true,
      mainDeviceLinked: false,
      clearError: true,
      clearNotice: true,
    );
    _publishDeployment();

    final SiteLicence? site;
    try {
      site = await ref.read(siteLicenceSourceProvider)?.read();
    } on PosDbException catch (error) {
      // The same four causes the main device's own test names, because they
      // are the same four things — an installer sent to open a firewall when
      // the password is wrong will not fix it.
      final why = error.failure == PosDbFailure.tls
          ? await _explainTlsRefusal(state.deployment)
          : _describe(error.failure, state.deployment);
      state = state.copyWith(busy: false, error: why);
      return;
    }

    final claims = site == null ? null : LicenseVerifier.claimsOf(site.file);
    if (site == null || claims == null) {
      state = state.copyWith(busy: false, error: s.mainDeviceHasNoLicence);
      return;
    }

    // One app per machine, and so per branch database (pos-split-apps, BR-8):
    // the main device published its mode with the licence, and a child of the
    // other app does not join it. Said before the mode below is copied in,
    // which would otherwise turn this app into the other one.
    if (state.appMode case final fixed? when site.mode != fixed) {
      state = state.copyWith(
        busy: false,
        error: s.databaseSetUpByOtherApp(site.mode.productName),
      );
      return;
    }

    final deployment = state.deployment.copyWith(
      mode: site.mode,
      tenantSlug: claims.tenantSlug,
    );
    // Published before judging, so the service that judges is the child's.
    ref.read(deploymentProvider.notifier).apply(deployment);
    final entitlement = await ref
        .read(licenceServiceProvider)
        .evaluate(site.file, deployment);

    state = state.copyWith(
      busy: false,
      deployment: deployment,
      claims: claims,
      entitlement: entitlement,
      mainDeviceLinked: true,
      error: entitlement.canSell ? null : entitlement.notice?.text(s),
      notice: entitlement.canSell
          ? s.mainDeviceLinked(
              claims.tenantName.isEmpty ? claims.tenantSlug : claims.tenantName,
            )
          : null,
    );
  }

  /// Hold a licence that arrived from somewhere other than the licence step.
  ///
  /// The bootstrap bundle a cloud claim carries has one embedded, so a cloud
  /// terminal is licensed without anyone typing a key. It is held rather than
  /// installed for the reason every other licence here is — the claim happens
  /// at step six of ten — and it supersedes whatever the operator activated,
  /// because it is the platform's own current copy for this terminal.
  void holdLicence(LicenseFile file) =>
      state = state.copyWith(licenceFile: file);

  /// What the platform's licence for this till said, the last time one came
  /// in a bootstrap bundle. Null until one has (pos-cloud-sign-in-setup).
  LicenceActivationResult? _bundleLicence;

  /// Take the licence the platform sent in a bootstrap bundle: verified the
  /// way a typed key is — signature, tenant (the business the owner signed in
  /// to), and that it names this app's mode and no other (D9) — and held, not
  /// written, until `complete()`.
  ///
  /// A cloud till has no licence step, so this is the only way it gets one.
  /// Called with the claim's bundle and again with every bundle the connecting
  /// step pulls, so a licence fixed on the dashboard is picked up by "Try
  /// again" without a second claim. [provisionTerminal] refuses to call the
  /// till ready until what arrived here can sell.
  Future<void> receiveBundleLicence(Map<String, Object?> licence) async {
    final result = await ref
        .read(licenceServiceProvider)
        .activate(
          deployment: state.deployment,
          key: '',
          fileContents: jsonEncode(licence),
          persist: false,
        );
    if (_disposed) return;
    _bundleLicence = result;
    state = state.copyWith(
      licenceFile: result.file,
      entitlement: result.entitlement,
      claims: result.claims,
    );
  }

  /// Why a cloud till may not be called ready on the licence the platform
  /// sent, or null when it may (pos-cloud-sign-in-setup, BR-5). Missing, for
  /// the other mode or for both, for another business, or not permitting
  /// trade: each says so in its own words.
  ///
  /// Judged on the licence the draft holds — the one a bundle brought on this
  /// run, or the one restored with a claim made on an earlier run — except
  /// that the latest bundle's refusal always stands: a licence the platform
  /// just sent and the verifier refused must not be outvoted by an older one.
  String? _cloudLicenceRefusal(AppStrings s) {
    final bundle = _bundleLicence;
    if (bundle != null && (bundle.file == null || bundle.entitlement == null)) {
      return bundle.notice?.text(s) ?? s.cloudLicenceMissing;
    }
    final entitlement = state.entitlement;
    if (entitlement == null) return s.cloudLicenceMissing;
    if (!entitlement.canSell) {
      return (entitlement.notice ?? bundle?.notice)?.text(s) ??
          s.cloudLicenceMissing;
    }
    return null;
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
    // Creating another beside it is how a two-seat business ends up with
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

    await _placeWhenUnambiguous(only, adoptable);
  }

  /// One branch and no till waiting for an owner: there is nothing to choose,
  /// so register this machine and skip the branch and terminal screens
  /// (tablet-cloud-onboarding, Q2). **Any doubt asks instead**: several
  /// branches, or any till waiting to be adopted (it may have been made for a
  /// desktop), leaves the existing screens exactly as they were. A refused or
  /// unreachable registration also falls back to them, with its message.
  Future<void> _placeWhenUnambiguous(
    PosBranch? only,
    List<PosTerminalSummary> adoptable,
  ) async {
    final cloudMain =
        state.deployment.mode == DeploymentMode.cloud &&
        !state.deployment.isChild;
    if (!cloudMain || only == null || adoptable.isNotEmpty || state.claimed) {
      return;
    }
    state = state.copyWith(terminalName: _defaultTerminalName);
    await registerTerminal();
    if (_disposed) return;
    if (state.claimed) {
      state = state.copyWith(autoPlaced: true);
    }
  }

  /// What an automatically registered till is called until the owner renames
  /// it on the dashboard.
  static String get _defaultTerminalName =>
      Platform.isAndroid ? 'Tablet' : 'Till';

  /// Everything the cloud path used to ask for, done instead of asked (owner
  /// decision, 2026-09-15: "cloud setup should get everything from cloud, no
  /// need for asking anything").
  ///
  /// The order is the order of dependence, and each step is survivable:
  ///
  ///  1. the database this machine already has — host, name, port, roles and
  ///     their generated passwords, out of the installer's credentials file;
  ///  2. the schema, created and migrated with the administrator credential
  ///     that file carries, then granted to the till;
  ///  3. the menu, the floor, the tax rules and the people, pulled from the
  ///     platform and seeded locally — the same call the catalogue step made;
  ///  4. the printer, if there is exactly one to be sure about.
  ///
  /// **Only (1) and (2) can stop the wizard.** A till with no database cannot
  /// take money and there is nothing to go on to; a till with no menu can be
  /// finished, said so on the last screen, and synced in the morning — which is
  /// the rule the catalogue step has always had.
  Future<void> provisionTerminal() async {
    if (state.busy || state.provisioned) return;
    final s = ref.read(stringsProvider);
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);

    // Read once. Once the fallback fields are on screen the operator is
    // answering this question themselves, and going back to the file would
    // throw their answer away on every retry.
    // A till whose data is a file of its own (the cloud app's encrypted
    // SQLite) has no installer credentials to read and no database to build:
    // the file is prepared instead, below (pos-cloud-single-till-sqlite).
    final embedded = ref.read(embeddedDatastoreProvider);
    if (embedded == null &&
        !state.needsDatabase &&
        !await _adoptInstalledDatabase()) {
      state = state.copyWith(busy: false, needsDatabase: true);
      return;
    }
    _publishDeployment();

    // The schema, always. This used to run only `if (adminDatabasePassword
    // .isNotEmpty)`, and on the fallback path nothing ever filled that in — the
    // password came from `install-credentials.json` or from the offline
    // deployment pane, and the cloud path shows neither. So a Mac walked
    // straight past the build into the seeder and failed there with a raw
    // `3D000: database "xorder_pos" does not exist`. `InstallerCredentials`
    // refuses a file without both passwords and the fallback's button is dead
    // until one is typed, so by here there is always a credential to build
    // with; a wrong one comes back as `bootstrapAuthFailed`, which names the
    // field it belongs to.
    final done = <String>[
      // First line of the report after a restart mid-setup, so the screen
      // explains why it is the one that opened. See [_restoreProgress].
      if (state.resumed) s.setupResumed,
    ];
    if (embedded != null) {
      try {
        final report = await embedded.prepare(state.deployment);
        done
          ..add(report.created ? s.createdDataFile : s.dataFileAlreadyThere)
          ..add(
            report.migrations == 0
                ? s.schemaAlreadyCurrent
                : s.migrationsApplied(report.migrations),
          );
      } on Object catch (error, stack) {
        // Without `provisioned`, as for a database that could not be built:
        // a till with no data file has nowhere to write a sale.
        debugPrint('setup[provisionTerminal] data file refused: $error\n$stack');
        state = state.copyWith(busy: false, error: s.dataFileRefused);
        return;
      }
    } else {
      try {
        final report = await ref.read(databaseBuilderProvider)(
          state.deployment,
          state.adminDatabasePassword,
          // The till's own, for the account the grants are for. On an installed
          // machine it is already a role and this is never used; on the fallback
          // path it is the password typed on this screen, and the only one the
          // till will ever connect with.
          state.databasePassword,
        );
        done
          ..add(
            report.created
                ? s.createdDatabase(state.deployment.databaseName)
                : s.databaseAlreadyThere(state.deployment.databaseName),
          )
          ..addAll([
            if (report.tillRoleCreated)
              s.tillRoleCreated(state.deployment.databaseUser),
          ])
          ..add(
            report.migrations == 0
                ? s.schemaAlreadyCurrent
                : s.migrationsApplied(report.migrations),
          )
          ..add(
            s.grantsApplied(
              state.deployment.databaseUser,
              state.deployment.adminDatabaseUser,
            ),
          );
      } on TillRoleRefused catch (refusal) {
        state = state.copyWith(
          busy: false,
          error: s.tillRoleRefused(refusal.role, refusal.admin),
        );
        return;
      } on PosDbException catch (error) {
        // Returns WITHOUT `provisioned`, which is what keeps Continue dim: a till
        // whose database was not built has nowhere to write a sale, and letting
        // the wizard finish over it only moves the failure to the first order.
        state = state.copyWith(busy: false, error: _bootstrapFailure(error));
        return;
      } on Object catch (error, stack) {
        debugPrint('setup[provisionTerminal] threw: $error\n$stack');
        state = state.copyWith(busy: false, error: '$error');
        return;
      }
    }

    // The bundle, seeded. Its failure is a notice and not a refusal: the claim
    // already succeeded on the platform, the terminal is real, and the first
    // sync pass re-fetches what could not be fetched now.
    String? notice;
    try {
      await _seedFromPlatform();
    } on _CatalogueBlocked catch (blocked) {
      notice = blocked.message;
    } on PosDbException catch (error) {
      // Caught ahead of `Exception` on purpose. `catalogueDownloadFailed` ends
      // in `$error`, and a `PosDbException`'s `toString()` is
      // `PosDbException(missingDatabase): Severity.fatal 3D000: …` — a driver's
      // words, in English, on a screen an Egyptian installer is reading. The
      // notice channel is not logged the way the error channel is, so the raw
      // cause is put on the console here by hand.
      debugPrint('setup[provisionTerminal] seed refused: $error');
      // NOT `_bootstrapFailure`, which names the administrator
      // regardless of which role's connection actually failed. This one is
      // always the TILL's (`posDatabaseProvider`, inside
      // `_seedFromPlatform`) — found live on 16 Sep 2026, where a mistyped
      // till password on the fallback screen was reported to the operator
      // as `pos_admin` being refused. Only the credential itself needs the
      // till named; every other failure kind reads the same regardless of
      // role.
      notice = error.failure == PosDbFailure.auth
          ? s.catalogueAuthFailed(state.deployment.databaseUser)
          : _bootstrapFailure(error);
    } on Exception catch (error) {
      notice = s.catalogueDownloadFailed(error);
    }

    // The till's own lists, once there is a business row to hang them on —
    // which is only after the seed above landed. A failure is a notice for the
    // same reason the seed's is; "Try again" here and "Download menu" on the
    // summary both run it again, and it upserts.
    if (notice == null) {
      try {
        await _seedLocalDefaults();
      } on PosDbException catch (error) {
        debugPrint('setup[provisionTerminal] defaults refused: $error');
        // The ADMINISTRATOR's connection this time, which is the role
        // `_bootstrapFailure` names.
        notice = _bootstrapFailure(error);
      }
    }
    var items = 0;
    try {
      items = (await ref.read(catalogRepositoryProvider).load()).products.length;
    } on Object {
      // A menu that cannot be read is the same outcome as one that is not there
      // yet, and the summary says so in as many words.
    }
    done.add(s.itemsCached(items));

    // The printer, detected rather than asked about. ONE is not a choice — it
    // is the printer on this machine — and the paper width, the drawer and the
    // absence of a scanner are what every business this ships to has. Two or
    // none is a genuine question, and `visibleSteps` puts the hardware screen
    // back for it.
    var printers = const <DiscoveredPrinter>[];
    try {
      printers = await ref.read(hardwarePortsProvider).discoverPrinters();
    } on Object {
      // A scan that throws is a machine with no printing subsystem this build
      // understands, which is the same answer as finding nothing.
    }
    final only = printers.length == 1 ? printers.single : null;
    if (only != null) done.add(s.printerDetected(only.name));

    // A cloud till is not ready until the licence the platform sent can sell
    // (pos-cloud-sign-in-setup, BR-5). It has no licence step, so this is the
    // first place anything looks at it; leaving it to the start screen would
    // finish a setup that cannot open a shift. "Try again" runs this whole
    // step again, and the bundle it pulls brings the licence afresh.
    final cloudMain =
        state.deployment.mode == DeploymentMode.cloud &&
        !state.deployment.isChild;
    if (cloudMain) {
      final refusal = _cloudLicenceRefusal(s);
      if (refusal != null) {
        state = state.copyWith(
          busy: false,
          bootstrapReport: done.join('\n'),
          catalogueItems: items,
          error: refusal,
          notice: notice,
        );
        return;
      }
    }

    state = state.copyWith(
      busy: false,
      provisioned: true,
      bootstrapReport: done.join('\n'),
      catalogueItems: items,
      detectedPrinters: printers.length,
      printerName: only?.name,
      paperWidthDots: only == null ? null : PrinterConfig.width80mm,
      drawerAttached: only == null ? null : true,
      scannerAttached: only == null ? null : false,
      notice: notice,
    );
  }

  /// Take the database off the installation, or say there is none to take.
  ///
  /// True when this machine's `install-credentials.json` answered. False sends
  /// the connecting step to its fallback fields — see [SetupDraft.needsDatabase].
  Future<bool> _adoptInstalledDatabase() async {
    final InstallerCredentials? installed;
    try {
      installed = await ref.read(installerCredentialsProvider).read();
    } on Object catch (error, stack) {
      // Nothing about a credentials file is worth failing an install over, and
      // the fallback screen handles its absence perfectly well.
      debugPrint('setup[installerCredentials] threw: $error\n$stack');
      return false;
    }
    if (installed == null) return false;

    state = state.copyWith(
      deployment: state.deployment.copyWith(
        // The installer puts PostgreSQL on the machine it is run on, and a
        // cloud till's database is its own. A shared LAN database is the
        // offline shape and keeps its screen.
        databaseHost: DeploymentConfig.localhost,
        databaseName: installed.database,
        databasePort: installed.port,
        databaseUser: installed.tillUser,
        adminDatabaseUser: installed.adminUser,
      ),
      databasePassword: installed.tillPassword,
      // Kept, so Admin Mode is a username and a PIN rather than a password
      // nobody was ever told. `complete()` is what writes it to the OS store
      // (DPAPI / Keychain, via `adminDbSecretStoreProvider`).
      adminDatabasePassword: installed.adminPassword,
    );
    return true;
  }

  /// Register a hand-configured terminal against the tenant.
  ///
  /// **Failure does not block setup.** An installer standing in a business
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

    // A child is one more of the licence's terminals, and on a shared database
    // that is a number it can check: every terminal row is in front of it.
    // Checked here, where the seat is spent, rather than when the licence was
    // read — the count can have moved while the installer picked a branch.
    if (state.deployment.isChild && adopting == null) {
      final s = ref.read(stringsProvider);
      final SiteLicence? site;
      try {
        site = await ref.read(siteLicenceSourceProvider)?.read();
      } on PosDbException catch (error) {
        state = state.copyWith(
          busy: false,
          error: _describe(error.failure, state.deployment),
        );
        return;
      }
      if (site != null && site.terminalCount >= state.maxTerminals) {
        state = state.copyWith(
          busy: false,
          error: s.allTerminalsTaken(state.maxTerminals),
        );
        return;
      }
    }

    final provisioning = ref.read(provisioningRepositoryProvider);

    // WHO is registering. Offline registration authenticates against
    // `pos_users` on this machine's own database, and the person doing it is
    // the administrator created two steps ago — the wizard is still holding
    // those credentials, so asking for them again would be asking somebody to
    // retype what they typed a minute earlier on the same run.
    //
    // The cloud fields are the ones the Sign in step collects, and the offline
    // path no longer has that step: it asks for the first administrator
    // instead. Reading them here sent an empty username to the till's own
    // database and was refused every time, on the last step of the wizard.
    //
    // A child is the exception: it built nothing and created nobody, so it
    // registers as the manager it signed in as, whatever the main device's
    // mode.
    final firstInstall =
        state.deployment.mode == DeploymentMode.offline &&
        !state.deployment.isChild;
    final username = firstInstall
        ? state.ownerUsername
        : state.operatorUsername;
    final password = firstInstall ? state.ownerPin : state.operatorPassword;

    // The installation id on disk before the row it keys exists — see
    // [_rememberProgress]. Only where the registration is the branch
    // database's upsert: a cloud main device registers with the platform, and
    // its record is the claim afterwards, as it always was.
    final branchDatabase =
        state.deployment.mode == DeploymentMode.offline ||
        state.deployment.isChild;
    if (adopting == null && branchDatabase) {
      await _rememberProgress(claimed: false);
    }

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
            installId: state.installationId,
          );

    final claim = result.claim;
    state = state.copyWith(
      busy: false,
      claimed: claim != null,
      terminalId: claim?.terminalId ?? state.terminalId,
      businessId: claim?.businessId,
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
      notice: claim == null ? null : _claimNotices(result.notices),
    );

    // A cloud till takes the business's own language and sync policy from the
    // claim, as the pairing-code path did before sign-in replaced it
    // (pos-cloud-sign-in-setup). The cloud path has no language screen: the
    // dashboard was asked this when the business was created. Whoever is
    // standing here still has the last word — the Settings bar's switch is on
    // every screen.
    final cloudMain =
        state.deployment.mode == DeploymentMode.cloud &&
        !state.deployment.isChild;
    if (claim != null && cloudMain) {
      state = state.copyWith(
        locale: claim.defaultLanguage,
        deployment: state.deployment.copyWith(syncPolicy: claim.syncPolicy),
      );
      if (claim.defaultLanguage case final language?) {
        ref.read(localeProvider.notifier).apply(language);
      }
    }

    // A seat spent by hand is as spent as one a code bought; the fallback
    // path resumes for the same reason the default one does.
    if (claim != null) await _rememberProgress();
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
      await _seedLocalDefaults();
      final catalog = await ref.read(catalogRepositoryProvider).load();
      state = state.copyWith(
        busy: false,
        catalogueItems: catalog.products.length,
      );
    } on _CatalogueBlocked catch (blocked) {
      state = state.copyWith(busy: false, error: blocked.message);
    } on PosDbException catch (error) {
      state = state.copyWith(busy: false, error: _bootstrapFailure(error));
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
    // Nor does a child of a cloud main device: the main device seeded the
    // database this tablet reads, and the tablet holds no token to pull with.
    if (state.deployment.isChild) return;

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
    // Parsing and writing the bundle are cloud code, bound by the cloud app
    // (pos-split-apps, stage 3); a build without that binding cannot seed.
    //
    // Forced: during setup the operator pressing "Download menu" IS the
    // precedence decision, and a half-applied earlier seed must not win a
    // config_version tie against a complete one.
    final seeding = ref.read(bootstrapSeedingProvider);
    final seeded =
        seeding != null &&
        await seeding.seed(reply.body, config: state.deployment, force: true);

    // The bundle carries the platform's current licence for this till; the
    // same one the claim brought, unless somebody fixed it on the dashboard
    // since — which is exactly the case "Try again" exists for.
    if (reply.body['licence'] case final Map licence) {
      await receiveBundleLicence(licence.cast<String, Object?>());
    }

    if (!seeded) {
      throw _CatalogueBlocked(s.menuShapeNotUnderstood(api.baseUrl));
    }
  }

  /// What the bundle has no field for — reasons and order types — seeded over
  /// the administrator's credential. See [cloudDefaultsSeederProvider] for
  /// what it writes and, more to the point, what it deliberately does not.
  ///
  /// After [_seedFromPlatform] and only after it: the rows reference the
  /// business the bundle created. Silent when there is nothing to do —
  /// an offline till seeded these in `bootstrapDatabase`, a child reads its
  /// main device's, and a business id the claim did not give means the
  /// seed above never ran either.
  Future<void> _seedLocalDefaults() async {
    if (state.deployment.mode != DeploymentMode.cloud) return;
    if (state.deployment.isChild) return;
    final businessId = state.businessId;
    if (businessId == null || state.adminDatabasePassword.isEmpty) return;

    await ref.read(cloudDefaultsSeederProvider)(
      state.deployment,
      state.adminDatabasePassword,
      businessId,
    );
  }

  void next() {
    if (!state.canAdvance || state.isLastStep) return;

    // Every step after the connection one reads the branch database: the branch
    // list, the pairing code, the first catalogue pull. They need the endpoint
    // and the credential, which is why those are published here rather than at
    // the end of the wizard — but they also need the *business*, and that is
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
      // Arriving at the first-install step starts on its first page.
      ownerPage: OwnerPage.databaseAccess,
      clearError: true,
      clearNotice: true,
    );
  }

  void back() {
    // Inside the first-install step, Back from the owner's page is the first
    // page, not the previous step.
    if (state.isFirstInstall &&
        !state.bootstrapped &&
        state.ownerPage == OwnerPage.ownerAccount) {
      showOwnerPage(OwnerPage.databaseAccess);
      return;
    }
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
/// here is how "not registered" once surfaced as "no business named demo
/// exists in this database", which sent the operator to check a database that
/// was never the problem.
class _CatalogueBlocked implements Exception {
  const _CatalogueBlocked(this.message);

  final String message;
}

final setupProvider = NotifierProvider<SetupController, SetupDraft>(
  SetupController.new,
);
