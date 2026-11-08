import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/admin/presentation/order_type_dialog.dart';

/// What a kind of order requires, on screen (§31).
///
/// The claim worth testing is that the switch with teeth is reachable and comes
/// back attached to the right code. `requires a table` decides whether the router
/// offers a floor plan at all, and it used to be `type == OrderType.dineIn` in
/// three files.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  const takeaway = OrderTypeConfig(
    type: OrderType.takeaway,
    nameEn: 'Takeaway',
    nameAr: 'تيك أواي',
    sortOrder: 2,
  );

  Future<OrderTypeConfig?> Function() open(
    WidgetTester tester, {
    OrderTypeConfig config = takeaway,
    String locale = 'en',
  }) {
    OrderTypeConfig? saved;

    Future<void> run() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: Locale(locale),
            theme: buildPosTheme(PosPalette.light),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await OrderTypeDialog.show(
                      context,
                      config: config,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    return () async {
      await run();
      return saved;
    };
  }

  testWidgets('the code is shown and cannot be typed over', (tester) async {
    // Every place that renders an order type reads its name off the `OrderType`
    // enum, so the code is identity rather than data. A business renames the
    // label; it does not invent a fifth code.
    await open(tester)();

    expect(find.text('takeaway'), findsOneWidget);
    expect(
      find.byType(TextField),
      findsNWidgets(2),
      reason: 'the two names, and nothing else typable',
    );
  });

  testWidgets('turning on a table is what the floor plan reads', (
    tester,
  ) async {
    // The switch that used to be a comparison in three files. A caterer who
    // seats people turns it on for takeaway.
    OrderTypeConfig? saved;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await OrderTypeDialog.show(
                    context,
                    config: takeaway,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(takeaway.requiresTable, isFalse, reason: 'the starting point');

    await tester.tap(find.byKey(const Key('order-type-table')));
    await tester.enterText(
      find.byKey(const Key('order-type-name')),
      'Catering',
    );
    await tester.tap(find.byKey(const Key('order-type-save')));
    await tester.pumpAndSettle();

    expect(saved?.type, OrderType.takeaway, reason: 'the code is untouched');
    expect(saved?.requiresTable, isTrue);
    expect(saved?.nameEn, 'Catering');
    expect(saved?.nameAr, 'تيك أواي', reason: 'the Arabic name is kept');
    expect(saved?.sortOrder, 2, reason: 'and so is the order');
  });

  testWidgets('a nameless order type is refused beside the field', (
    tester,
  ) async {
    final result = open(tester);
    await result();

    await tester.enterText(find.byKey(const Key('order-type-name')), '   ');
    await tester.tap(find.byKey(const Key('order-type-save')));
    await tester.pumpAndSettle();

    expect(find.byType(OrderTypeDialog), findsOneWidget);
    expect(find.textContaining('needs a name'), findsOneWidget);
  });

  testWidgets('every switch says what it does, not just what it is', (
    tester,
  ) async {
    // "Has a table" tells a business owner nothing about the floor plan.
    await open(tester)();

    expect(find.textContaining('Turns on the floor plan'), findsOneWidget);
    expect(find.textContaining('customers are still being built'), findsOneWidget);
    expect(find.textContaining('takes it off the till'), findsOneWidget);
  });

  testWidgets('in Arabic too', (tester) async {
    await open(tester, locale: 'ar')();
    expect(find.textContaining('يفعّل مخطط الصالة'), findsOneWidget);
    expect(find.text('takeaway'), findsOneWidget, reason: 'the code is a code');
  });
}
