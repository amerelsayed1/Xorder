import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/config/lan_tls.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/postgres/pos_tls.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';
import '../support/lan_tls_fixtures.dart';

/// Management › Devices, the LAN encryption section (ADR-006, slice C).
///
/// The two claims it makes: on the main device, it shows the fingerprint a
/// technician compares a child against; and the only way to turn encryption
/// off is here, by somebody holding `terminal.manage`, with an audit row
/// written first — no row, no change.
void main() {
  const en = EnStrings();
  final presentedA = PresentedCertificate.fromPem(fixtureACertificate)!;

  const child = DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: '192.168.1.20',
    role: TerminalRole.child,
  );

  InMemoryTerminalConfigStore configStore(ProviderContainer container) =>
      container.read(terminalConfigStoreProvider)
          as InMemoryTerminalConfigStore;

  Future<ProviderContainer> open(
    WidgetTester tester, {
    required DeploymentConfig deployment,
    PresentedCertificate? published,
    CertificateFetch? fetch,
  }) async {
    // Tall enough that the section, last on the pane, is laid out.
    tester.view
      ..physicalSize = const Size(1440, 2200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        publishedServerCertificateSourceProvider.overrideWithValue(
          _Published(published),
        ),
        serverCertificateProbeProvider.overrideWithValue(
          _FakeProbe(fetch ?? CertificateFetched(presentedA)),
        ),
      ],
    );
    addTearDown(container.dispose);
    // A configured till has a config.json; the change has to land in it.
    configStore(container).saved = SavedTerminalConfig(
      deployment: deployment,
      terminal: const TerminalProfile(
        branchName: 'Maadi',
        terminalName: 'Counter 1',
        businessId: 7,
      ),
      languageCode: 'en',
    );
    container.read(deploymentProvider.notifier).apply(deployment);
    container.read(setupCompleteProvider.notifier).markComplete();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(
            onClose: () {},
            onReconfigure: () {},
            initialPane: ManagementPane.terminal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterAdminMode(tester);
    return container;
  }

  FakeAuditRepository ledger(ProviderContainer container) =>
      container.read(auditRepositoryProvider) as FakeAuditRepository;

  testWidgets('the main device shows the fingerprint its server presents', (
    tester,
  ) async {
    await open(
      tester,
      deployment: const DeploymentConfig(mode: DeploymentMode.offline),
      published: presentedA,
    );

    expect(find.text(en.serverCertificateThisMachine), findsOneWidget);
    expect(
      find.text(LanTls.formatFingerprint(fixtureASha256)),
      findsOneWidget,
    );
    // The date it stops being valid, in mono — 825 days is a date to see
    // coming.
    expect(find.text('2029-01-27'), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-published-certificate')),
      findsOneWidget,
    );
  });

  testWidgets('a main device with no LAN certificate says so', (tester) async {
    await open(
      tester,
      deployment: const DeploymentConfig(mode: DeploymentMode.offline),
    );

    expect(find.text(en.serverCertificateNone), findsOneWidget);
    // A till on loopback has no LAN transport to change.
    expect(find.byKey(const Key('terminal-lan-encryption-off')), findsNothing);
  });

  testWidgets('a paired child shows what it trusts', (tester) async {
    await open(
      tester,
      deployment: child.copyWith(
        pinnedCertificateSha256: fixtureASha256,
        pinnedCertificatePem: fixtureACertificate,
      ),
    );

    expect(find.text(en.lanEncryptedPinned), findsOneWidget);
    expect(find.byKey(const Key('terminal-pinned-certificate')), findsOneWidget);
    expect(find.text(en.serverCertificateNone), findsNothing,
        reason: 'a child holds no server');
  });

  testWidgets('turning encryption off is confirmed, audited, then applied', (
    tester,
  ) async {
    final container = await open(
      tester,
      deployment: child.copyWith(
        pinnedCertificateSha256: fixtureASha256,
        pinnedCertificatePem: fixtureACertificate,
      ),
    );

    await tester.tap(find.byKey(const Key('terminal-lan-encryption-off')));
    await tester.pumpAndSettle();
    expect(find.text(en.lanEncryptionTurnOffBody), findsOneWidget);
    await tester.tap(find.byKey(const Key('terminal-lan-encryption-confirm')));
    await tester.pumpAndSettle();

    final now = container.read(deploymentProvider);
    expect(now.isInsecureLan, isTrue);
    expect(now.pinnedCertificateSha256, isNull);

    final row = ledger(container).entries.first;
    expect(row.action, AuditAction.lanEncryptionChanged);
    expect(row.entityType, AuditAction.entityTerminal);
    expect(row.before?['transport'], LanTransport.pinned.name);
    expect(row.before?['pinned_sha256'], fixtureASha256);
    expect(row.after?['transport'], LanTransport.insecureLan.name);

    // And it survives a restart.
    final saved = configStore(container).saved!.deployment;
    expect(saved.isInsecureLan, isTrue);
    expect(saved.pinnedCertificateSha256, isNull);

    // And the warning is up.
    expect(find.byKey(const Key('terminal-insecure-lan')), findsOneWidget);
  });

  testWidgets('a disk that refuses config.json changes nothing, and says so', (
    tester,
  ) async {
    // The pane once applied first and swallowed this: it said "encryption
    // off", the ledger agreed, and a restart came back pinned.
    final container = await open(
      tester,
      deployment: child.copyWith(
        pinnedCertificateSha256: fixtureASha256,
        pinnedCertificatePem: fixtureACertificate,
      ),
    );
    configStore(container).refuseWrites = true;

    await tester.tap(find.byKey(const Key('terminal-lan-encryption-off')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terminal-lan-encryption-confirm')));
    await tester.pumpAndSettle();

    expect(container.read(deploymentProvider).lanTls.transport,
        LanTransport.pinned);
    expect(configStore(container).saved!.deployment.lanTls.transport,
        LanTransport.pinned);
    expect(find.text(en.lanEncryptionNotSaved), findsOneWidget);
    expect(find.byKey(const Key('terminal-insecure-lan')), findsNothing);

    // The ledger reads "changed, then changed back" — never a change that
    // stands in the log and nowhere else.
    final rows = ledger(container)
        .entries
        .where((e) => e.action == AuditAction.lanEncryptionChanged)
        .toList();
    expect(rows, hasLength(2));
    expect(rows.first.before?['transport'], LanTransport.insecureLan.name);
    expect(rows.first.after?['transport'], LanTransport.pinned.name);
    expect(rows.first.reason, isNotNull);
  });

  testWidgets('a ledger that refuses the row leaves encryption on', (
    tester,
  ) async {
    final container = await open(
      tester,
      deployment: child.copyWith(
        pinnedCertificateSha256: fixtureASha256,
        pinnedCertificatePem: fixtureACertificate,
      ),
    );
    ledger(container).failWith = StateError('ledger unreachable');

    await tester.tap(find.byKey(const Key('terminal-lan-encryption-off')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terminal-lan-encryption-confirm')));
    await tester.pumpAndSettle();

    expect(container.read(deploymentProvider).lanTls.transport,
        LanTransport.pinned);
    expect(find.text(en.lanEncryptionNotRecorded), findsOneWidget);
  });

  testWidgets('turning it back on is a pairing: compare, confirm, pinned', (
    tester,
  ) async {
    final container = await open(
      tester,
      deployment: child.copyWith(allowInsecureLan: true),
    );
    expect(find.byKey(const Key('terminal-insecure-lan')), findsOneWidget);

    await tester.tap(find.byKey(const Key('terminal-lan-encryption-on')));
    await tester.pumpAndSettle();
    // The fingerprint is the question.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(LanTls.formatFingerprint(fixtureASha256)),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('terminal-lan-encryption-confirm')));
    await tester.pumpAndSettle();

    final now = container.read(deploymentProvider);
    expect(now.lanTls.transport, LanTransport.pinned);
    expect(now.pinnedCertificateSha256, fixtureASha256);
    expect(now.allowInsecureLan, isFalse);
    expect(
      ledger(container).entries.first.after?['transport'],
      LanTransport.pinned.name,
    );
    expect(
      configStore(container).saved!.deployment.pinnedCertificateSha256,
      fixtureASha256,
      reason: 'pinned after a restart too',
    );
  });

  testWidgets('a server with nothing to compare leaves encryption off', (
    tester,
  ) async {
    final container = await open(
      tester,
      deployment: child.copyWith(allowInsecureLan: true),
      fetch: const ServerOffersNoTls(),
    );

    await tester.tap(find.byKey(const Key('terminal-lan-encryption-on')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text(en.lanEncryptionNoCertificate), findsOneWidget);
    expect(container.read(deploymentProvider).isInsecureLan, isTrue);
    expect(ledger(container).entries.where(
      (e) => e.action == AuditAction.lanEncryptionChanged,
    ), isEmpty);
  });
}

class _Published implements PublishedServerCertificateSource {
  const _Published(this.certificate);

  final PresentedCertificate? certificate;

  @override
  Future<PresentedCertificate?> read() async => certificate;
}

class _FakeProbe implements ServerCertificateProbe {
  _FakeProbe(this.answer);

  final CertificateFetch answer;

  @override
  Future<CertificateFetch> fetch(String host, int port) async => answer;
}
