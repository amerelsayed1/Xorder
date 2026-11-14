import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/lan_tls.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/features/licensing/data/site_licence.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/presentation/setup_wizard.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/lan_tls_fixtures.dart';

/// A child till learns to trust its database server on the connection step
/// (ADR-006, slice C).
///
/// The first connection is refused for a certificate nobody has confirmed;
/// the wizard shows the fingerprint the server presented, the technician
/// compares it with the main device's Management pane and confirms, and the
/// till connects again — now trusting exactly that certificate. Nothing on
/// this screen connects without encryption, and nothing is trusted until a
/// person presses the button.
void main() {
  const en = EnStrings();
  final presentedA = PresentedCertificate.fromPem(fixtureACertificate)!;

  group('the child wizard', () {
    Future<({ProviderContainer container, _PinnedOnlySource source})> open(
      WidgetTester tester, {
      CertificateFetch? fetch,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final source = _PinnedOnlySource();
      final probe = _FakeProbe(fetch ?? CertificateFetched(presentedA));
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          deviceRoleProvider.overrideWithValue(TerminalRole.child),
          siteLicenceSourceProvider.overrideWithValue(source),
          serverCertificateProbeProvider.overrideWithValue(probe),
        ],
      );
      addTearDown(container.dispose);
      // The source answers only a till whose PUBLISHED transport is the pin —
      // what a real hostssl server does — so a pass below means the second
      // attempt carried the pin, not that the fake gave up.
      source.paired = () =>
          container.read(deploymentProvider).lanTls.transport ==
          LanTransport.pinned;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildPosTheme(),
            home: SetupWizard(onFinished: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      container.read(setupProvider.notifier)
        ..setDatabaseHost('192.168.1.20')
        ..setDatabasePassword('till-secret');
      await tester.pumpAndSettle();
      return (container: container, source: source);
    }

    testWidgets('shows the fingerprint the server presented, and trusts '
        'nothing until it is confirmed', (tester) async {
      final app = await open(tester);

      await tester.tap(find.text(en.connectToMainDevice));
      await tester.pumpAndSettle();

      final draft = app.container.read(setupProvider);
      expect(draft.error, en.tlsUntrusted);
      expect(draft.mainDeviceLinked, isFalse);
      expect(draft.canAdvance, isFalse);
      // Shown, in the shape the main device shows it…
      expect(
        find.text(LanTls.formatFingerprint(fixtureASha256)),
        findsOneWidget,
      );
      expect(find.text(en.serverCertificateCompare), findsOneWidget);
      // …and not yet trusted by anything.
      expect(draft.deployment.pinnedCertificateSha256, isNull);
      expect(draft.deployment.lanTls.transport, LanTransport.verifiedChain);
      expect(app.source.reads, 1);
    });

    testWidgets('confirming pins that certificate and connects with it', (
      tester,
    ) async {
      final app = await open(tester);
      await tester.tap(find.text(en.connectToMainDevice));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('setup-trust-certificate')));
      await tester.pumpAndSettle();

      final draft = app.container.read(setupProvider);
      expect(draft.error, isNull, reason: draft.error ?? '');
      expect(draft.mainDeviceLinked, isTrue);
      expect(draft.presentedCertificate, isNull);
      expect(draft.deployment.pinnedCertificateSha256, fixtureASha256);
      expect(draft.deployment.lanTls.transport, LanTransport.pinned);
      expect(draft.deployment.allowInsecureLan, isFalse);
      expect(app.source.reads, 2);

      // The step now says what it trusts, rather than asking again.
      expect(find.text(en.serverCertificatePaired), findsOneWidget);
      expect(find.byKey(const Key('setup-trust-certificate')), findsNothing);
      expect(
        find.text(LanTls.formatFingerprint(fixtureASha256)),
        findsOneWidget,
      );
    });

    testWidgets('a new address forgets the pin and the offer', (tester) async {
      final app = await open(tester);
      await tester.tap(find.text(en.connectToMainDevice));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setup-trust-certificate')));
      await tester.pumpAndSettle();

      app.container.read(setupProvider.notifier).setDatabaseHost('192.168.1.21');
      await tester.pumpAndSettle();

      final draft = app.container.read(setupProvider);
      expect(draft.deployment.pinnedCertificateSha256, isNull);
      expect(draft.presentedCertificate, isNull);
      expect(find.byKey(const Key('setup-server-certificate')), findsNothing);
    });

    testWidgets('a server with no TLS is named, and offers nothing to trust', (
      tester,
    ) async {
      final app = await open(tester, fetch: const ServerOffersNoTls());
      await tester.tap(find.text(en.connectToMainDevice));
      await tester.pumpAndSettle();

      final draft = app.container.read(setupProvider);
      expect(draft.error, en.tlsNotOffered);
      expect(draft.presentedCertificate, isNull);
      expect(find.byKey(const Key('setup-trust-certificate')), findsNothing);
      expect(draft.deployment.lanTls.transport.encrypted, isTrue,
          reason: 'refused, not downgraded');
    });

    testWidgets('the old "trust without a certificate" tick is gone', (
      tester,
    ) async {
      await open(tester);
      // Any wording of it: the only way past the certificate is to compare it.
      expect(find.textContaining('without a certificate'), findsNothing);
    });
  });

  group('a main device pointed at a database on the LAN', () {
    test('a refused certificate is explained, with the fingerprint to compare',
        () async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
          posDatabaseProvider.overrideWithValue(_ProbesAs(PosDbFailure.tls)),
          serverCertificateProbeProvider.overrideWithValue(
            _FakeProbe(CertificateFetched(presentedA)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier)
        ..setDatabaseHost('192.168.1.20')
        ..setDatabasePassword('s3cret');

      expect(await controller.testConnection(), isFalse);

      final draft = container.read(setupProvider);
      expect(draft.error, en.tlsUntrusted);
      expect(draft.presentedCertificate?.sha256, fixtureASha256);
      expect(draft.deployment.pinnedCertificateSha256, isNull);
    });

    test('the pinned certificate refused for its name says so', () async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
          posDatabaseProvider.overrideWithValue(_ProbesAs(PosDbFailure.tls)),
          serverCertificateProbeProvider.overrideWithValue(
            _FakeProbe(CertificateFetched(presentedA)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier)
        ..setDatabaseHost('192.168.1.20')
        ..setDatabasePassword('s3cret');
      controller.state = container.read(setupProvider).copyWith(
        deployment: container.read(setupProvider).deployment.copyWith(
          pinnedCertificateSha256: fixtureASha256,
          pinnedCertificatePem: fixtureACertificate,
        ),
      );

      await controller.testConnection();

      final draft = container.read(setupProvider);
      expect(draft.error, en.tlsNameMismatch('192.168.1.20'));
      expect(draft.presentedCertificate, isNull,
          reason: 'it is already trusted; there is nothing to confirm');
    });
  });
}

