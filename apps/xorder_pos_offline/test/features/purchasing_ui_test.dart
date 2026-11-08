import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';
import 'package:xorder_pos/domain/models/supplier.dart';
import 'package:xorder_pos/domain/models/pos_unit.dart';
import 'package:xorder_pos/domain/models/stock_item.dart';
import 'package:xorder_pos_offline/features/admin/presentation/purchase_order_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/receive_dialog.dart';
import 'package:xorder_pos_offline/features/admin/presentation/supplier_dialog.dart';

/// Buying, on screen (§36–37).
///
/// Three claims are worth a test because getting any of them wrong makes the
/// screen quietly lie: the order total has to move as lines are typed, a
/// half-typed line must not count as an order, and every receiving box has to
/// start at what is still owed rather than at zero.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  const suppliers = [
    Supplier(id: 7, nameEn: 'Nile Dairy', code: 'ND'),
    Supplier(id: 8, nameEn: 'Cairo Meats', code: 'CM'),
  ];

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open, {
    String locale = 'en',
  }) async {
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
                onPressed: () => open(context),
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

  group('the supplier dialog', () {
    testWidgets('one field is required and the rest say they are not', (
      tester,
    ) async {
      // A delivery arrives at seven in the morning. Demanding a tax number is
      // how the delivery goes unrecorded.
      Supplier? saved;
      await host(
        tester,
        (context) async => saved = await SupplierDialog.show(context),
      );

      expect(find.text('NAME'), findsOneWidget);
      expect(find.textContaining('OPTIONAL'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('supplier-name')),
        'Nile Dairy',
      );
      await tester.tap(find.byKey(const Key('supplier-save')));
      await tester.pumpAndSettle();

      expect(saved?.nameEn, 'Nile Dairy');
      expect(saved?.paymentTermDays, 0, reason: 'blank terms mean on delivery');
      expect(saved?.isActive, isTrue);
    });

    testWidgets('a nameless supplier is refused beside the field', (
      tester,
    ) async {
      Supplier? saved;
      var closed = false;
      await host(tester, (context) async {
        saved = await SupplierDialog.show(context);
        closed = true;
      });

      await tester.tap(find.byKey(const Key('supplier-save')));
      await tester.pumpAndSettle();

      expect(closed, isFalse, reason: 'the dialog stays open');
      expect(saved, isNull);
      expect(find.byType(SupplierDialog), findsOneWidget);
    });

    testWidgets('every field is a box you can see, and the terms hint sits '
        'under its box rather than in it', (tester) async {
      // Nine of the ten boxes on this form had no border and no fill: a
      // `null` decoration is not the theme's default, it is no decoration at
      // all. The one field with a hint was the only one that looked like a
      // field — and its hint, sitting in the box in full ink, read as typed.
      await host(tester, (context) async => SupplierDialog.show(context));

      // Each one scrolled to first: the form is longer than the dialog, and a
      // list does not build what is below the fold.
      final list = find
          .descendant(
            of: find.byType(SupplierDialog),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final name in const [
        'name', 'name_ar', 'contact', 'phone', 'email', //
        'address', 'tax', 'terms', 'code', 'notes',
      ]) {
        final box = find.byKey(Key('supplier-$name'));
        await tester.scrollUntilVisible(box, 80, scrollable: list);
        final decorator = tester.widget<InputDecorator>(
          find.descendant(of: box, matching: find.byType(InputDecorator)),
        );
        expect(
          decorator.decoration.enabledBorder,
          isA<OutlineInputBorder>().having(
            (b) => b.borderSide.style,
            'side',
            BorderStyle.solid,
          ),
          reason: 'supplier-$name must draw the theme\'s border',
        );
        expect(decorator.decoration.filled, isTrue, reason: name);
        expect(decorator.decoration.hintText, isNull, reason: name);
      }

      expect(find.text(const EnStrings().supplierTermsHint), findsOneWidget);
    });

    testWidgets('a new supplier is not asked whether it is retired', (
      tester,
    ) async {
      // There is nothing to retire on a supplier nobody has saved yet, and an
      // "in use" switch on a blank form is a question about nothing.
      await host(tester, (context) async => SupplierDialog.show(context));
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('an existing one can be retired', (tester) async {
      await host(
        tester,
        (context) async =>
            SupplierDialog.show(context, supplier: suppliers.first),
      );
      await tester.scrollUntilVisible(
        find.byType(SwitchListTile),
        80,
        scrollable: find
            .descendant(
              of: find.byType(SupplierDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byType(SwitchListTile), findsOneWidget);
    });
  });

  group('the order dialog', () {
    const chicken = StockItem(
      id: 101,
      nameEn: 'Chicken',
      unit: QuantityUnit.kilogram,
    );
    const units = [
      PosUnit(id: 1, code: 'ea', nameEn: 'Each'),
      PosUnit(id: 2, code: 'kg', nameEn: 'Kilogram', allowsFraction: true),
      PosUnit(id: 3, code: 'box', nameEn: 'Box'),
    ];

    testWidgets('picking an item names the line, counts it in its unit, and '
        'links it', (tester) async {
      // Linked, so the delivery raises the chicken's stock — not a line that
      // happens to say "Chicken" and stocks nothing.
      PurchaseOrder? saved;
      await host(
        tester,
        (context) async => saved = await PurchaseOrderDialog.show(
          context,
          suppliers: suppliers,
          items: const [chicken],
          units: units,
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'chi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chicken').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '12.5');
      await tester.enterText(find.byType(TextField).at(2), '95.00');
      await tester.tap(find.byKey(const Key('purchase-save')));
      await tester.pumpAndSettle();

      final line = saved!.lines.single;
      expect(line.productId, 101);
      expect(line.description, 'Chicken');
      expect(line.ordered.unit, QuantityUnit.kilogram);
      expect(line.ordered.milli, 12500);
    });

    testWidgets('a name not in the list is added as a new item, from the line',
        (tester) async {
      PurchaseOrder? saved;
      String? asked;
      await host(
        tester,
        (context) async => saved = await PurchaseOrderDialog.show(
          context,
          suppliers: suppliers,
          items: const [chicken],
          units: units,
          onCreateItem: (name) async {
            asked = name;
            return StockItem(id: 555, nameEn: name, unit: QuantityUnit.box);
          },
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Gas cylinder');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add “Gas cylinder” as a new item'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '3');
      await tester.enterText(find.byType(TextField).at(2), '400.00');
      await tester.tap(find.byKey(const Key('purchase-save')));
      await tester.pumpAndSettle();

      expect(asked, 'Gas cylinder');
      expect(saved!.lines.single.productId, 555);
      expect(saved!.lines.single.ordered.unit, QuantityUnit.box);
    });

    testWidgets('typing over a picked item makes it a free line again', (
      tester,
    ) async {
      // A line that says "Chicken wings" and stocks the chicken is worse than
      // a line that stocks nothing.
      PurchaseOrder? saved;
      await host(
        tester,
        (context) async => saved = await PurchaseOrderDialog.show(
          context,
          suppliers: suppliers,
          items: const [chicken],
          units: units,
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'chi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chicken').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Chicken wings');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.enterText(find.byType(TextField).at(2), '50.00');
      await tester.tap(find.byKey(const Key('purchase-save')));
      await tester.pumpAndSettle();

      expect(saved!.lines.single.productId, isNull);
    });

    testWidgets('a line that names an item is fixed to its unit', (
      tester,
    ) async {
      // Receiving writes the line's unit onto the item's stock: boxes against
      // an item counted in kilograms would add boxes to kilograms.
      await host(
        tester,
        (context) async => PurchaseOrderDialog.show(
          context,
          suppliers: suppliers,
          items: const [chicken],
          units: units,
        ),
      );
      expect(find.byType(PopupMenuButton<QuantityUnit>), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'chi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chicken').last);
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<QuantityUnit>), findsNothing);
      expect(find.text('Kilogram'), findsOneWidget);
    });

    testWidgets('the total moves as the lines are typed', (tester) async {
      // The number a buyer is deciding about is what the whole order costs. A
      // figure that only appeared after saving would make them save to find out.
      await host(
        tester,
        (context) async =>
            PurchaseOrderDialog.show(context, suppliers: suppliers),
      );

      expect(find.text('120.00 EGP'), findsNothing);

      await tester.enterText(find.byType(TextField).at(0), 'Milk 1L');
      await tester.enterText(find.byType(TextField).at(1), '12');
      await tester.enterText(find.byType(TextField).at(2), '10.00');
      await tester.pumpAndSettle();

      expect(
        find.text('120.00 EGP'),
        findsWidgets,
        reason: '12 × 10.00, shown before anybody saves',
      );
    });

    testWidgets('a half-typed line is not an error and not an order', (
      tester,
    ) async {
      PurchaseOrder? saved;
      await host(
        tester,
        (context) async => saved = await PurchaseOrderDialog.show(
          context,
          suppliers: suppliers,
        ),
      );

      // A name and nothing else: the normal state of a form mid-typing.
      await tester.enterText(find.byType(TextField).at(0), 'Milk 1L');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('needs a name'),
        findsNothing,
        reason: 'not complained about while it is being typed',
      );

      await tester.tap(find.byKey(const Key('purchase-save')));
      await tester.pumpAndSettle();

      expect(saved, isNull, reason: 'and not saved either');
      expect(find.textContaining('Nothing to order'), findsOneWidget);
    });

    testWidgets('the order carries the supplier that was picked', (
      tester,
    ) async {
      PurchaseOrder? saved;
      await host(
        tester,
        (context) async => saved = await PurchaseOrderDialog.show(
          context,
          suppliers: suppliers,
        ),
      );

      await tester.tap(find.text('Cairo Meats'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Beef mince');
      await tester.enterText(find.byType(TextField).at(1), '5');
      await tester.enterText(find.byType(TextField).at(2), '240.00');
      await tester.tap(find.byKey(const Key('purchase-save')));
      await tester.pumpAndSettle();

      expect(saved?.supplierId, 8);
      expect(saved?.supplierName, 'Cairo Meats');
      expect(saved?.lines.single.lineTotal, const Money(120000));
    });

    testWidgets('a second line can be added and the first one removed', (
      tester,
    ) async {
      await host(
        tester,
        (context) async =>
            PurchaseOrderDialog.show(context, suppliers: suppliers),
      );

      expect(
        find.byIcon(Icons.close),
        findsNothing,
        reason: 'the only line cannot be removed — the form would have none',
      );

      await tester.tap(find.byKey(const Key('purchase-add-line')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });
  });

  group('the receiving dialog', () {
    final order = PurchaseOrder(
      id: 3,
      supplierId: 7,
      supplierName: 'Nile Dairy',
      reference: 'PO-2026-0003',
      status: PurchaseStatus.sent,
      lines: [
        PurchaseOrderLine(
          id: 11,
          description: 'Milk 1L',
          ordered: Quantity.of(10, unit: QuantityUnit.each),
          unitCost: const Money(1000),
        ),
        PurchaseOrderLine(
          id: 12,
          description: 'Butter',
          ordered: Quantity.of(4, unit: QuantityUnit.kilogram),
          received: Quantity.of(1, unit: QuantityUnit.kilogram),
          unitCost: const Money(18000),
        ),
      ],
    );

    testWidgets('every box starts at what is still owed', (tester) async {
      // The common case is that the delivery matches the order. A form that
      // made somebody retype eight numbers to say "all of it came" is a form
      // they stop using by Thursday.
      await host(
        tester,
        (context) async => ReceiveDialog.show(context, order: order),
      );

      expect(
        tester.widget<TextField>(find.byKey(const Key('receive-11'))).controller?.text,
        '10',
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('receive-12'))).controller?.text,
        '3',
        reason: '4 ordered, 1 already in',
      );
    });

    testWidgets('a short delivery is one number changed', (tester) async {
      Map<int, Quantity>? booked;
      await host(
        tester,
        (context) async =>
            booked = await ReceiveDialog.show(context, order: order),
      );

      await tester.enterText(find.byKey(const Key('receive-11')), '8');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receive-confirm')));
      await tester.pumpAndSettle();

      expect(booked, {
        11: Quantity.of(8, unit: QuantityUnit.each),
        12: Quantity.of(3, unit: QuantityUnit.kilogram),
      });
    });

    testWidgets('a line typed to zero is left off rather than booked at zero', (
      tester,
    ) async {
      // "Nothing arrived of this one" and "zero of this one arrived" are the
      // same sentence, and a zero movement in the stock ledger would be a
      // receipt of nothing that still moved the average cost's denominator.
      Map<int, Quantity>? booked;
      await host(
        tester,
        (context) async =>
            booked = await ReceiveDialog.show(context, order: order),
      );

      await tester.enterText(find.byKey(const Key('receive-11')), '0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receive-confirm')));
      await tester.pumpAndSettle();

      expect(booked?.keys, [12]);
    });

    testWidgets('nothing at all cannot be booked in', (tester) async {
      Map<int, Quantity>? booked;
      var closed = false;
      await host(tester, (context) async {
        booked = await ReceiveDialog.show(context, order: order);
        closed = true;
      });

      await tester.enterText(find.byKey(const Key('receive-11')), '');
      await tester.enterText(find.byKey(const Key('receive-12')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receive-confirm')));
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(booked, isNull);
    });
  });

  testWidgets('the Arabic order dialog keeps its numbers in Latin digits', (
    tester,
  ) async {
    // A unit cost is a figure somebody checks against a printed invoice, and
    // the invoice is in Latin digits whatever the screen is in.
    await host(
      tester,
      (context) async =>
          PurchaseOrderDialog.show(context, suppliers: suppliers),
      locale: 'ar',
    );

    expect(find.text('أمر جديد'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'لبن');
    await tester.enterText(find.byType(TextField).at(1), '3');
    await tester.enterText(find.byType(TextField).at(2), '15.50');
    await tester.pumpAndSettle();

    expect(find.text('46.50 EGP'), findsWidgets);
  });
}
