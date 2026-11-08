import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';

import '../support/fakes.dart';

/// The licence decides the mode, so the wizard must ask for it first.
///
/// A tenant is sold cloud, offline, or both when the Super Admin creates it,
/// and the `modes` claim is how that reaches the till. The wizard used to ask
/// the opposite way round — pick a mode, then read the licence — which had two
/// costs. An operator could pick a mode they had not bought and be refused two
/// screens later, and, once the licence step moved to the front, a
/// single-mode licence could not be read at all: `DeploymentConfig.unconfigured`
/// is cloud, so an **offline-only** licence was judged against cloud, came back
/// `modeNotLicensed`, and stopped the wizard on a screen whose whole purpose
/// was to tell it otherwise.
LicenseFile _licence({
  required Set<DeploymentMode> modes,
  Duration expiresIn = const Duration(days: 365),
}) {
  final now = DateTime.now();
  final claims = LicenseClaims(
    licenseId: 'LIC-TEST-0001',
    tenantSlug: 'islanded',
    tenantName: 'The Islanded Cafe',
    issuedAt: now.subtract(const Duration(days: 1)),
    expiresAt: now.add(expiresIn),
    maxTerminals: 2,
    features: const {'pos'},
    modes: modes,
  );

  // The signature is a placeholder: `FakeLicenceService` is the development
  // issuer and skips the signature check, while still evaluating policy in
  // full. Policy is the whole subject here.
  return LicenseFile(
    payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
    signatureB64: base64Url.encode(List<int>.filled(64, 0)),
    keyId: 'dev',
  );
}