/// A main device's shared licence, readable only over a pinned connection.
class _PinnedOnlySource implements SiteLicenceSource {
  bool Function() paired = () => false;
  int reads = 0;

  @override
  Future<SiteLicence?> read({int? businessId}) async {
    reads++;
    if (!paired()) {
      throw PosDbException(
        PosDbFailure.tls,
        'HandshakeException: CERTIFICATE_VERIFY_FAILED: self signed '
        'certificate',
      );
    }
    final now = DateTime.now();
    final claims = LicenseClaims(
      licenseId: 'LIC-SITE-0001',
      tenantSlug: 'islanded',
      tenantName: 'The Islanded Cafe',
      issuedAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 365)),
      maxTerminals: 3,
      features: const {'pos'},
      modes: const {DeploymentMode.offline},
    );
    return SiteLicence(
      file: LicenseFile(
        payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
        signatureB64: base64Url.encode(List<int>.filled(64, 0)),
        keyId: 'dev',
      ),
      businessId: 7,
      mode: DeploymentMode.offline,
      terminalCount: 1,
    );
  }

  @override
  Future<void> publish({
    required int businessId,
    required LicenseFile file,
    required DeploymentMode mode,
  }) async {}
}

class _FakeProbe implements ServerCertificateProbe {
  _FakeProbe(this.answer);

  final CertificateFetch answer;

  @override
  Future<CertificateFetch> fetch(String host, int port) async => answer;
}

class _ProbesAs extends PosDatabase {
  _ProbesAs(this.failure) : super(credentials: MutablePosDbCredentials());

  final PosDbFailure? failure;

  @override
  Future<PosDbFailure?> probe(DeploymentConfig config) async => failure;
}
