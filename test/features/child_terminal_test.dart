import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/features/licensing/data/site_licence.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';

import '../support/fakes.dart';

/// A tablet is a child of the main device (owner decision, 2026-09-12).
///
/// It was being walked through the desktop wizard: a licence key on its first
/// screen, then the mode, the database build and the first owner. None of
/// those belong to a device carried round the floor. A child finds its main
/// device, uses the licence the main device shares in their database, signs in
/// as a manager who already exists, and registers as one more terminal.
LicenseClaims _claims({
  int maxTerminals = 3,
  Set<String> fingerprints = const {},
  Set<DeploymentMode> modes = const {DeploymentMode.offline},
}) {
  final now = DateTime.now();
  return LicenseClaims(
    licenseId: 'LIC-SITE-0001',
    tenantSlug: 'islanded',
    tenantName: 'The Islanded Cafe',
    issuedAt: now.subtract(const Duration(days: 1)),
    expiresAt: now.add(const Duration(days: 365)),
    maxTerminals: maxTerminals,
    features: const {'pos'},
    modes: modes,
    fingerprints: fingerprints,
  );
}

/// Signature is a placeholder: `FakeLicenceService` skips it, and the direct
/// [SiteLicenceService] tests below inject a verifier that accepts it.
LicenseFile _file(LicenseClaims claims) => LicenseFile(
  payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
  signatureB64: base64Url.encode(List<int>.filled(64, 0)),
  keyId: 'dev',
);

SiteLicence _site({
  LicenseClaims? claims,
  DeploymentMode mode = DeploymentMode.offline,
  int terminalCount = 1,
}) => SiteLicence(
  file: _file(claims ?? _claims()),
  restaurantId: 7,
  mode: mode,
  terminalCount: terminalCount,
);

