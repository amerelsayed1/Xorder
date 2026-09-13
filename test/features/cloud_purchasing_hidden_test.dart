import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart' show etaFilingEnabled;
import 'package:xorder_pos/features/admin/presentation/management_purchasing_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_roles_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/admin/presentation/management_staff_pane.dart';

import '../support/fakes.dart';

/// CB-09 slice e: on a cloud till the platform authors buying and stock.
///
/// The claim is about deployment, not permission. The platform withholds
/// `purchase.manage` from every bundle, but roles are the till's own even on
/// cloud, so a local Owner or Manager role — or a direct grant — still carries
/// it. Every test here therefore gives the person the capability and asserts
/// the panes are gone anyway; a test with nobody holding it would pass on the
/// old capability gate and prove nothing.
void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    role: PosRole(
      id: 1,
      code: SystemRoles.ownerCode,
      nameEn: 'Owner',
      capabilities: SystemRoles.owner,
    ),
  );
  const manager = PosStaff(
    id: 2,
    name: 'Nour S.',
    username: 'nour',
    role: PosRole(
      id: 2,
      code: SystemRoles.managerCode,
      nameEn: 'Manager',
      capabilities: SystemRoles.manager,
    ),
  );
  // No role at all: the grant against their own name is the whole of it.
  const granted = PosStaff(
    id: 3,
    name: 'Hady K.',
    username: 'hady',
    capabilities: {PosCapability.staffManage, PosCapability.purchaseManage},
  );
  const buyers = [owner, manager, granted];

  const platformAuthored = [
    ManagementPane.purchasing,
    ManagementPane.items,
    ManagementPane.stock,
    ManagementPane.units,
  ];

  group('which panes a cloud till has', () {
    test('none of the four, even for an owner who holds purchase.manage', () {
      expect(
        owner.can(PosCapability.purchaseManage),
        isTrue,
        reason: 'the premise: the capability alone would have let them in',
      );
      final panes = managementPanesFor(
        admin: owner,
        authorsItsOwnCatalogue: false,
      );
      for (final pane in platformAuthored) {
        expect(panes, isNot(contains(pane)), reason: pane.name);
      }
      final areas = [
        for (final (area, _) in managementAreasFor(
          admin: owner,
          authorsItsOwnCatalogue: false,
        ))
          area,
      ];
      expect(areas, isNot(contains(ManagementArea.buying)));
      expect(areas, isNot(contains(ManagementArea.inventory)));
    });

    test('nor for a local Manager role, nor for a direct grant', () {
      for (final staff in [manager, granted]) {
        expect(staff.can(PosCapability.purchaseManage), isTrue);
        final panes = managementPanesFor(
          admin: staff,
          authorsItsOwnCatalogue: false,
        );
        for (final pane in platformAuthored) {
          expect(panes, isNot(contains(pane)), reason: '${staff.name}: $pane');
        }
      }
    });

    test('offline is unchanged: the owner has every pane, the four included',
        () {
      // Every pane this build shows at all: e-receipt filing is a build switch
      // (off since 2026-09-13), and it hides ETA on both deployments alike.
      expect(
        managementPanesFor(admin: owner, authorsItsOwnCatalogue: true),
        [
          for (final pane in ManagementPane.values)
            if (pane != ManagementPane.eta || etaFilingEnabled) pane,
        ],
      );
      final panes = managementPanesFor(
        admin: manager,
        authorsItsOwnCatalogue: true,
      );
      for (final pane in platformAuthored) {
        expect(panes, contains(pane), reason: pane.name);
      }
      // Still the owner's alone — the capability gate is untouched.
      expect(panes, isNot(contains(ManagementPane.backup)));
    });

    test('cloud is offline less exactly what the platform authors', () {
      // Pins the rule both ways: nothing else moved, and this is the whole set.
      expect(
        {
          for (final pane in ManagementPane.values)
            if (hiddenBecausePlatformAuthors(
              pane,
              authorsItsOwnCatalogue: false,
            ))
              pane,
        },
        {ManagementPane.menu, ManagementPane.floor, ...platformAuthored},
      );
      for (final staff in buyers) {
        expect(
          managementPanesFor(admin: staff, authorsItsOwnCatalogue: false),
          [
            for (final pane in managementPanesFor(
              admin: staff,
              authorsItsOwnCatalogue: true,
            ))
              if (!hiddenBecausePlatformAuthors(
                pane,
                authorsItsOwnCatalogue: false,
              ))
                pane,
          ],
          reason: staff.name,
        );
      }
      for (final pane in ManagementPane.values) {
        expect(
          hiddenBecausePlatformAuthors(pane, authorsItsOwnCatalogue: true),
          isFalse,
          reason: 'offline authors everything: $pane',
        );
      }
    });
  });

  group('the Manage menu agrees with the rail', () {
    const s = EnStrings();

    List<ManagementBarEntry> lines(
      PosStaff staff, {
      required bool authors,
    }) => [
      for (final (_, entries) in managementBarFor(
        s,
        admin: staff,
        authorsItsOwnCatalogue: authors,
      ))
        ...entries,
    ];

    test('on cloud, every pane line names a pane the rail has, and only those',
        () {
      for (final staff in buyers) {
        final rail = managementPanesFor(
          admin: staff,
          authorsItsOwnCatalogue: false,
        );
        final panes = [
          for (final line in lines(staff, authors: false)) ?line.pane,
        ];
        expect(panes.toSet(), rail.toSet(), reason: staff.name);
        for (final line in lines(staff, authors: false)) {
          if (line.pane == null) continue;
          expect(rail, contains(line.open().pane), reason: line.label);
        }
        expect(
          [for (final (area, _) in managementBarFor(
            s,
            admin: staff,
            authorsItsOwnCatalogue: false,
          )) area],
          isNot(contains(ManagementArea.inventory)),
        );
      }
    });

    test('and Buying is one pointer, which lands on the notice', () {
      final bar = managementBarFor(
        s,
        admin: owner,
        authorsItsOwnCatalogue: false,
      );
      final buying = bar.firstWhere((a) => a.$1 == ManagementArea.buying).$2;
      expect(buying, hasLength(1));
      expect(buying.single.pane, isNull, reason: 'a pointer, not a pane');
      expect(buying.single.label, s.purchasingOnPlatformEntry);

      final landing = buying.single.open();
      expect(
        hiddenBecausePlatformAuthors(
          landing.pane,
          authorsItsOwnCatalogue: false,
        ),
        isTrue,
        reason: 'the screen falls back and says why, rather than refusing',
      );
      expect(
        platformAuthoredPointer(s, landing.pane),
        s.purchasingComesFromPlatform,
      );
      expect(
        [for (final line in lines(owner, authors: false)) if (line.pane == null) line],
        hasLength(1),
        reason: 'one pointer in the whole bar',
      );
    });

    test('offline, the bar is what it was: Buying\'s seven lines, no pointer',
        () {
      expect(
        lines(owner, authors: true).where((line) => line.pane == null),
        isEmpty,
      );
      final bar = managementBarFor(
        s,
        admin: owner,
        authorsItsOwnCatalogue: true,
      );
      expect(
        [for (final (area, _) in bar) area],
        [
          for (final (area, _) in managementAreasFor(
            admin: owner,
            authorsItsOwnCatalogue: true,
          ))
            area,
        ],
      );
      expect(
        [
          for (final line
              in bar.firstWhere((a) => a.$1 == ManagementArea.buying).$2)
            line.label,
        ],
        [
          for (final (label, _, _)
              in managementMenuEntries(s, ManagementPane.purchasing))
            label,
        ],
      );
      expect(
        [
          for (final line
              in bar.firstWhere((a) => a.$1 == ManagementArea.inventory).$2)
            line.pane,
        ],
        [ManagementPane.items, ManagementPane.stock, ManagementPane.units],
      );
    });
  });

  test('the pointer covers buying and inventory, and nothing else', () {
    const s = EnStrings();
    for (final pane in ManagementPane.values) {
      final buyingOrStock =
          areaOf(pane) == ManagementArea.buying ||
          areaOf(pane) == ManagementArea.inventory;
      expect(
        platformAuthoredPointer(s, pane) != null,
        buyingOrStock,
        reason: pane.name,
      );
    }
  });

  group('a deep link to a platform-authored pane', () {
    const cloud = DeploymentConfig(
      mode: DeploymentMode.cloud,
      baseUrl: 'https://xorder.io',
      tenantSlug: 'mahsoub',
    );

    /// The back office asking for [pane] — pumped again with another pane, it
    /// is what the bar does to a screen that is already open.
    Widget screen(
      ProviderContainer container, {
      required ManagementPane pane,
      String language = 'en',
    }) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: ManagementScreen(
          onClose: () {},
          onReconfigure: () {},
          initialPane: pane,
        ),
      ),
    );

    /// Cloud by DEPLOYMENT, not by an override: the provider the rule reads is
    /// derived from the mode, and this is where that is proved. [offline]
    /// binds a catalogue administrator instead, as an offline till has.
    Future<ProviderContainer> open(
      WidgetTester tester, {
      required ManagementPane pane,
      String language = 'en',
      bool offline = false,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          if (offline) offlineTerminal(),
        ],
      );
      addTearDown(container.dispose);
      if (!offline) container.read(deploymentProvider.notifier).apply(cloud);

      await tester.pumpWidget(screen(container, pane: pane, language: language));
      await tester.pumpAndSettle();

      // Through the door as Amer, the owner — every capability, purchasing's
      // included.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('back-office-username')),
          matching: find.byType(TextField),
        ),
        'amer',
      );
      await tester.enterText(
        find.byKey(const Key('back-office-password')),
        'test-credential',
      );
      await tester.tap(find.byKey(const Key('back-office-open')));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('lands on Staff on a cloud till, and says where buying went', (
      tester,
    ) async {
      final container = await open(tester, pane: ManagementPane.purchasing);

      expect(container.read(catalogAdminRepositoryProvider), isNull);
      expect(
        container.read(signedInStaffProvider)!.can(PosCapability.purchaseManage),
        isTrue,
      );

      expect(find.byType(ManagementPurchasingPane), findsNothing);
      expect(find.byType(ManagementStaffPane), findsOneWidget);
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsOneWidget,
      );
      expect(
        find.text(const EnStrings().purchasingComesFromPlatform),
        findsOneWidget,
      );
    });

    testWidgets('and says it in Arabic on an Arabic till', (tester) async {
      await open(tester, pane: ManagementPane.units, language: 'ar');

      expect(
        find.text(const ArStrings().purchasingComesFromPlatform),
        findsOneWidget,
      );
      expect(
        find.text(const EnStrings().purchasingComesFromPlatform),
        findsNothing,
      );
    });

    // Asked for through the screen's own inputs rather than a tab: every pane
    // is its own page now, and the bar re-asking is the only way to move on.
    testWidgets('asking for another pane moves on, and the sentence goes too', (
      tester,
    ) async {
      final container = await open(tester, pane: ManagementPane.stock);
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsOneWidget,
      );

      await tester.pumpWidget(screen(container, pane: ManagementPane.roles));
      await tester.pumpAndSettle();

      expect(find.byType(ManagementRolesPane), findsOneWidget);
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsNothing,
      );
    });

    testWidgets('offline, the same link opens Purchasing and says nothing', (
      tester,
    ) async {
      await open(tester, pane: ManagementPane.purchasing, offline: true);

      expect(find.byType(ManagementPurchasingPane), findsOneWidget);
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsNothing,
      );
    });
  });

  test('the pointer is a real sentence in both languages', () {
    for (final s in const <AppStrings>[EnStrings(), ArStrings()]) {
      expect(s.purchasingComesFromPlatform, contains('xorder.io'));
      expect(s.purchasingOnPlatformEntry, contains('xorder.io'));
    }
    // Arabic words, not the English left in place.
    expect(
      const ArStrings().purchasingComesFromPlatform,
      contains('المشتريات'),
    );
    expect(
      const ArStrings().purchasingOnPlatformEntry,
      isNot(const EnStrings().purchasingOnPlatformEntry),
    );
  });
}
