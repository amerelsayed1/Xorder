import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/home/home_screen.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// The home screen's buttons follow the back office (pos-home-screen).
void main() {
  setUpAll(loadPosFonts);

  late ProviderContainer container;
  var backs = 0;

  /// What the restaurant configured, as a test can change it mid-flight.
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
        orderTypeConfigProvider.overrideWith(
          (ref) => pending ?? Future.value(ref.watch(configured)),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (rules != null) container.read(configured.notifier).state = rules;

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

  testWidgets('one button per enabled type, in order, with the restaurant\'s '
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
}