ProviderContainer _device(
  TerminalRole role, {
  SiteLicenceSource? source,
}) {
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      deviceRoleProvider.overrideWithValue(role),
      siteLicenceSourceProvider.overrideWithValue(
        source ?? InMemorySiteLicenceSource(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Point the tablet at a main device and connect.
Future<SetupController> _connect(ProviderContainer container) async {
  final controller = container.read(setupProvider.notifier)
    ..setDatabaseHost('192.168.1.20')
    ..setDatabasePassword('till-secret');
  await controller.connectToMainDevice();
  return controller;
}

void main() {
  const en = EnStrings();

  test('a tablet opens on finding its main device, not on a licence key', () {
    final draft = _device(TerminalRole.child).read(setupProvider);

    expect(draft.deployment.isChild, isTrue);
    expect(draft.step, SetupStep.deployment);
    expect(draft.visibleSteps, SetupDraft.childSteps);
    // Everything the main device owns is left out.
    expect(
      draft.visibleSteps,
      isNot(anyOf(
        contains(SetupStep.licence),
        contains(SetupStep.setupType),
        contains(SetupStep.money),
      )),
    );
    // Never pre-filled with localhost: a child's database is not on it.
    expect(draft.deployment.databaseHost, isEmpty);
  });

  test('a desktop still opens on the licence', () {
    final draft = _device(TerminalRole.main).read(setupProvider);

    expect(draft.deployment.isChild, isFalse);
    expect(draft.step, SetupStep.licence);
    expect(draft.visibleSteps, contains(SetupStep.licence));
  });

  test('the tablet adopts the licence, tenant and mode its main device shares',
      () async {
    final container = _device(
      TerminalRole.child,
      source: InMemorySiteLicenceSource(_site()),
    );
    await _connect(container);
    final draft = container.read(setupProvider);

    expect(draft.error, isNull);
    expect(draft.mainDeviceLinked, isTrue);
    expect(draft.entitlement?.canSell, isTrue);
    expect(draft.deployment.tenantSlug, 'islanded');
    expect(draft.deployment.mode, DeploymentMode.offline);
    expect(draft.notice, en.mainDeviceLinked('The Islanded Cafe'));
    expect(draft.canAdvance, isTrue);
  });

  test('a main device that has shared nothing yet is named as the problem',
      () async {
    final container = _device(TerminalRole.child);
    await _connect(container);
    final draft = container.read(setupProvider);

    expect(draft.error, en.mainDeviceHasNoLicence);
    expect(draft.mainDeviceLinked, isFalse);
    expect(draft.canAdvance, isFalse);
  });

  test('the tablet cannot be its own main device', () async {
    final container = _device(
      TerminalRole.child,
      source: InMemorySiteLicenceSource(_site()),
    );
    final controller = container.read(setupProvider.notifier)
      ..setDatabaseHost('localhost')
      ..setDatabasePassword('till-secret');
    await controller.connectToMainDevice();

    expect(container.read(setupProvider).error, en.mainDeviceIsThisTablet);
    expect(container.read(setupProvider).canAdvance, isFalse);
  });

  test('changing the address forgets the main device it was linked to',
      () async {
    final container = _device(
      TerminalRole.child,
      source: InMemorySiteLicenceSource(_site()),
    );
    final controller = await _connect(container);
    controller.setDatabaseHost('192.168.1.21');

    expect(container.read(setupProvider).mainDeviceLinked, isFalse);
    expect(container.read(setupProvider).canAdvance, isFalse);
  });

  test('a child of a cloud main device runs in cloud, with no address of its '
      'own', () async {
    final container = _device(
      TerminalRole.child,
      source: InMemorySiteLicenceSource(
        _site(
          claims: _claims(modes: {DeploymentMode.cloud}),
          mode: DeploymentMode.cloud,
        ),
      ),
    );
    await _connect(container);
    final draft = container.read(setupProvider);

    expect(draft.deployment.mode, DeploymentMode.cloud);
    expect(draft.deployment.baseUrl, isNull);
    expect(draft.deployment.isConfigured, isTrue);
    expect(draft.canAdvance, isTrue);
    // Its sales go up through the main device's drain, never its own.
    expect(container.read(posCloudApiProvider), isNull);
  });

  test('a tablet that would exceed the licence is refused before it '
      'registers', () async {
    final container = _device(
      TerminalRole.child,
      source: InMemorySiteLicenceSource(
        _site(claims: _claims(maxTerminals: 2), terminalCount: 2),
      ),
    );
    final controller = await _connect(container);
    controller
      ..setBranch(1, 'Main')
      ..setTerminalName('Tablet 1');
    await controller.registerTerminal();
    final draft = container.read(setupProvider);

    expect(draft.error, en.allTerminalsTaken(2));
    expect(draft.claimed, isFalse);
  });

  test('a desktop cannot be sent down the tablet path', () async {
    final container = _device(
      TerminalRole.main,
      source: InMemorySiteLicenceSource(_site()),
    );
    await _connect(container);

    expect(container.read(setupProvider).mainDeviceLinked, isFalse);
    expect(container.read(setupProvider).claims, isNull);
  });

  group('the licence a child reads', () {
    SiteLicenceService service(SiteLicence licence) => SiteLicenceService(
      source: InMemorySiteLicenceSource(licence),
      verifySignature: (_) async => true,
      clock: DateTime.now,
      restaurantId: 7,
    );

    const tablet = DeploymentConfig(
      mode: DeploymentMode.offline,
      tenantSlug: 'islanded',
      databaseHost: '192.168.1.20',
      role: TerminalRole.child,
    );

    test('is not refused for being pinned to the main device', () async {
      final pinned = _claims(fingerprints: {'the-main-device'});
      final verdict = await service(_site(claims: pinned)).current(tablet);

      expect(verdict.canSell, isTrue);
      // …which a desktop holding the same licence still is.
      expect(
        LicenseVerifier.evaluateClaims(
          claims: pinned,
          deployment: tablet,
          now: DateTime.now(),
          terminalFingerprint: 'a-desktop',
        ).state,
        LicenseState.terminalNotLicensed,
      );
    });

    test('is still judged on its tenant', () async {
      final verdict = await service(_site()).current(
        tablet.copyWith(tenantSlug: 'somebody-else'),
      );

      expect(verdict.state, LicenseState.tenantMismatch);
    });

    test('cannot be replaced by typing a key on the tablet', () async {
      expect(service(_site()).canActivateOnline, isFalse);
    });
  });

  test('the role survives a restart, and an old config reads as a main '
      'device', () {
    const child = DeploymentConfig(
      mode: DeploymentMode.offline,
      databaseHost: '192.168.1.20',
      role: TerminalRole.child,
    );
    expect(DeploymentConfig.fromJson(child.toJson()).role, TerminalRole.child);

    final legacy = child.toJson()..remove('role');
    expect(DeploymentConfig.fromJson(legacy).role, TerminalRole.main);
  });
}
