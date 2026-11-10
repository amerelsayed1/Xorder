import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/printer_config.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/receipt_profile.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/receipt/receipt_data.dart';
import 'package:shared_module/features/receipt/receipt_document.dart';
import 'package:shared_module/features/receipt/receipt_paper.dart';
import 'package:shared_module/features/receipt/receipt_raster.dart';
import 'package:shared_module/features/receipt/slip_style.dart';

import 'package:xorder_pos_test_support/fonts.dart';

/// The receipt's design rules (receipt-design-system, 26 Oct 2026).
///
/// Presentation only: what is asserted here is where things go and that nothing
/// is cut. What the slip SAYS — every figure, label and total — is asserted by
/// `receipt_document_test`, `receipt_amounts_test` and the money tests, which
/// this redesign did not touch.
void main() {
  setUpAll(loadPosFonts);

  ReceiptData sale(
    List<ReceiptLine> lines, {
    Money? total,
    List<ReceiptPayment> payments = const [],
  }) {
    final subtotal = lines.fold(Money.zero, (sum, l) => sum + l.lineTotal);
    return ReceiptData(
      invoiceNumber: 'MAIN-2026-000004',
      orderType: OrderType.dineIn,
      tableLabel: 'A1',
      occurredAt: DateTime(2026, 10, 26, 7, 16),
      lines: lines,
      subtotal: subtotal,
      discount: Money.zero,
      service: Money.zero,
      vat: Money.zero,
      total: total ?? subtotal,
      paid: total ?? subtotal,
      change: Money.zero,
      payments: payments,
    );
  }

  ReceiptDocument slip(
    ReceiptData data, {
    AppStrings strings = const EnStrings(),
    String? footerNote,
    ReceiptSyncNote? note,
  }) => ReceiptDocument.of(
    data,
    strings: strings,
    profile: ReceiptProfile(
      branchId: 1,
      tradeName: 'Cafe Aziz',
      phone: '01016943505',
      footerNote: footerNote,
    ),
    tenantName: 'Cafe Aziz',
    terminalCode: 'T1',
    cashierName: 'Amer',
  );

  const lines = [
    ReceiptLine(name: 'Mixed grill', quantity: 2, lineTotal: Money(60000)),
    ReceiptLine(name: 'Water', quantity: 1, lineTotal: Money(1500)),
  ];

  group('the structure', () {
    test('three rules, in order: after the branding, before the money, above '
        'the total', () {
      final document = slip(sale(lines));
      final rules = document.blocks.whereType<SlipRule>().toList();

      expect(rules.map((r) => r.weight), [
        SlipRuleWeight.solid,
        SlipRuleWeight.dashed,
        SlipRuleWeight.heavy,
      ]);

      // The heavy one sits directly above the grand total.
      final heavy = document.blocks.indexWhere(
        (b) => b is SlipRule && b.weight == SlipRuleWeight.heavy,
      );
      expect(document.blocks[heavy + 1], isA<SlipGrandTotal>());
    });

    test('sections come in the order of the design', () {
      final document = slip(
        sale(
          lines,
          payments: const [ReceiptPayment(label: 'Cash', amount: Money(61500))],
        ),
        footerNote: 'Free wifi',
      );
      int at(bool Function(SlipBlock) test) => document.blocks.indexWhere(test);

      final order = [
        at((b) => b is SlipCentre && b.emphasis == SlipEmphasis.title),
        at((b) => b is SlipRow && b.secondary),
        at((b) => b is SlipItemsHeader),
        at((b) => b is SlipItem),
        at((b) => b is SlipRow && b.amount),
        at((b) => b is SlipGrandTotal),
        at(
          (b) =>
              b is SlipRow && b.label == const EnStrings().receiptPaymentMethod,
        ),
        at((b) => b is SlipCentre && b.text == 'Free wifi'),
        at((b) => b is SlipCentre && b.text == 'xorder.io'),
      ];
      expect(order.every((i) => i >= 0), isTrue, reason: '$order');
      expect([...order]..sort(), order);
    });

    test('the facts about the sale have a quiet label; the money does not', () {
      final rows = slip(sale(lines)).blocks.whereType<SlipRow>();
      final facts = {
        const EnStrings().receiptDate,
        const EnStrings().receiptTime,
        const EnStrings().receiptOrderNumber,
        const EnStrings().receiptCashier,
        const EnStrings().receiptTerminal,
        const EnStrings().receiptOrderType,
      };
      for (final row in rows) {
        expect(
          row.secondary,
          facts.contains(row.label),
          reason: '"${row.label}"',
        );
      }
    });

    test('the gaps are the scale the tokens name', () {
      expect(const SlipGap.medium().dots, SlipMetrics.spaceMd);
      expect(const SlipGap.section().dots, SlipMetrics.spaceSection);
    });
  });

  group('the footer', () {
    List<String> footer(ReceiptDocument document) {
      final from = document.blocks.indexWhere(
        (b) => b is SlipCentre && b.emphasis == SlipEmphasis.strong,
      );
      return [
        for (final b in document.blocks.skip(from))
          if (b is SlipCentre) b.text,
      ];
    }

    test('thanks once, then xorder.io — no second invitation, no ornament', () {
      for (final strings in const <AppStrings>[EnStrings(), ArStrings()]) {
        final words = footer(slip(sale(lines), strings: strings));
        expect(words, [strings.receiptThanks, 'xorder.io']);
        expect(
          slip(
            sale(lines),
            strings: strings,
          ).blocks.whereType<SlipCentre>().map((b) => b.text),
          isNot(contains(strings.receiptLookForward)),
        );
      }
    });

    test("the business's own text is still printed, above the thanks", () {
      final document = slip(sale(lines), footerNote: 'Free wifi: cafe-guest');
      final texts = [
        for (final b in document.blocks)
          if (b is SlipCentre) b.text,
      ];
      expect(
        texts.indexOf('Free wifi: cafe-guest'),
        lessThan(texts.indexOf(const EnStrings().receiptThanks)),
      );
    });

    test('an empty footer note adds nothing', () {
      final with0 = slip(sale(lines), footerNote: '   ');
      final without = slip(sale(lines));
      expect(with0.blocks.length, without.blocks.length);
    });
  });

  group('item names are never cut', () {
    const medium =
        'Grilled chicken sandwich with garlic sauce and crispy fries';
    const long =
        'Extra large grilled chicken sandwich with garlic sauce, cheddar, '
        'crispy fries, coleslaw salad and a fresh orange juice, large size';
    const arabic =
        'ساندويتش دجاج مشوي بصوص الثوم والجبنة الشيدر مع بطاطس مقرمشة وسلطة '
        'كولسلو وعصير برتقال طازج حجم كبير جدا';

    Future<int> height(String name, int width, {AppStrings? strings}) async {
      final data = sale([
        ReceiptLine(name: name, quantity: 1, lineTotal: const Money(13500)),
      ]);
      final bitmap = await ReceiptRaster.render(
        slip(data, strings: strings ?? const EnStrings()),
        widthDots: width,
      );
      return bitmap.height;
    }

    for (final width in [PrinterConfig.width58mm, PrinterConfig.width80mm]) {
      test('on the paper at $width dots, a longer name is a taller slip, '
          'with no stop at two lines', () async {
        final one = await height('Water', width);
        final two = await height(medium, width);
        final many = await height(long, width);

        expect(two, greaterThan(one));
        // Before: both clamped at two lines and these two were the same height.
        expect(many, greaterThan(two));
      });

      test('Arabic too, at $width dots', () async {
        final two = await height(
          'ساندويتش دجاج مشوي بصوص الثوم والجبنة',
          width,
          strings: const ArStrings(),
        );
        final many = await height(arabic, width, strings: const ArStrings());
        expect(many, greaterThan(two));
      });
    }

    for (final width in [328.0, 220.0]) {
      testWidgets('in the preview at ${width.round()} px: the whole name, '
          'no ellipsis, no overlap', (tester) async {
        tester.view
          ..physicalSize = const Size(600, 4000)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildPosTheme(PosPalette.light),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: width,
                  child: ReceiptPaper(
                    data: sale([
                      const ReceiptLine(
                        name: long,
                        quantity: 12,
                        lineTotal: Money(1234567),
                      ),
                    ]),
                    tenantName: 'Cafe Aziz',
                    terminalCode: 'T1',
                    cashierName: 'Amer',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final name = find.text(long);
        expect(name, findsOneWidget);
        final text = tester.widget<Text>(name);
        expect(text.maxLines, isNull, reason: 'no line limit');
        expect(text.overflow, isNot(TextOverflow.ellipsis));

        final nameBox = tester.getRect(name);
        final quantity = tester.getRect(find.text('12'));
        final price = tester.getRect(find.textContaining('12,345.67').first);
        expect(nameBox.overlaps(quantity), isFalse);
        expect(nameBox.overlaps(price), isFalse);
        expect(quantity.overlaps(price), isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('nothing runs into the margins', () {
    // The head's outermost columns drift, so nothing may be printed in the
    // margin either side. A figure or a name that overflowed would show here.
    Future<void> expectMarginsBlank(ReceiptDocument document, int width) async {
      final image = await ReceiptRaster.paint(document, widthDots: width);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width;
      final h = image.height;
      var inked = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final inMargin =
              x < SlipMetrics.margin - 1 || x >= w - SlipMetrics.margin + 1;
          if (!inMargin) continue;
          final o = (y * w + x) * 4;
          final luma =
              (data!.getUint8(o) * 299 +
                  data.getUint8(o + 1) * 587 +
                  data.getUint8(o + 2) * 114) ~/
              1000;
          if (luma < 128) inked++;
        }
      }
      image.dispose();
      expect(inked, 0, reason: 'ink in the margin at $width dots');
    }

    for (final width in [PrinterConfig.width58mm, PrinterConfig.width80mm]) {
      test(
        'a six-figure total, a long name and a split bill at $width dots',
        () async {
          final data = sale(
            const [
              ReceiptLine(
                name:
                    'Extra large grilled chicken sandwich with garlic sauce, '
                    'cheddar and crispy fries',
                quantity: 12,
                lineTotal: Money(99999999),
              ),
            ],
            payments: const [
              ReceiptPayment(label: 'Cash', amount: Money(50000000)),
              ReceiptPayment(label: 'Card', amount: Money(49999999)),
            ],
          );
          await expectMarginsBlank(slip(data), width);
          await expectMarginsBlank(
            slip(data, strings: const ArStrings()),
            width,
          );
        },
      );
    }
  });

  group('the grand total', () {
    test('is smaller than before and still the largest text on the slip', () {
      expect(SlipMetrics.totalAmountSize, 44);
      expect(SlipMetrics.totalAmountSize, greaterThan(SlipMetrics.titleSize));
      expect(
        SlipMetrics.totalAmountSize,
        greaterThan(SlipMetrics.totalLabelSize),
      );
      expect(
        SlipMetrics.totalAmountSize,
        greaterThanOrEqualTo(2 * SlipMetrics.bodySize),
      );
    });
  });
}
