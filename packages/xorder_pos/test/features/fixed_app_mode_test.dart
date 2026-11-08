import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/labels.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';

import '../support/fakes.dart';

/// One app per mode (pos-split-apps, stage 2).
///
/// "XOrder POS - Cloud" and "XOrder POS - Offline" each fix `appModeProvider`
/// in their `main`. From then on the mode is not a question: the wizard has no
/// mode step (BR-1), `setMode` refuses the other mode, a licence for the other
/// mode is refused and names the other app (BR-2), and a licence signed for
/// both modes is refused and sent back to the Super Admin (D9). Every rule is
/// run once per app, because each app is the other one's "other".
LicenseFile _licence({required Set<DeploymentMode> modes}) {
  final now = DateTime.now();
  final claims = LicenseClaims(
    licenseId: 'LIC-TEST-0002',
    tenantSlug: 'islanded',
    tenantName: 'The Islanded Cafe',
    issuedAt: now.subtract(const Duration(days: 1)),
    expiresAt: now.add(const Duration(days: 365)),
    maxTerminals: 2,
    features: const {'pos'},
    modes: modes,
  );
  return LicenseFile(
    payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
    signatureB64: base64Url.encode(List<int>.filled(64, 0)),
    keyId: 'dev',
  );
}

ProviderContainer _app(DeploymentMode mode) {
  final container = ProviderContainer(
    overrides: fakeRepositoryOverrides(appMode: mode),
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  for (final mode in DeploymentMode.values) {
    final other = mode.other;

    group('${mode.productName}:', () {
      test('an unconfigured till is already in the app\'s mode', () {
        final container = _app(mode);
        expect(container.read(deploymentProvider).mode, mode);
        expect(container.read(setupProvider).deployment.mode, mode);
        expect(container.read(setupProvider).appMode, mode);
        expect(container.read(appTitleProvider), mode.productName);
      });

      test('the wizard never asks which product this is (BR-1)', () async {
        final container = _app(mode);
        final draft = container.read(setupProvider);

        // Before any licence is read — the shared package would still be
        // asking here, since nothing has answered it.
        expect(draft.asksSetupType, isFalse);
        expect(draft.visibleSteps, isNot(contains(SetupStep.setupType)));

        // And a licence covering this mode changes nothing about that.
        await container
            .read(setupProvider.notifier)
            .activateLicence(fileContents: _licence(modes: {mode}).serialize());
        final after = container.read(setupProvider);
        expect(after.entitlement?.canSell, isTrue);
        expect(after.deployment.mode, mode);
        expect(after.visibleSteps, isNot(contains(SetupStep.setupType)));
      });

      test('the other mode cannot be chosen on the till', () {
        final container = _app(mode);
        container.read(setupProvider.notifier).setMode(other);
        expect(container.read(setupProvider).deployment.mode, mode);
      });

      test('a licence for the other mode is refused and names the other app '
          '(BR-2)', () async {
        final container = _app(mode);
        await container
            .read(setupProvider.notifier)
            .activateLicence(fileContents: _licence(modes: {other}).serialize());

        final draft = container.read(setupProvider);
        expect(draft.entitlement?.state, LicenseState.modeNotLicensed);
        expect(draft.entitlement?.canSell, isFalse);
        // Not quietly moved to the mode the licence holds: that would turn
        // this app into the other one.
        expect(draft.deployment.mode, mode);
        expect(draft.copyWith(step: SetupStep.licence).canAdvance, isFalse);

        final notice = draft.entitlement!.notice!;
        expect(notice, isA<LicenceModeNotCovered>());
        expect((notice as LicenceModeNotCovered).fixedApp, isTrue);
        final text = notice.text(AppStrings.of(const Locale('en')));
        expect(text, contains(other.productName));
        expect(text, isNot(contains(mode.productName)));
      });

      test('a licence signed for both modes is refused (D9)', () async {
        final container = _app(mode);
        await container.read(setupProvider.notifier).activateLicence(
          fileContents: _licence(modes: {mode, other}).serialize(),
        );

        final draft = container.read(setupProvider);
        expect(draft.entitlement?.state, LicenseState.modeAmbiguous);
        expect(draft.entitlement?.canSell, isFalse);
        expect(draft.entitlement?.notice, isA<LicenceCoversBothModes>());
        expect(draft.copyWith(step: SetupStep.licence).canAdvance, isFalse);
        // Both languages have a sentence for it.
        for (final locale in const [Locale('en'), Locale('ar')]) {
          expect(
            draft.entitlement!.notice!.text(AppStrings.of(locale)),
            isNotEmpty,
          );
        }
      });

      test('an empty modes claim still means every mode, so it is accepted',
          () async {
        final container = _app(mode);
        await container
            .read(setupProvider.notifier)
            .activateLicence(fileContents: _licence(modes: {}).serialize());
        expect(container.read(setupProvider).entitlement?.canSell, isTrue);
      });
    });
  }

  group('the verifier on its own', () {
    final now = DateTime(2026, 11, 8);
    LicenseClaims claims(Set<DeploymentMode> modes) => LicenseClaims(
      licenseId: 'LIC-TEST-0003',
      tenantSlug: 'islanded',
      tenantName: 'The Islanded Cafe',
      issuedAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 365)),
      maxTerminals: 1,
      features: const {'pos'},
      modes: modes,
    );

    test('a both-modes licence is refused only when one mode is fixed', () {
      const cloud = DeploymentConfig(mode: DeploymentMode.cloud);
      final both = claims({DeploymentMode.cloud, DeploymentMode.offline});

      final shared = LicenseVerifier.evaluateClaims(
        claims: both,
        deployment: cloud,
        now: now,
      );
      expect(shared.state, LicenseState.valid);

      final app = LicenseVerifier.evaluateClaims(
        claims: both,
        deployment: cloud,
        now: now,
        singleModeOnly: true,
      );
      expect(app.state, LicenseState.modeAmbiguous);
      expect(app.canSell, isFalse);
      expect(app.canOpenShift, isFalse);
      expect(app.canChangeConfiguration, isFalse);
    });

    test('ambiguity is judged before coverage, so the message is about '
        'reissuing', () {
      const offline = DeploymentConfig(mode: DeploymentMode.offline);
      final verdict = LicenseVerifier.evaluateClaims(
        claims: claims({DeploymentMode.cloud, DeploymentMode.offline}),
        deployment: offline,
        now: now,
        singleModeOnly: true,
      );
      expect(verdict.notice, isA<LicenceCoversBothModes>());
    });

    test('the other mode alone is modeNotLicensed, flagged for the app', () {
      const offline = DeploymentConfig(mode: DeploymentMode.offline);
      final verdict = LicenseVerifier.evaluateClaims(
        claims: claims({DeploymentMode.cloud}),
        deployment: offline,
        now: now,
        singleModeOnly: true,
      );
      expect(verdict.state, LicenseState.modeNotLicensed);
      expect(
        verdict.notice,
        isA<LicenceModeNotCovered>().having((n) => n.fixedApp, 'fixedApp', true),
      );
    });
  });

  test('the shared package without an app keeps the old rule', () {
    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    expect(container.read(appModeProvider), isNull);
    expect(container.read(appTitleProvider), 'XOrder POS');
    expect(container.read(setupProvider).appMode, isNull);
    // Nothing has answered the mode question, so it is still asked.
    expect(container.read(setupProvider).asksSetupType, isTrue);
  });
}
