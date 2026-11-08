import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/app.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/router.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
import 'package:xorder_pos/features/setup/presentation/wrong_app_screen.dart';
import 'package:xorder_pos/pos_main.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// One app per machine (pos-split-apps, BR-8).
///
/// A `config.json` written by "XOrder POS - Cloud" is not opened by "XOrder
/// POS - Offline", and the other way round. [bootFor] is the rule, pure; the
/// router then parks the till on a screen that names the app which owns the
/// machine, and nothing else is reachable — not the wizard.
void main() {
  const terminal = TerminalProfile(
    branchId: 13,
    branchName: 'Maadi',
    terminalName: 'Counter 1',
    terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
    businessId: 7,
    branchCode: 'MAA',
  );

  SavedTerminalConfig saved(DeploymentMode mode) => SavedTerminalConfig(
    deployment: DeploymentConfig(mode: mode, databaseHost: '192.168.1.20'),
    terminal: terminal,
    languageCode: 'ar',
  );

  group('bootFor', () {
    for (final mode in DeploymentMode.values) {
      test('${mode.productName} opens its own configuration', () {
        final boot = bootFor(
          saved: saved(mode),
          appMode: mode,
          hasDatabaseCredential: true,
          credentialStoreUnavailable: false,
        );
        expect(boot.config, same(boot.config));
        expect(boot.config?.deployment.mode, mode);
        expect(boot.otherAppMode, isNull);
        // Whether it is *usable* is `SavedTerminalConfig.isUsable`'s question
        // (a cloud till also needs its platform address); this rule only
        // decides whose configuration it is.
      });

      test('${mode.productName} refuses the other app\'s configuration', () {
        final boot = bootFor(
          saved: saved(mode.other),
          appMode: mode,
          hasDatabaseCredential: true,
          credentialStoreUnavailable: false,
        );
        // Not configured, and not a fresh install either: the file is left
        // where it is for the app that wrote it.
        expect(boot.config, isNull);
        expect(boot.isConfigured, isFalse);
        expect(boot.otherAppMode, mode.other);
      });

      test('${mode.productName} on a fresh machine is a fresh install', () {
        final boot = bootFor(
          saved: null,
          appMode: mode,
          hasDatabaseCredential: false,
          credentialStoreUnavailable: false,
        );
        expect(boot.config, isNull);
        expect(boot.otherAppMode, isNull);
        expect(boot.isConfigured, isFalse);
      });
    }

    test('a child tablet is judged by its main device\'s mode too', () {
      final child = SavedTerminalConfig(
        deployment: const DeploymentConfig(
          mode: DeploymentMode.cloud,
          role: TerminalRole.child,
          databaseHost: '192.168.1.20',
        ),
        terminal: terminal,
        languageCode: 'en',
      );
      final boot = bootFor(
        saved: child,
        appMode: DeploymentMode.offline,
        hasDatabaseCredential: true,
        credentialStoreUnavailable: false,
      );
      expect(boot.otherAppMode, DeploymentMode.cloud);
    });
  });

  group('the router', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required DeploymentMode appMode,
      required TerminalBoot boot,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(appMode: appMode),
          terminalBootProvider.overrideWithValue(boot),
        ],
      );
      addTearDown(container.dispose);
      container.read(localeProvider.notifier).apply('en');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const XorderPosApp(),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('parks the till on the wrong-app screen and names the owner', (
      tester,
    ) async {
      final container = await pump(
        tester,
        appMode: DeploymentMode.offline,
        boot: const TerminalBoot(otherAppMode: DeploymentMode.cloud),
      );

      expect(find.byType(WrongAppScreen), findsOneWidget);
      expect(find.textContaining('XOrder POS - Cloud'), findsWidgets);
      expect(find.textContaining('XOrder POS - Offline'), findsWidgets);

      // No way on: the wizard's route redirects straight back here.
      container.read(routerProvider).go(PosRoutes.setup);
      await tester.pumpAndSettle();
      expect(find.byType(WrongAppScreen), findsOneWidget);
      container.read(routerProvider).go(PosRoutes.start);
      await tester.pumpAndSettle();
      expect(find.byType(WrongAppScreen), findsOneWidget);
    });

    testWidgets('an ordinary fresh install never sees it', (tester) async {
      await pump(
        tester,
        appMode: DeploymentMode.cloud,
        boot: TerminalBoot.none,
      );
      expect(find.byType(WrongAppScreen), findsNothing);
    });
  });
}
