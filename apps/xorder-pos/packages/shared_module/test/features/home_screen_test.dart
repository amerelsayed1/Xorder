import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/domain/models/order_type_config.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/home/home_screen.dart';
import 'package:shared_module/features/licensing/domain/license.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

final _shift = PosShift(
  id: 3,
  openedAt: DateTime(2026, 10, 26, 9),
  openingFloat: const Money(0),
  openedByName: 'Rana A.',
);

/// Someone who may open a shift and sell, and nothing more.
const _cashier = PosStaff(
  id: 2,
  name: 'Rana A.',
  username: 'rana',
  capabilities: {PosCapability.operate, PosCapability.shiftOpen},
);

/// The home screen's buttons follow the back office (pos-home-screen), and its
/// shift and day buttons follow who is signed in (pos-signin-first-home).
void main() {
  setUpAll(loadPosFonts);

  late ProviderContainer container;
  var backs = 0;

  /// What the business configured, as a test can change it mid-flight.
  final configured = StateProvider<OrderTypeRules>(
    (ref) => OrderTypeRules.fallback,
  );

  Future<List<OrderType>> pump(
    WidgetTester tester, {
    String language = 'en',
    Size size = const Size(1440, 900),
    OrderTypeRules? rules,
    Future<OrderTypeRules>? pending,
    void Function(OrderType)? onPick,
    bool shiftOpen = true,
    PosStaff? staff = _cashier,
    bool licenceBlocked = false,
    VoidCallback? onShiftOpened,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final picked = <OrderType>[];
    backs = 0;
    container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        shiftProvider.overrideWith((ref) async => shiftOpen ? _shift : null),
        licenceEntitlementProvider.overrideWith(
          (ref) async => LicenseEntitlement(
            state: licenceBlocked ? LicenseState.expired : LicenseState.valid,
            canOpenShift: !licenceBlocked,
            canSell: true,
            canChangeConfiguration: true,
          ),
        ),
        orderTypeConfigProvider.overrideWith(
          (ref) => pending ?? Future.value(ref.watch(configured)),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (rules != null) container.read(configured.notifier).state = rules;
    if (staff != null) {
      container.read(signedInStaffProvider.notifier).signIn(staff);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          theme: buildPosTheme(),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            onShiftOpened: onShiftOpened,
            onBack: () => backs++,
            onPick: (type) {
              picked.add(type);
              onPick?.call(type);
            },
          ),
        ),
      ),
    );
    // A spinner never settles; one frame is the point of the loading test.
    pending == null ? await tester.pumpAndSettle() : await tester.pump();
    return picked;
  }

  Finder button(OrderType type) => find.byKey(Key('home-type-${type.wire}'));
  List<String> buttons(WidgetTester tester) => [
    for (final element
        in find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('home-type-'),
            )
            .evaluate())
      (element.widget.key! as ValueKey<String>).value.substring(10),
  ];

  testWidgets('one button per enabled type, in order, with the business\'s '
      'English names and a number each', (tester) async {
    await pump(tester);

    expect(buttons(tester), ['dine_in', 'takeaway', 'delivery', 'drive_thru']);
    expect(find.text('Dine in'), findsOneWidget);
    expect(find.text('Takeaway'), findsOneWidget);
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('Drive-thru'), findsOneWidget);
    for (final n in ['1', '2', '3', '4']) {
      expect(find.text(n), findsOneWidget, reason: 'key $n');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Arabic: the Arabic names, and it fits the smallest window', (
    tester,
  ) async {
    await pump(tester, language: 'ar', size: const Size(1024, 700));

    for (final name in ['صالة', 'تيك أواي', 'دليفري', 'سيارة']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  testWidgets('the names and the order are the back office\'s own', (
    tester,
  ) async {
    await pump(
      tester,
      rules: const OrderTypeRules([
        OrderTypeConfig(
          type: OrderType.takeaway,
          nameEn: 'Counter',
          sortOrder: 1,
        ),
        OrderTypeConfig(
          type: OrderType.dineIn,
          nameEn: 'Floor',
          requiresTable: true,
          sortOrder: 2,
        ),
      ]),
    );

    expect(buttons(tester), ['takeaway', 'dine_in']);
    expect(find.text('Counter'), findsOneWidget);
    expect(find.text('Floor'), findsOneWidget);
    expect(find.text('Takeaway'), findsNothing);
  });

  testWidgets('a type turned off has no button, and one turned on arrives '
      'without a restart', (tester) async {
    await pump(
      tester,
      rules: const OrderTypeRules([
        OrderTypeConfig(
          type: OrderType.dineIn,
          nameEn: 'Dine in',
          requiresTable: true,
        ),
        OrderTypeConfig(type: OrderType.takeaway, nameEn: 'Takeaway'),
        OrderTypeConfig(
          type: OrderType.delivery,
          nameEn: 'Delivery',
          isActive: false,
        ),
      ]),
    );
    expect(buttons(tester), ['dine_in', 'takeaway']);

    container.read(configured.notifier).state = const OrderTypeRules([
      OrderTypeConfig(
        type: OrderType.dineIn,
        nameEn: 'Dine in',
        requiresTable: true,
      ),
      OrderTypeConfig(type: OrderType.takeaway, nameEn: 'Takeaway'),
      OrderTypeConfig(type: OrderType.delivery, nameEn: 'Delivery'),
    ]);
    await tester.pumpAndSettle();
    expect(buttons(tester), ['dine_in', 'takeaway', 'delivery']);
  });

  testWidgets('a tap, and the keys 1–4 and the numpad, report the choice', (
    tester,
  ) async {
    final picked = await pump(tester);

    await tester.tap(button(OrderType.takeaway));
    await tester.pump();
    expect(picked, [OrderType.takeaway]);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9); // no ninth button
    await tester.pump();
    expect(picked, [OrderType.takeaway, OrderType.dineIn, OrderType.delivery]);
  });

  testWidgets('Escape is the back button: it reports a step back, not a '
      'choice', (tester) async {
    final picked = await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(backs, 1);
    expect(picked, isEmpty);
  });

  testWidgets('one enabled type: no choice is shown, the screen forwards', (
    tester,
  ) async {
    final picked = await pump(
      tester,
      rules: const OrderTypeRules([
        OrderTypeConfig(type: OrderType.takeaway, nameEn: 'Takeaway'),
      ]),
    );

    expect(picked, [OrderType.takeaway], reason: 'forwarded once');
    // Not even a second time on a rebuild.
    await tester.pump(const Duration(seconds: 1));
    expect(picked, hasLength(1));
  });

  testWidgets('while the configuration is loading: a wait, no buttons', (
    tester,
  ) async {
    final never = Completer<OrderTypeRules>();
    final picked = await pump(tester, pending: never.future);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(buttons(tester), isEmpty);
    expect(picked, isEmpty);

    // Let the fakes' timers run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  group('before a shift is open', () {
    final startShift = find.byKey(const Key('home-start-shift'));

    testWidgets('Start shift is offered, and the order types wait for it', (
      tester,
    ) async {
      final picked = await pump(tester, shiftOpen: false);

      expect(startShift, findsOneWidget);
      expect(find.text('Signed in as Rana A.'), findsOneWidget);
      expect(find.text('Start a shift to sell.'), findsOneWidget);

      // The buttons are there, dead: a tap and the number keys choose nothing.
      expect(buttons(tester), [
        'dine_in',
        'takeaway',
        'delivery',
        'drive_thru',
      ]);
      await tester.tap(button(OrderType.takeaway), warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(picked, isEmpty);
    });

    testWidgets('a branch that sells one way sees only Start shift, and is '
        'not forwarded', (tester) async {
      final picked = await pump(
        tester,
        shiftOpen: false,
        rules: const OrderTypeRules([
          OrderTypeConfig(type: OrderType.takeaway, nameEn: 'Takeaway'),
        ]),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(startShift, findsOneWidget);
      expect(buttons(tester), isEmpty);
      expect(find.text('Start a shift to sell.'), findsNothing);
      expect(picked, isEmpty, reason: 'nothing to sell until a shift is open');
    });

    testWidgets('somebody who may not open a shift is told so, and offered '
        'no button', (tester) async {
      await pump(
        tester,
        shiftOpen: false,
        staff: const PosStaff(
          id: 5,
          name: 'Nour S.',
          username: 'nour',
          capabilities: {PosCapability.operate},
        ),
      );

      expect(startShift, findsNothing);
      expect(find.byKey(const Key('home-cannot-open-shift')), findsOneWidget);
    });

    testWidgets('a lapsed licence blocks the shift, and says cash-up is still '
        'there', (tester) async {
      var opened = 0;
      await pump(
        tester,
        shiftOpen: false,
        licenceBlocked: true,
        onShiftOpened: () => opened++,
      );

      expect(find.text('Licence required'), findsOneWidget);
      expect(find.textContaining('Cash-up and reprint'), findsOneWidget);
      await tester.tap(startShift, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(find.text('Open the drawer'), findsNothing);
    });

    testWidgets('Start shift asks for the float only, and reports the shift '
        'opened', (tester) async {
      var opened = 0;
      await pump(
        tester,
        shiftOpen: false,
        onShiftOpened: () => opened++,
        // Not under test: the day opens with the first shift as before.
      );

      await tester.tap(startShift);
      await tester.pumpAndSettle();

      // No name and PIN: the person signed in at Start.
      expect(find.text('Open the drawer'), findsOneWidget);
      await tester.tap(find.text('Open shift'));
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(
        (await container.read(shiftRepositoryProvider).current())?.openedByName,
        'Rana A.',
      );
    });
  });

  testWidgets('before a shift, in Arabic: Start shift and the reason, and it '
      'fits the smallest window', (tester) async {
    await pump(
      tester,
      language: 'ar',
      size: const Size(1024, 700),
      shiftOpen: false,
    );

    expect(find.text('بدء الوردية'), findsOneWidget); // startShift
    expect(find.text('ابدأ وردية لتبدأ البيع.'), findsOneWidget);
    expect(find.text('مسجّل الدخول: Rana A.'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  group('signing out', () {
    testWidgets('Sign out signs the person out and steps back to Start', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('home-sign-out')));
      await tester.pump();

      expect(container.read(signedInStaffProvider), isNull);
      expect(backs, 1);
    });

    testWidgets('Escape does the same', (tester) async {
      await pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(container.read(signedInStaffProvider), isNull);
      expect(backs, 1);
    });
  });
}
