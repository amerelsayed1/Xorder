import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/printer_config.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/receipt/receipt_data.dart';
import 'package:xorder_pos/features/receipt/receipt_document.dart';
import 'package:xorder_pos/features/receipt/receipt_raster.dart';

import '../support/fonts.dart';

/// Writes pictures of the receipt, for LOOKING at. Asserts nothing.
///
/// Skipped unless `RECEIPT_PREVIEW_DIR` is set, so the suite stays what it was:
///
///     RECEIPT_PREVIEW_DIR=docs/features/receipt-design-system/previews/before \
///       flutter test test/tool/receipt_previews_test.dart
///
/// Each picture is the one-bit bitmap the printer would be sent, drawn with
/// the bundled faces — dots, not a sketch — so what is seen is what a head
/// receives. It is not a photograph of paper: a real roll, its margins and its
/// thermal contrast still need a person.
///
/// There are deliberately no golden files (owner, 2026-10-26): they would fail
/// on every pixel and need the same fonts on every machine. The structure of
/// the slip is asserted on the block list in `receipt_document_test.dart`.
void main() {
  final out = Platform.environment['RECEIPT_PREVIEW_DIR'];

  setUpAll(loadPosFonts);

  const logoSide = 240;

  Future<Uint8List> logo() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final ink = ui.Paint()..color = const ui.Color(0xFF222222);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, logoSide.toDouble(), 120),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawCircle(const ui.Offset(70, 60), 44, ink);
    canvas.drawRect(const ui.Rect.fromLTWH(130, 34, 80, 14), ink);
    canvas.drawRect(const ui.Rect.fromLTWH(130, 58, 60, 14), ink);
    canvas.drawRect(const ui.Rect.fromLTWH(130, 82, 80, 14), ink);
    final image = await recorder.endRecording().toImage(logoSide, 120);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  ReceiptData sale(
    List<ReceiptLine> lines, {
    Money? discount,
    int? discountBp,
    Money? service,
    List<ReceiptTaxLine>? taxLines,
    List<ReceiptPayment> payments = const [],
    Money? total,
    Money? paid,
    Money? change,
  }) {
    final subtotal = lines.fold(Money.zero, (sum, l) => sum + l.lineTotal);
    final disc = discount ?? Money.zero;
    final serv = service ?? Money.zero;
    final tax =
        taxLines ?? const [ReceiptTaxLine(rateBp: 1400, amount: Money(0))];
    final vat = tax.fold(Money.zero, (sum, t) => sum + t.amount);
    final grand = total ?? (subtotal - disc + serv + vat);
    return ReceiptData(
      invoiceNumber: 'MAIN-2026-000004',
      orderType: OrderType.dineIn,
      tableLabel: 'A1',
      occurredAt: DateTime(2026, 10, 26, 7, 16),
      lines: lines,
      subtotal: subtotal,
      discount: disc,
      discountBp: discountBp,
      service: serv,
      serviceBp: serv.isZero ? null : 1200,
      vat: vat,
      taxLines: tax,
      total: grand,
      paid: paid ?? grand,
      change: change ?? Money.zero,
      payments: payments.isEmpty
          ? [ReceiptPayment(label: 'Cash', amount: paid ?? grand)]
          : payments,
    );
  }

  const arItems = [
    ReceiptLine(name: 'ستيك مشوي', quantity: 1, lineTotal: Money(15000)),
    ReceiptLine(name: 'لحمه مشويه', quantity: 2, lineTotal: Money(60000)),
  ];
  const enItems = [
    ReceiptLine(name: 'Grilled steak', quantity: 1, lineTotal: Money(15000)),
    ReceiptLine(name: 'Mixed grill', quantity: 2, lineTotal: Money(60000)),
  ];
  const taxes = [ReceiptTaxLine(rateBp: 1400, amount: Money(7056))];

  Future<void> save(
    String name,
    ReceiptDocument document,
    int widthDots,
  ) async {
    final bitmap = await ReceiptRaster.render(document, widthDots: widthDots);
    final pixels = Uint8List(bitmap.width * bitmap.height * 4);
    for (var y = 0; y < bitmap.height; y++) {
      for (var x = 0; x < bitmap.width; x++) {
        final ink =
            bitmap.bits[y * bitmap.rowBytes + (x >> 3)] & (0x80 >> (x & 7)) !=
            0;
        final o = (y * bitmap.width + x) * 4;
        final v = ink ? 0 : 255;
        pixels[o] = v;
        pixels[o + 1] = v;
        pixels[o + 2] = v;
        pixels[o + 3] = 255;
      }
    }
    final image = await _decode(pixels, bitmap.width, bitmap.height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$out/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  }

  ReceiptDocument document(
    ReceiptData data, {
    AppStrings strings = const ArStrings(),
    String tradeName = 'كافيه عزيز',
    String cashier = 'Amer Mahsoub',
    Uint8List? logoBytes,
    ReceiptProfile? profile,
  }) => ReceiptDocument.of(
    data,
    strings: strings,
    profile:
        profile ??
        ReceiptProfile(
          branchId: 1,
          tradeName: tradeName,
          phone: '01016943505',
          address: const BranchAddress(
            street: 'شارع سعد زغلول الممشي الجديد',
            regionCity: 'المنصوره',
          ),
          footerNote: strings.languageCode == 'ar'
              ? 'اتشرفنا يوجوك جدا - تعالى تاني'
              : 'Free wifi: cafe-guest',
        ),
    tenantName: tradeName,
    terminalCode: 'T1',
    cashierName: cashier,
    logo: logoBytes,
  );

  final skip = out == null || out.isEmpty ? 'set RECEIPT_PREVIEW_DIR' : null;

  test('the nine cases of the brief', skip: skip, () async {
    final mark = await logo();
    const w80 = PrinterConfig.width80mm;
    const w58 = PrinterConfig.width58mm;

    final plain = sale(
      arItems,
      taxLines: taxes,
      payments: const [],
      paid: const Money(100000),
      change: const Money(42944),
    );
    final plainEn = sale(
      enItems,
      taxLines: taxes,
      paid: const Money(100000),
      change: const Money(42944),
    );

    await save('1-ar-80', document(plain, logoBytes: mark), w80);
    await save('2-ar-58', document(plain, logoBytes: mark), w58);
    await save(
      '3-en-80',
      document(
        plainEn,
        strings: const EnStrings(),
        tradeName: 'Cafe Aziz',
        logoBytes: mark,
      ),
      w80,
    );
    await save(
      '4-en-58',
      document(
        plainEn,
        strings: const EnStrings(),
        tradeName: 'Cafe Aziz',
        logoBytes: mark,
      ),
      w58,
    );

    // Arabic slip with Latin product names, a Latin cashier and a Latin tender.
    final mixed = sale(
      const [
        ReceiptLine(
          name: 'Cappuccino كبير',
          quantity: 2,
          lineTotal: Money(9000),
        ),
        ReceiptLine(
          name: 'تشيز كيك Blueberry',
          quantity: 1,
          lineTotal: Money(7500),
        ),
        ReceiptLine(
          name: 'Mojito بالنعناع',
          quantity: 1,
          lineTotal: Money(6000),
        ),
      ],
      taxLines: const [ReceiptTaxLine(rateBp: 1400, amount: Money(3150))],
    );
    await save('5-mixed-80', document(mixed, logoBytes: mark), w80);

    final many = sale(
      [
        for (var i = 1; i <= 30; i++)
          ReceiptLine(
            name: i.isEven ? 'صنف رقم $i' : 'Item number $i',
            quantity: 1 + i % 3,
            lineTotal: Money(1250 * i),
          ),
      ],
      taxLines: const [ReceiptTaxLine(rateBp: 1400, amount: Money(81375))],
    );
    await save('6-many-items-ar-80', document(many, logoBytes: mark), w80);

    final longNames = sale(
      const [
        ReceiptLine(
          name: 'ساندويتش دجاج مشوي بصوص الثوم والجبنة الشيدر مع بطاطس مقرمشة وسلطة كولسلو وعصير برتقال طازج حجم كبير جدا',
          quantity: 2,
          lineTotal: Money(24000),
        ),
        ReceiptLine(
          name: 'Extra large grilled chicken sandwich with garlic sauce, cheddar, crispy fries and fresh orange juice',
          quantity: 1,
          lineTotal: Money(13500),
        ),
        ReceiptLine(name: 'Water', quantity: 3, lineTotal: Money(1500)),
      ],
      taxLines: const [ReceiptTaxLine(rateBp: 1400, amount: Money(5460))],
    );
    await save('7-long-names-ar-58', document(longNames, logoBytes: mark), w58);
    await save(
      '7-long-names-en-80',
      document(
        longNames,
        strings: const EnStrings(),
        tradeName: 'Cafe Aziz',
        logoBytes: mark,
      ),
      w80,
    );

    // A discount, a service charge, two tax rates and a split bill.
    final busy = sale(
      const [
        ReceiptLine(name: 'Mixed grill', quantity: 2, lineTotal: Money(90000)),
        ReceiptLine(name: 'Mineral water', quantity: 2, lineTotal: Money(4000)),
        ReceiptLine(
          name: 'Voided dessert',
          quantity: 1,
          lineTotal: Money(8000),
          isVoided: true,
        ),
      ],
      discount: const Money(9400),
      discountBp: 1000,
      service: const Money(10152),
      taxLines: const [
        ReceiptTaxLine(rateBp: 1400, amount: Money(12600)),
        ReceiptTaxLine(rateBp: 0, amount: Money(0)),
      ],
      payments: const [
        ReceiptPayment(label: 'Cash', amount: Money(60000)),
        ReceiptPayment(label: 'Card', amount: Money(57352)),
      ],
      paid: const Money(117352),
    );
    await save(
      '8-discount-tax-split-en-80',
      document(
        busy,
        strings: const EnStrings(),
        tradeName: 'Cafe Aziz',
        logoBytes: mark,
      ),
      w80,
    );

    // No logo, no phone, no address.
    await save(
      '9-no-logo-en-80',
      document(
        plainEn,
        strings: const EnStrings(),
        tradeName: 'Cafe Aziz',
        profile: const ReceiptProfile(branchId: 1, tradeName: 'Cafe Aziz'),
      ),
      w80,
    );
  });
}

Future<ui.Image> _decode(Uint8List rgba, int width, int height) {
  final completer = ui.ImmutableBuffer.fromUint8List(rgba);
  return completer.then((buffer) async {
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  });
}
