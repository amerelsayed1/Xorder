import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The licence is read first, and is judged against the app's mode.
///
/// **Rewritten in pos-split-apps stage 4.** This file used to be "the licence
/// decides the mode": a tenant sold one mode had the draft moved onto it, a
/// tenant sold both was offered a mode screen, and `setMode` refused a tile the
/// tenant had not bought. Cloud and offline are two apps now; the app is the
/// mode, the mode step and `setMode` are gone, and a licence either covers the
/// app's mode or is refused naming the other app (`fixed_app_mode_test.dart`).
/// What is left here is the part of the old rule that still holds: the licence
/// is the first step, a licence for this app's mode is not refused for a mode
/// nobody chose, and nothing about the mode rescues a licence refused for
/// something else.

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

/// The offline app, unless [mode] says which. Every test here but one is an
/// app's: with the mode fixed by the app there is nothing left for a licence
/// to decide but whether it covers it.
ProviderContainer _container({DeploymentMode mode = DeploymentMode.offline}) {
  final container = ProviderContainer(
    overrides: fakeRepositoryOverrides(appMode: mode),
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('an offline licence on the offline app is not refused for a mode '
      'nobody chose', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    // The trap this file was written for, stated: `unconfigured` is cloud, and
    // an offline-only licence judged against it came back `modeNotLicensed`.
    // The app's mode is what the draft opens in now, not `unconfigured`'s.
    expect(
      container.read(setupProvider).deployment.mode,
      DeploymentMode.offline,
    );

    await controller.activateLicence(
      fileContents: _licence(modes: {DeploymentMode.offline}).serialize(),
    );

    final draft = container.read(setupProvider);
    expect(draft.entitlement, isNotNull);
    expect(draft.entitlement!.state, isNot(LicenseState.modeNotLicensed));
    expect(draft.entitlement!.canSell, isTrue);
    expect(draft.deployment.mode, DeploymentMode.offline);
    // Asked *of the licence step*: `canAdvance` is a property of the step the
    // draft is on, and every step answers it differently.
    expect(draft.copyWith(step: SetupStep.licence).canAdvance, isTrue);
  });

  /// Added in stage 4, in place of "the mode step then offers only what the
  /// tenant bought". The licence used to MOVE a draft onto the mode it
  /// covered, and with no app to fix the mode that is where the shared
  /// package's draft would still have gone. It no longer moves: a licence that
  /// does not cover the draft's mode is refused, here as in either app.
  test('a licence never moves the draft to another mode', () async {
    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    final controller = container.read(setupProvider.notifier);
    expect(
      container.read(setupProvider).deployment.mode,
      DeploymentMode.cloud,
    );

    await controller.activateLicence(
      fileContents: _licence(modes: {DeploymentMode.offline}).serialize(),
    );

    final draft = container.read(setupProvider);
    expect(draft.deployment.mode, DeploymentMode.cloud);
    expect(draft.entitlement?.state, LicenseState.modeNotLicensed);
    expect(draft.copyWith(step: SetupStep.licence).canAdvance, isFalse);
  });

  /// Rewritten for pos-split-apps (D9). This used to show a dual-mode licence
  /// leaving the choice with the operator; an app runs one mode, so a licence
  /// that would leave two is refused and reissued for one. The rule itself,
  /// per app, is in `fixed_app_mode_test.dart`.
  test('a licence covering both is refused by an app, not offered as a choice',
      () async {
    for (final mode in DeploymentMode.values) {
      final container = _container(mode: mode);
      final controller = container.read(setupProvider.notifier);

      await controller.activateLicence(
        fileContents: _licence(
          modes: {DeploymentMode.cloud, DeploymentMode.offline},
        ).serialize(),
      );

      final draft = container.read(setupProvider);
      expect(draft.entitlement?.state, LicenseState.modeAmbiguous);
      expect(draft.deployment.mode, mode);
    }
  });

  /// The offline path, walked. Rewritten in stage 4 from "a single-mode
  /// licence takes the mode screen away entirely": there is no mode screen to
  /// take away, and the path is the same before and after the licence.
  test('the offline app walks licence, language, connection — and back', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);
    final before = container.read(setupProvider).visibleSteps;

    await controller.activateLicence(
      fileContents: _licence(modes: {DeploymentMode.offline}).serialize(),
    );

    final draft = container.read(setupProvider);
    expect(draft.visibleSteps, before);
    // Counted against the path rather than against `SetupStep.values`, which
    // also carries the cloud-only `connecting` step.
    expect(draft.stepCount, draft.offlineSteps.length);
    expect(draft.visibleSteps, isNot(contains(SetupStep.connecting)));

    expect(draft.step, SetupStep.licence);
    controller.next();
    expect(container.read(setupProvider).step, SetupStep.language);
    controller.next();
    expect(container.read(setupProvider).step, SetupStep.deployment);
    controller.back();
    expect(container.read(setupProvider).step, SetupStep.language);
  });

  /// Rewritten in stage 4 from "an app never shows the mode screen, whatever
  /// the licence says": the step is gone, so what is left to hold is the path.
  test('each app walks its own path', () async {
    for (final mode in DeploymentMode.values) {
      final container = _container(mode: mode);
      final controller = container.read(setupProvider.notifier);

      await controller.activateLicence(
        fileContents: _licence(modes: {mode}).serialize(),
      );

      final draft = container.read(setupProvider);
      expect(
        draft.stepCount,
        mode == DeploymentMode.cloud
            ? draft.cloudSteps.length
            : draft.offlineSteps.length,
      );
    }
  });

  test('covering the mode does not rescue an expired licence', () async {
    final container = _container();
    final controller = container.read(setupProvider.notifier);

    // Past expiry and past the 14-day grace. A licence that covers the app's
    // mode is still refused for everything else it can be refused for.
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
    // takes away is the next shift.
    expect(draft.entitlement!.canOpenShift, isFalse);
    expect(draft.entitlement!.canChangeConfiguration, isFalse);
  });

  test('the wizard asks for the licence first, on either path', () {
    for (final mode in DeploymentMode.values) {
      final steps = SetupDraft(
        deployment: DeploymentConfig.unconfigured.copyWith(mode: mode),
        appMode: mode,
      ).visibleSteps;

      // The gate. A terminal with no licence has nothing to set up, so every
      // other question would be collecting answers that may prove worthless.
      // Hiding it for cloud terminals once decided the mode question using its
      // own answer.
      expect(steps.first, SetupStep.licence, reason: mode.name);
    }
  });
}
