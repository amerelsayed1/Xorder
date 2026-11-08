import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/printer_config.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/receipt/receipt_data.dart';
import 'package:shared_module/features/receipt/receipt_document.dart';
import 'package:shared_module/features/receipt/receipt_paper.dart';
import 'package:shared_module/features/receipt/receipt_raster.dart';
import 'package:shared_module/features/receipt/slip_style.dart';

/// XORD-025 and XORD-026: the amounts on a slip end at one edge, so their
/// decimal points stand in one line, in Arabic as in English; and the currency
/// code under the total ends where the figure ends.
///
/// Measured on the bitmap the printer is sent and on the preview widget — not
/// on the document, which says nothing about where anything is drawn.
void main() {
  bool inked(ReceiptBitmap bitmap, int x, int y) =>
      (bitmap.bits[y * bitmap.rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1 == 1;

  /// Rows of ink that touch, as (first, last), looking only at columns
  /// [fromX, toX).
  List<(int, int)> runs(ReceiptBitmap bitmap, {int fromX = 0, int? toX}) {
    final end = toX ?? bitmap.width;
    final result = <(int, int)>[];
    int? start;
    for (var y = 0; y < bitmap.height; y++) {
      var any = false;
      for (var x = fromX; x < end && !any; x++) {
        any = inked(bitmap, x, y);
      }
      if (any && start == null) start = y;
      if (!any && start != null) {
        result.add((start, y - 1));
        start = null;
      }
    }
    if (start != null) result.add((start, bitmap.height - 1));
    return result;
  }

  int rightEdge(
    ReceiptBitmap bitmap,
    int top,
    int bottom, {
    int fromX = 0,
    int? toX,
  }) {
    final end = toX ?? bitmap.width;
    var edge = -1;
    for (var y = top; y <= bottom; y++) {
      for (var x = end - 1; x >= fromX && x > edge; x--) {
        if (inked(bitmap, x, y)) {
          edge = x;
          break;
        }
      }
    }
    return edge;
  }

  int leftEdge(ReceiptBitmap bitmap, int top, int bottom) {
    var edge = bitmap.width;
    for (var y = top; y <= bottom; y++) {
      for (var x = 0; x < edge; x++) {
        if (inked(bitmap, x, y)) {
          edge = x;
          break;
        }
      }
    }
    return edge;
  }

  group('amount rows on the printed slip', () {
    ReceiptDocument stack({required bool rtl}) => ReceiptDocument(
      rightToLeft: rtl,
      blocks: const [
        SlipRow('', '1,050.00 EGP', amount: true),
        SlipGap(24),
        SlipRow('', '450.00 EGP', amount: true),
        SlipGap(24),
        SlipRow('', '63.00 EGP', amount: true),
      ],
    );

    for (final rtl in [true, false]) {
      for (final width in [PrinterConfig.width80mm, PrinterConfig.width58mm]) {
        test(
          'end at the same dot in ${rtl ? 'Arabic' : 'English'} at $width dots',
          () async {
            final bitmap = await ReceiptRaster.render(
              stack(rtl: rtl),
              widthDots: width,
            );
            final lines = runs(bitmap);
            expect(lines, hasLength(3), reason: 'three separate figures');

            final edges = [
              for (final (top, bottom) in lines) rightEdge(bitmap, top, bottom),
            ];
            expect(edges.toSet(), hasLength(1), reason: 'right edges $edges');
          },
        );
      }
    }

    test('an Arabic slip keeps its amounts on the left, an English one on the right', () async {
      final arabic = await ReceiptRaster.render(stack(rtl: true));
      final english = await ReceiptRaster.render(stack(rtl: false));

      final (aTop, aBottom) = runs(arabic).first;
      final (eTop, eBottom) = runs(english).first;
      expect(leftEdge(arabic, aTop, aBottom), lessThan(arabic.width ~/ 4));
      expect(
        rightEdge(english, eTop, eBottom),
        greaterThan(english.width * 3 ~/ 4),
      );
    });

    test('and a row that is not an amount is left where it was', () async {
      // A date is mono and numeric but not money: it keeps pinning to the edge
      // at its own width rather than joining the amounts' box.
      final bitmap = await ReceiptRaster.render(
        const ReceiptDocument(
          rightToLeft: true,
          blocks: [
            SlipRow('', '26/10/2026'),
            SlipGap(24),
            SlipRow('', '1,050.00 EGP', amount: true),
          ],
        ),
      );
      final lines = runs(bitmap);
      expect(lines, hasLength(2));
      // The date starts at the left margin like the amount's box does; it is
      // the shorter text, so it ends earlier. They must NOT be forced equal.
      final dateEdge = rightEdge(bitmap, lines[0].$1, lines[0].$2);
      final amountEdge = rightEdge(bitmap, lines[1].$1, lines[1].$2);
      expect(dateEdge, lessThan(amountEdge));
    });
  });

  group('the items column', () {
    for (final rtl in [true, false]) {
      test('ends at one dot in ${rtl ? 'Arabic' : 'English'}', () async {
        final bitmap = await ReceiptRaster.render(
          ReceiptDocument(
            rightToLeft: rtl,
            blocks: const [
              // Short enough for the test font, whose every glyph is a full
              // em wide: longer figures overflow the column and are cut at
              // its width, which would make any alignment look equal.
              SlipItem('', '1', '100 EGP'),
              SlipGap(24),
              SlipItem('', '1', '10 EGP'),
              SlipGap(24),
              SlipItem('', '1', '1 EGP'),
            ],
          ),
        );
        // Only the price column: the quantity beside it is a figure of its own
        // and ends at one dot whatever the price does.
        final column = (SlipMetrics.margin + SlipMetrics.priceColumn).toInt();
        final priceFrom = rtl ? 0 : bitmap.width - column;
        final priceTo = rtl ? column : bitmap.width;
        final edges = [
          for (final (top, bottom) in runs(
            bitmap,
            fromX: priceFrom,
            toX: priceTo,
          ))
            rightEdge(bitmap, top, bottom, fromX: priceFrom, toX: priceTo),
        ];
        expect(edges, hasLength(3));
        expect(edges.toSet(), hasLength(1), reason: 'right edges $edges');
      });
    }
  });

  group('the currency under the total', () {
    for (final rtl in [true, false]) {
      test(
        'ends where the figure ends in ${rtl ? 'Arabic' : 'English'}',
        () async {
          final bitmap = await ReceiptRaster.render(
            ReceiptDocument(
              rightToLeft: rtl,
              blocks: const [SlipGrandTotal('TOTAL', '513.00', 'EGP')],
            ),
          );
          // The figure's own side of the slip: the label is on the other.
          final fromX = rtl ? 0 : bitmap.width ~/ 2 - 40;
          final toX = rtl ? bitmap.width ~/ 2 + 40 : bitmap.width;
          final figure = runs(bitmap, fromX: fromX, toX: toX).single;
          final height = figure.$2 - figure.$1;

          final amountEdge = rightEdge(
            bitmap,
            figure.$1,
            figure.$1 + 6,
            fromX: fromX,
            toX: toX,
          );
          final currencyEdge = rightEdge(
            bitmap,
            figure.$2 - 6,
            figure.$2,
            fromX: fromX,
            toX: toX,
          );
          expect(
            height,
            greaterThan(40),
            reason: 'a figure with a code under it',
          );
          expect(
            (amountEdge - currencyEdge).abs(),
            lessThanOrEqualTo(2),
            reason: 'amount ends at $amountEdge, code at $currencyEdge',
          );
        },
      );
    }
  });

  group('a price wider than the column', () {
    for (final rtl in [true, false]) {
      test(
        'is printed whole, not cut to an ellipsis, in ${rtl ? 'Arabic' : 'English'}',
        () async {
          // 9 glyphs of the test font are 198 dots: past the 190-dot column the
          // slip starts with, inside what it may grow to.
          final bitmap = await ReceiptRaster.render(
            ReceiptDocument(
              rightToLeft: rtl,
              blocks: const [SlipItem('', '1', '1,000 EGP')],
            ),
          );
          final column = (SlipMetrics.margin + 198).toInt() + 2;
          final from = rtl ? 0 : bitmap.width - column;
          final to = rtl ? column : bitmap.width;

          var left = bitmap.width;
          var right = -1;
          for (var y = 0; y < bitmap.height; y++) {
            for (var x = from; x < to; x++) {
              if (!inked(bitmap, x, y)) continue;
              if (x < left) left = x;
              if (x > right) right = x;
            }
          }
          expect(right - left + 1, greaterThanOrEqualTo(196));
        },
      );
    }
  });

  group('nothing is cut off', () {
    for (final width in [PrinterConfig.width80mm, PrinterConfig.width58mm]) {
      test(
        'a long Arabic dish and a seven-digit total fit at $width dots',
        () async {
          final document = ReceiptDocument(
            rightToLeft: true,
            blocks: const [
              SlipItem(
                'سلطة سيزر بالدجاج المشوي مع صوص خاص وجبنة بارميزان ومكسرات',
                '12',
                '9,999,999.99 EGP',
              ),
              SlipRow('المجموع الفرعي', '9,999,999.99 EGP', amount: true),
              SlipGrandTotal('الإجمالي', '9,999,999.99', 'EGP'),
            ],
          );
          final bitmap = await ReceiptRaster.render(document, widthDots: width);

          var minX = bitmap.width;
          var maxX = -1;
          for (var y = 0; y < bitmap.height; y++) {
            for (var x = 0; x < bitmap.width; x++) {
              if (!inked(bitmap, x, y)) continue;
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
            }
          }
          expect(minX, greaterThanOrEqualTo(SlipMetrics.margin.floor() - 1));
          expect(
            maxX,
            lessThanOrEqualTo(bitmap.width - SlipMetrics.margin.floor()),
          );
        },
      );
    }
  });

  group('the preview', () {
    ReceiptData sale() => ReceiptData(
      invoiceNumber: 'HST-000481',
      orderType: OrderType.takeaway,
      occurredAt: DateTime(2026, 10, 26, 2, 14),
      lines: const [
        ReceiptLine(name: 'Grill', quantity: 1, lineTotal: Money(10000)),
        ReceiptLine(name: 'Tea', quantity: 1, lineTotal: Money(1500)),
      ],
      subtotal: const Money(11500),
      discount: Money.zero,
      service: Money.zero,
      vat: const Money(1610),
      total: const Money(13110),
      paid: const Money(13110),
      change: Money.zero,
      taxLines: const [ReceiptTaxLine(rateBp: 1400, amount: Money(1610))],
    );

    Future<void> pump(
      WidgetTester tester,
      Locale locale, {
      Uint8List? logo,
      ReceiptData? data,
    }) async {
      tester.view
        ..physicalSize = const Size(600, 2400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
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
                width: 328,
                child: ReceiptPaper(
                  data: data ?? sale(),
                  tenantName: 'Cafe',
                  terminalCode: 'T1',
                  cashierName: 'Amer',
                  logo: logo,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Where the last glyph of [text] ends, on screen: the paragraph's own box
    /// says nothing about where its text sits inside.
    double textEnd(WidgetTester tester, String text) {
      final finder = find.text(text);
      expect(finder, findsOneWidget, reason: text);
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      final origin = paragraph.localToGlobal(Offset.zero);
      return origin.dx +
          boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b);
    }

    for (final locale in [const Locale('ar'), const Locale('en')]) {
      testWidgets('amounts end together, in ${locale.languageCode}', (
        tester,
      ) async {
        await pump(tester, locale);

        final ends = [
          textEnd(tester, '115.00 EGP'),
          textEnd(tester, '16.10 EGP'),
        ];
        expect(
          (ends[0] - ends[1]).abs(),
          lessThan(1),
          reason: 'subtotal ends at ${ends[0]}, VAT at ${ends[1]}',
        );

        // The items column too: a four-digit price over a three-digit one.
        final prices = [
          textEnd(tester, '100.00 EGP'),
          textEnd(tester, '15.00 EGP'),
        ];
        expect((prices[0] - prices[1]).abs(), lessThan(1));
      });

      testWidgets('the code ends under the figure, in ${locale.languageCode}', (
        tester,
      ) async {
        await pump(tester, locale);

        expect(
          (textEnd(tester, '131.10') - textEnd(tester, 'EGP')).abs(),
          lessThan(1),
        );
      });
    }

    testWidgets('a logo that will not decode leaves no error on the slip', (
      tester,
    ) async {
      await pump(
        tester,
        const Locale('en'),
        logo: Uint8List.fromList([1, 2, 3]),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // The rest of the slip is all there.
      expect(find.text('115.00 EGP'), findsOneWidget);
    });

    testWidgets('a logo is drawn above the business name, in a box', (
      tester,
    ) async {
      await pump(
        tester,
        const Locale('en'),
        logo: Uint8List.fromList([1, 2, 3]),
      );

      final logoBox = tester.getRect(find.byKey(const Key('receipt-logo')));
      final name = tester.getRect(find.text('CAFE'));
      expect(logoBox.bottom, lessThanOrEqualTo(name.top + 1));
    });

    testWidgets('a price wider than the column is shown whole', (tester) async {
      await pump(
        tester,
        const Locale('en'),
        data: ReceiptData(
          invoiceNumber: 'HST-1',
          orderType: OrderType.takeaway,
          occurredAt: DateTime(2026, 10, 26, 2, 14),
          lines: const [
            ReceiptLine(name: 'Tea', quantity: 1, lineTotal: Money(10000)),
          ],
          subtotal: const Money(10000),
          discount: Money.zero,
          service: Money.zero,
          vat: Money.zero,
          total: const Money(10000),
          paid: const Money(10000),
          change: Money.zero,
        ),
      );

      final price = tester.renderObject<RenderParagraph>(
        find.text('100.00 EGP').first,
      );
      expect(price.didExceedMaxLines, isFalse);
    });

    testWidgets('a real logo is above the name and as small as it prints', (
      tester,
    ) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 64, 64),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      final png = (await tester.runAsync(() async {
        final image = await recorder.endRecording().toImage(64, 64);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;

      await pump(tester, const Locale('en'), logo: png);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      final logoBox = tester.getRect(find.byKey(const Key('receipt-logo')));
      final name = tester.getRect(find.text('CAFE'));
      expect(logoBox.bottom, lessThanOrEqualTo(name.top + 1));
      // 64 dots on a slip drawn 328 wide for 640: 64 x 0.5125 = 32.8 pixels.
      expect(logoBox.width, closeTo(64 * 328 / 640, 1.5));
      expect(logoBox.height, closeTo(64 * 328 / 640, 1.5));
    });
  });
}
