import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/models/receipt_profile.dart';
import 'package:shared_module/domain/models/service_charge.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';
import 'package:shared_module/features/receipt/receipt_data.dart';
import 'package:shared_module/features/receipt/receipt_document.dart';
import 'package:shared_module/features/receipt/receipt_paper.dart';

/// What the slip says, block by block.
///
/// **The owner's mockup is the reason this suite exists.** It was drawn with
/// the discount added instead of taken off, and printed 134.06 for a sale that
/// comes to 105.34. The layout was adopted; the arithmetic was not. So the
/// first group builds exactly that sale through the engine and checks every
/// figure the paper prints — a redesign is the moment somebody is tempted to
/// "just format it here", and this is what says no.
void main() {
  /// Water 15.00 and Boba Milk Tea 90.00, 12% off the order, 14% VAT, cash.
  Ticket ownersSale({
    TenderMethod method = const TenderMethod(
      id: 1,
      code: 'cash',
      nameEn: 'Cash',
      nameAr: 'نقدي',
      kind: TenderKind.cash,
      countsAsCash: true,
    ),
  }) {
    var ticket = Ticket(id: 'owner', orderType: OrderType.takeaway);
    for (final product in const [
      Product(id: 1, categoryId: 1, nameEn: 'Water', price: Money(1500)),
      Product(
        id: 2,
        categoryId: 1,
        nameEn: 'Boba Milk Tea',
        price: Money(9000),
      ),
    ]) {
      ticket = TicketEngine.addLine(ticket, product).ticket!;
    }
    ticket = TicketEngine.applyOrderDiscount(
      ticket,
      const Discount(
        id: 1,
        code: 'twelve',
        nameEn: '12% off',
        kind: DiscountKind.percentage,
        scope: DiscountScope.order,
        valueBp: 1200,
      ),
      now: DateTime(2026, 9, 13, 8, 7),
      appliedBy: 1,
    ).ticket!;
    return TicketEngine.addTender(
      ticket,
      typeId: method.id,
      label: method.wireLabel,
      countsAsCash: method.countsAsCash,
    ).ticket!;
  }

  ReceiptDocument slip(
    ReceiptData data, {
    AppStrings strings = const EnStrings(),
    List<TenderMethod> methods = TenderMethod.seeded,
  }) => ReceiptDocument.of(
    data,
    strings: strings,
    tenantName: 'XOrder Café',
    terminalCode: 'T1',
    cashierName: 'Amer',
    tenderMethods: methods,
  );

  /// Label to value, for every label-and-value row on the slip.
  Map<String, String> rows(ReceiptDocument document) => {
    for (final block in document.blocks)
      if (block is SlipRow) block.label: block.value,
  };

  SlipGrandTotal total(ReceiptDocument document) =>
      document.blocks.whereType<SlipGrandTotal>().single;

  group("the owner's sale", () {
    test('prints the engine’s figures, not the mockup’s', () {
      final document = slip(ReceiptData.fromTicket(ownersSale()));
      final printed = rows(document);

      expect(printed['Subtotal'], '105.00 EGP');
      expect(printed['Discount (12%)'], '-12.60 EGP');
      expect(printed['VAT (14%)'], '12.94 EGP');
      expect(total(document).amount, '105.34');
      expect(total(document).currency, 'EGP');

      // The mockup's total, which added the discount. It must not appear.
      final everything = [
        for (final block in document.blocks)
          if (block is SlipRow) block.value,
        total(document).amount,
      ];
      expect(everything, isNot(contains('134.06')));
    });

    test('says how it was paid', () {
      final printed = rows(slip(ReceiptData.fromTicket(ownersSale())));
      expect(printed['Payment Method'], 'Cash');
      expect(printed['Amount Paid'], '105.34 EGP');
      expect(printed.containsKey('Change'), isFalse, reason: 'paid exact');
    });

    test('in Arabic, with the same figures and the tender named in Arabic', () {
      final document = slip(
        ReceiptData.fromTicket(ownersSale()),
        strings: const ArStrings(),
      );
      final printed = rows(document);

      expect(document.rightToLeft, isTrue);
      expect(printed['المجموع الفرعي'], '105.00 EGP');
      expect(printed['خصم (12%)'], '-12.60 EGP');
      expect(printed['ضريبة القيمة المضافة (14%)'], '12.94 EGP');
      expect(printed['طريقة الدفع'], 'نقدي');
      expect(total(document).label, 'الإجمالي');
      expect(total(document).amount, '105.34');
    });

    test('the items table lists each line with its own total', () {
      final items = slip(ReceiptData.fromTicket(ownersSale())).blocks
          .whereType<SlipItem>()
          .toList();
      expect([for (final item in items) item.name], ['Water', 'Boba Milk Tea']);
      expect([for (final item in items) item.quantity], ['1', '1']);
      expect(
        [for (final item in items) item.price],
        ['15.00 EGP', '90.00 EGP'],
      );
    });
  });

  group('the discount label', () {
    test('names no percentage for a fixed amount off', () {
      final ticket = TicketEngine.applyOrderDiscount(
        TicketEngine.addLine(
          Ticket(id: 'fixed', orderType: OrderType.takeaway),
          const Product(
            id: 1,
            categoryId: 1,
            nameEn: 'Tea',
            price: Money(10000),
          ),
        ).ticket!,
        const Discount(
          id: 2,
          code: 'ten-off',
          nameEn: '10 off',
          kind: DiscountKind.fixed,
          scope: DiscountScope.order,
          valueMinor: Money(1000),
        ),
        now: DateTime(2026, 9, 13),
        appliedBy: 1,
      ).ticket!;

      final printed = rows(slip(ReceiptData.fromTicket(ticket)));
      expect(printed['Discount'], '-10.00 EGP');
      expect(printed.keys.where((label) => label.contains('%')), ['VAT (14%)']);
    });

    test(
      'names no percentage when a cap means the rate does not explain it',
      () {
        // "20% off, up to 5.00" on 100.00 takes 5.00 off. Printing "(20%)"
        // beside -5.00 under a 100.00 subtotal is a sum the customer can do.
        final ticket = TicketEngine.applyOrderDiscount(
          TicketEngine.addLine(
            Ticket(id: 'capped', orderType: OrderType.takeaway),
            const Product(
              id: 1,
              categoryId: 1,
              nameEn: 'Tea',
              price: Money(10000),
            ),
          ).ticket!,
          const Discount(
            id: 3,
            code: 'capped',
            nameEn: '20% up to 5',
            kind: DiscountKind.percentage,
            scope: DiscountScope.order,
            valueBp: 2000,
            maxDiscount: Money(500),
          ),
          now: DateTime(2026, 9, 13),
          appliedBy: 1,
        ).ticket!;

        final data = ReceiptData.fromTicket(ticket);
        expect(data.discount.minor, 500);
        expect(data.discountBp, isNull);
        expect(rows(slip(data))['Discount'], '-5.00 EGP');
      },
    );
  });

  group('the VAT label', () {
    test('prints one line per rate, each from the tax lines', () {
      // A zero-rated bottle of water beside a standard-rated meal. Nothing
      // here is 14% by assumption: the rates come off the engine's lines.
      final ticket =
          [
            const Product(
              id: 1,
              categoryId: 1,
              nameEn: 'Water',
              price: Money(1500),
              taxGroupId: 2,
            ),
            const Product(
              id: 2,
              categoryId: 1,
              nameEn: 'Grill',
              price: Money(10000),
            ),
          ].fold(
            Ticket(
              id: 'rates',
              orderType: OrderType.takeaway,
              taxConfig: const TaxConfig().withTaxGroups(const [
                TaxGroup(id: 1, nameEn: 'VAT', rateBp: 1400, isDefault: true),
                TaxGroup(id: 2, nameEn: 'Zero', rateBp: 0),
              ]),
            ),
            (ticket, product) => TicketEngine.addLine(ticket, product).ticket!,
          );

      final printed = rows(slip(ReceiptData.fromTicket(ticket)));
      expect(printed['VAT (14%)'], '14.00 EGP');
      expect(printed['VAT (0%)'], '0.00 EGP');
    });

    test('a rate with a fraction prints the fraction, not a rounded whole', () {
      // This printed "VAT 13%" — `(1250 / 100).toStringAsFixed(0)`. Watched
      // fail before the fix.
      final document = slip(
        ReceiptData(
          orderType: OrderType.takeaway,
          occurredAt: DateTime(2026, 9, 13, 8, 7),
          lines: const [],
          subtotal: const Money(10000),
          discount: Money.zero,
          service: Money.zero,
          vat: const Money(1250),
          total: const Money(11250),
          paid: const Money(11250),
          change: Money.zero,
          taxLines: const [ReceiptTaxLine(rateBp: 1250, amount: Money(1250))],
        ),
      );
      expect(rows(document).keys, contains('VAT (12.5%)'));
    });

    test('rates format without a double anywhere near them', () {
      expect(receiptPercent(1400), '14');
      expect(receiptPercent(1250), '12.5');
      expect(receiptPercent(1225), '12.25');
      expect(receiptPercent(1405), '14.05');
      expect(receiptPercent(0), '0');
    });
  });

  test('a configured service charge does not print the legacy rate', () {
    // It printed "SERVICE 12%" — `TaxConfig.serviceBp`, the fallback — over a
    // charge taken at 10%. Watched fail before the fix.
    final ticket = TicketEngine.addLine(
      Ticket(
        id: 'svc',
        orderType: OrderType.dineIn,
        taxConfig: const TaxConfig().withServiceCharges(const [
          ServiceCharge(id: 1, nameEn: 'Service', rateBp: 1000),
        ]),
      ),
      const Product(id: 1, categoryId: 1, nameEn: 'Grill', price: Money(10000)),
    ).ticket!;
    expect(ticket.totals.service.minor, 1000, reason: 'charged at 10%');

    final labels = rows(slip(ReceiptData.fromTicket(ticket))).keys;
    expect(labels, contains(const EnStrings().orderDetailService));
    expect(labels.where((label) => label.contains('12')), isEmpty);
  });

  group('a reprint of a split bill', () {
    OrderRecordDetail splitBill() => OrderRecordDetail(
      order: OrderRecord(
        id: 9,
        clientTransactionId: 'txn-9',
        invoiceNumber: 'HST-000512',
        status: OrderStatus.paid,
        orderType: OrderType.dineIn,
        occurredAt: DateTime(2026, 9, 12, 20, 41),
        subtotal: const Money(40000),
        discount: Money.zero,
        service: const Money(4800),
        vat: const Money(6272),
        total: const Money(51072),
        tableLabel: 'T4',
        servedByName: 'Nour Adel',
      ),
      lines: const [
        OrderRecordLine(
          id: 1,
          lineKey: 'L1',
          name: 'Mixed Grill',
          quantity: 2,
          unitPrice: Money(20000),
          lineTotal: Money(40000),
        ),
      ],
      payments: const [
        OrderRecordPayment(
          label: 'Cash',
          amount: Money(30000),
          tenderTypeId: 1,
        ),
        OrderRecordPayment(
          label: 'Card',
          amount: Money(21072),
          tenderTypeId: 2,
        ),
      ],
      discounts: const [],
      taxLines: const [
        TaxLine(
          name: 'VAT',
          rateBp: 1400,
          base: Money(44800),
          amount: Money(6272),
        ),
      ],
    );

    test('prints one line per tender, the service, and the stamp', () {
      final document = slip(ReceiptData.fromOrder(splitBill()));
      final printed = rows(document);

      expect(document.blocks.first, isA<SlipStamp>());
      expect(printed['Cash'], '300.00 EGP');
      expect(printed['Card'], '210.72 EGP');
      expect(printed['Amount Paid'], '510.72 EGP');
      // No rate: service is not stored per rate, and a reprint does not guess.
      expect(printed['Service'], '48.00 EGP');
      expect(printed['VAT (14%)'], '62.72 EGP');
      expect(total(document).amount, '510.72');
    });

    test('keeps a renamed method under the name it was paid with', () {
      // Somebody renamed "Card" to "Visa" after the sale. The Arabic slip
      // must not turn last month's "Card" into this month's name.
      final document = slip(
        ReceiptData.fromOrder(splitBill()),
        strings: const ArStrings(),
        methods: const [
          TenderMethod(id: 1, code: 'cash', nameEn: 'Cash', nameAr: 'نقدي'),
          TenderMethod(id: 2, code: 'card', nameEn: 'Visa', nameAr: 'فيزا'),
        ],
      );
      final printed = rows(document);
      expect(printed['نقدي'], '300.00 EGP');
      expect(printed['Card'], '210.72 EGP');
      expect(printed.containsKey('فيزا'), isFalse);
    });
  });

  testWidgets('the preview shows every line the printer is sent', (
    tester,
  ) async {
    // The claim the preview makes is "this is the receipt". It is built from
    // the same document the raster prints, so every row, item and centred line
    // of that document has to be on screen.
    final data = ReceiptData.fromTicket(ownersSale());
    const profile = ReceiptProfile(
      branchId: 1,
      tradeName: 'XOrder Café',
      phone: '+20 2 2577 5935',
      address: BranchAddress(street: 'Champollion', regionCity: 'Cairo'),
    );

    tester.view
      ..physicalSize = const Size(600, 2400)
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
              width: 328,
              child: ReceiptPaper(
                data: data,
                profile: profile,
                tenantName: 'XOrder Café',
                terminalCode: 'T1',
                cashierName: 'Amer',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final document = ReceiptDocument.of(
      data,
      strings: const EnStrings(),
      profile: profile,
      tenantName: 'XOrder Café',
      terminalCode: 'T1',
      cashierName: 'Amer',
    );
    final expected = <String>[
      for (final block in document.blocks)
        ...switch (block) {
          SlipRow(:final label, :final value) => [label, value],
          SlipItem(:final name, :final quantity, :final price) => [
            name,
            quantity,
            price,
          ],
          SlipItemsHeader(:final item, :final quantity, :final price) => [
            item,
            quantity,
            price,
          ],
          SlipCentre(:final text) => [text],
          SlipStamp(:final text) => [text],
          SlipGrandTotal(:final label, :final amount, :final currency) => [
            label,
            amount,
            currency,
          ],
          SlipRule() ||
          SlipGap() ||
          SlipQr() ||
          SlipLogo() => <String>[],
        },
    ];

    for (final text in expected.where((text) => text.isNotEmpty)) {
      expect(find.text(text), findsWidgets, reason: '"$text" is on the paper');
    }
    expect(tester.takeException(), isNull);
  });

  group('the currency is printed beside every amount (XORD-026)', () {
    test(
      'every amount row, item price and payment line ends with the code',
      () {
        final document = slip(ReceiptData.fromTicket(ownersSale()));

        final amounts = document.blocks
            .whereType<SlipRow>()
            .where((row) => row.amount)
            .toList();
        expect(
          amounts.map((row) => row.label),
          containsAll([
            'Subtotal',
            'Discount (12%)',
            'VAT (14%)',
            'Amount Paid',
          ]),
        );
        for (final row in amounts) {
          expect(row.value, endsWith(' EGP'), reason: row.label);
        }
        for (final item in document.blocks.whereType<SlipItem>()) {
          expect(item.price, endsWith(' EGP'), reason: item.name);
        }
      },
    );

    test('a row that is not money carries no code and is not an amount', () {
      final document = slip(ReceiptData.fromTicket(ownersSale()));
      final others = document.blocks.whereType<SlipRow>().where(
        (row) => !row.amount,
      );

      expect(others, isNotEmpty);
      for (final row in others) {
        expect(row.value, isNot(contains('EGP')), reason: row.label);
      }
    });

    test('the total keeps its figure and its code apart, as before', () {
      final total = slip(ReceiptData.fromTicket(ownersSale())).blocks
          .whereType<SlipGrandTotal>()
          .single;

      expect(total.amount, '105.34');
      expect(total.currency, 'EGP');
    });

    test(
      'only the formatting changed: figures are the engine\'s to the cent',
      () {
        final data = ReceiptData.fromTicket(ownersSale());
        final printed = rows(slip(data));

        String bare(String label) =>
            printed[label]!.replaceFirst(' EGP', '').replaceFirst('-', '');
        expect(bare('Subtotal'), data.subtotal.format());
        expect(bare('Discount (12%)'), data.discount.format());
        expect(bare('Amount Paid'), data.paid.format());
      },
    );
  });

  group('XOrder is only in the footer', () {
    String text(SlipBlock block) => switch (block) {
      SlipCentre(:final text) || SlipStamp(:final text) => text,
      SlipRow(:final label, :final value) => '$label $value',
      SlipItem(:final name) => name,
      SlipItemsHeader(:final item) => item,
      SlipGrandTotal(:final label) => label,
      _ => '',
    };

    test(
      'nothing above the footer names it, and its mark is in the footer',
      () {
        final document = ReceiptDocument.of(
          ReceiptData.fromTicket(ownersSale()),
          strings: const EnStrings(),
          tenantName: 'Cafe Aziz',
          terminalCode: 'T1',
          cashierName: 'Amer',
        );
        final blocks = document.blocks;
        // The footer starts at the thank-you; `xorder.io` follows it.
        final footerFrom = blocks.lastIndexWhere(
          (block) =>
              block is SlipCentre && block.emphasis == SlipEmphasis.strong,
        );

        expect(footerFrom, greaterThan(0));
        for (final block in blocks.take(footerFrom)) {
          expect(text(block).toLowerCase(), isNot(contains('xorder')));
        }
        expect(
          blocks.whereType<SlipCentre>().where((b) => b.text == 'xorder.io'),
          hasLength(1),
        );
        expect(
          blocks.indexWhere((b) => b is SlipCentre && b.text == 'xorder.io'),
          greaterThan(footerFrom),
        );
      },
    );
  });

  group('the logo (XORD-024)', () {
    final mark = Uint8List.fromList([1, 2, 3, 4]);

    ReceiptDocument withLogo(
      Uint8List? logo, {
      bool reprint = false,
      AppStrings strings = const EnStrings(),
    }) {
      final data = reprint
          ? ReceiptData(
              invoiceNumber: 'HST-000512',
              orderType: OrderType.dineIn,
              occurredAt: DateTime(2026, 9, 12, 20, 41),
              lines: const [
                ReceiptLine(name: 'Tea', quantity: 1, lineTotal: Money(2500)),
              ],
              subtotal: const Money(2500),
              discount: Money.zero,
              service: Money.zero,
              vat: Money.zero,
              total: const Money(2500),
              paid: const Money(2500),
              change: Money.zero,
              isReprint: true,
            )
          : ReceiptData.fromTicket(ownersSale());
      return ReceiptDocument.of(
        data,
        strings: strings,
        tenantName: 'Cafe Aziz',
        terminalCode: 'T1',
        cashierName: 'Amer',
        logo: logo,
      );
    }

    test('is the first block, above the business name', () {
      final blocks = withLogo(mark).blocks;

      expect(blocks.first, isA<SlipLogo>());
      expect((blocks.first as SlipLogo).bytes, mark);
      final name = blocks.indexWhere(
        (b) => b is SlipCentre && b.emphasis == SlipEmphasis.title,
      );
      expect(name, 1);
    });

    test('comes after the REPRINT stamp, which must be read first', () {
      final blocks = withLogo(mark, reprint: true).blocks;

      expect(blocks[0], isA<SlipStamp>());
      expect(blocks[1], isA<SlipLogo>());
    });

    test('no logo, or an empty one, leaves the slip exactly as it was', () {
      final none = withLogo(null).blocks;
      final empty = withLogo(Uint8List(0)).blocks;
      final before = slip(ReceiptData.fromTicket(ownersSale())).blocks;

      expect(none.whereType<SlipLogo>(), isEmpty);
      expect(empty.whereType<SlipLogo>(), isEmpty);
      expect(none.length, empty.length);
      // Same shape as a slip built the way it was before there was a logo.
      expect(none.length, before.length);
    });

    test('adds nothing but the logo, and no XOrder mark above the footer', () {
      final plain = withLogo(null).blocks;
      final logo = withLogo(mark).blocks;

      expect(logo.length, plain.length + 1);
      expect(
        logo.skip(1).map((b) => b.runtimeType),
        plain.map((b) => b.runtimeType),
      );
    });
  });
}