ProviderContainer _container() {
  final container = ProviderContainer(overrides: fakeRepositoryOverrides());
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('an offline-only licence is not refused for a mode nobody chose', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    // The trap, stated: the draft is sitting on cloud because that is what
    // `unconfigured` is, not because anyone picked it.
    expect(
      container.read(setupProvider).deployment.mode,
      DeploymentMode.cloud,
    );

    await controller.activateLicence(
      fileContents: _licence(modes: {DeploymentMode.offline}).serialize(),
    );

    final draft = container.read(setupProvider);
    expect(draft.entitlement, isNotNull);
    expect(draft.entitlement!.state, isNot(LicenseState.modeNotLicensed));
    expect(draft.entitlement!.canSell, isTrue);
    // And the terminal has been moved to the mode it actually holds.
    expect(draft.deployment.mode, DeploymentMode.offline);
    // Asked *of the licence step*: `canAdvance` is a property of the step the
    // draft is on, and every step answers it differently.
    expect(draft.copyWith(step: SetupStep.licence).canAdvance, isTrue);
  });

  test('the mode step then offers only what the tenant bought', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    await controller.activateLicence(
      fileContents: _licence(modes: {DeploymentMode.offline}).serialize(),
    );

    expect(container.read(setupProvider).licensedModes, {DeploymentMode.offline});

    // Not merely dimmed in the UI — the controller refuses it, so no route
    // through the wizard can land on a mode this tenant did not buy.
    controller.setMode(DeploymentMode.cloud);
    expect(
      container.read(setupProvider).deployment.mode,
      DeploymentMode.offline,
    );
  });

  test('a licence covering both leaves the choice with the operator', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    await controller.activateLicence(
      fileContents: _licence(
        modes: {DeploymentMode.cloud, DeploymentMode.offline},
      ).serialize(),
    );

    expect(
      container.read(setupProvider).licensedModes,
      {DeploymentMode.cloud, DeploymentMode.offline},
    );

    controller.setMode(DeploymentMode.offline);
    expect(
      container.read(setupProvider).deployment.mode,
      DeploymentMode.offline,
    );
    controller.setMode(DeploymentMode.cloud);
    expect(
      container.read(setupProvider).deployment.mode,
      DeploymentMode.cloud,
    );
  });

  /// A screen with one choosable option is not a question.
  ///
  /// The mode screen offers what the tenant bought and greys out what it did
  /// not. On a single-mode licence — which is most of them — that leaves the
  /// answer already filled in, since adoption moves the draft onto a covered
  /// mode the moment the licence is read. The installer's only move is Continue.
  test('a single-mode licence takes the mode screen away entirely', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    // Before a licence is read, nothing has answered it, so it is asked.
    expect(
      container.read(setupProvider).visibleSteps,
      contains(SetupStep.setupType),
    );

    await controller.activateLicence(
      fileContents: _licence(modes: {DeploymentMode.offline}).serialize(),
    );

    final draft = container.read(setupProvider);
    expect(draft.asksSetupType, isFalse);
    expect(draft.visibleSteps, isNot(contains(SetupStep.setupType)));
    // The offline path, one step shorter. Counted against the path rather than
    // against `SetupStep.values`, which now also carries the cloud-only
    // `connecting` step and would make this assertion read as a failure the
    // day a step is added for anybody else.
    expect(draft.stepCount, draft.offlineSteps.length);
    expect(draft.visibleSteps, isNot(contains(SetupStep.connecting)));
    // Taken away, not skipped past: the mode is set, and the summary screen is
    // where it is read back.
    expect(draft.deployment.mode, DeploymentMode.offline);

    // And the wizard walks straight by it, in both directions, so nobody lands
    // on a screen the rail no longer lists.
    expect(draft.step, SetupStep.licence);
    controller.next();
    expect(container.read(setupProvider).step, SetupStep.language);
    controller.next();
    expect(container.read(setupProvider).step, SetupStep.deployment);
    controller.back();
    expect(container.read(setupProvider).step, SetupStep.language);
  });

  test('a licence covering both keeps it, because it is a question', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    await controller.activateLicence(
      fileContents: _licence(
        modes: {DeploymentMode.cloud, DeploymentMode.offline},
      ).serialize(),
    );

    final draft = container.read(setupProvider);
    expect(draft.asksSetupType, isTrue);
    expect(draft.visibleSteps, contains(SetupStep.setupType));

    // A dual-mode licence leaves the draft on cloud, which since 2026-09-15 is
    // the short path: licence, setup type, setup code, connecting, hardware,
    // ready. The mode screen is the only one of the six that is on it *because*
    // the licence could not answer it.
    expect(draft.stepCount, draft.cloudSteps.length);
    expect(draft.visibleSteps, isNot(contains(SetupStep.language)));
    expect(draft.visibleSteps, isNot(contains(SetupStep.deployment)));

    controller.next();
    expect(container.read(setupProvider).step, SetupStep.setupType);
  });

  test('re-judging the mode does not rescue an expired licence', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    // Past expiry and past the 14-day grace. Only the *mode* verdict is ever
    // revisited; a refusal of the licence itself has to stand, or the fix
    // would have quietly become a way past every other gate.
    await controller.activateLicence(
      fileContents: _licence(
        modes: {DeploymentMode.offline},
        expiresIn: const Duration(days: -60),
      ).serialize(),
    );

    final draft = container.read(setupProvider);
    expect(draft.entitlement!.state, LicenseState.expired);
    // `canSell` deliberately stays true past grace — an open shift is never cut
    // off and cash-up is never gated — and the licence step advances on it, so
    // an expired licence does not strand an installer mid-wizard. What expiry
    // takes away is the next shift, and re-judging the mode must not give that
    // back.
    expect(draft.entitlement!.canOpenShift, isFalse);
    expect(draft.entitlement!.canChangeConfiguration, isFalse);
  });

  test('the wizard asks for the licence first, and before the mode', () {
    final steps = const SetupDraft().visibleSteps;

    // The gate. A terminal with no licence has nothing to set up, so every
    // other question would be collecting answers that may prove worthless.
    expect(steps.first, SetupStep.licence);
    expect(
      steps.indexOf(SetupStep.licence),
      lessThan(steps.indexOf(SetupStep.setupType)),
    );
    // The licence step is on every path now. Hiding it for cloud terminals
    // decided the mode question using its own answer.
    expect(steps, contains(SetupStep.licence));
  });
}
