import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/receipt/receipt_data.dart';
import 'package:shared_module/features/receipt/receipt_document.dart';

/// README XORDER-008, problem B: the same dish ordered again in a later round
/// printed as another line. The slip now reads Mango Juice × 4 — and nothing
/// stored, and no total, moves.
void main() {
  const juice = Product(
    id: 1,
    categoryId: 1,
    nameEn: 'Mango Juice',
    price: Money(5000),
  );
  const tea = Product(id: 2, categoryId: 1, nameEn: 'Tea', price: Money(2000));
  const bread = Modifier(
    id: 9,
    groupId: 3,
    nameEn: 'Extra ice',
    priceDelta: Money(0),
  );

  /// A line sent to the kitchen in round [round].
  TicketLine sent(
    Product product,
    int quantity,
    int round, {
    List<Modifier> modifiers = const [],
    String? note,
    PriceOverride? override,
    LineVoid? voided,
  }) => TicketLine(
    product: product,
    quantity: quantity,
    modifiers: modifiers,
    note: note,
    stage: LineStage.sent,
    roundNumber: round,
    priceOverride: override,
    voided: voided,
  );

  Ticket ticketOf(
    List<TicketLine> lines, {
    List<AppliedDiscount> discounts = const [],
  }) => Ticket(
    id: 't',
    orderType: OrderType.dineIn,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    lines: lines,
    discounts: discounts,
  );

  PriceOverride at(int minor) => PriceOverride(
    price: Money(minor),
    original: const Money(5000),
    byStaffId: 1,
    at: DateTime(2026, 10, 28),
  );

  LineVoid gone() => LineVoid(byStaffId: 1, at: DateTime(2026, 10, 28));

  List<ReceiptLine> printed(Ticket ticket) =>
      ReceiptData.fromTicket(ticket).lines;

  group('the live receipt', () {
    test('three rounds of the same juice are one line: 1 + 1 + 2 = 4 for 200.00',
        () {
      final lines = printed(
        ticketOf([sent(juice, 1, 1), sent(juice, 1, 2), sent(juice, 2, 3)]),
      );

      expect(lines, hasLength(1));
      expect(lines.single.name, 'Mango Juice');
      expect(lines.single.quantity, 4);
      expect(lines.single.lineTotal.minor, 20000);
    });

    test('the ticket keeps every round; only the printout is merged', () {
      final ticket = ticketOf([
        sent(juice, 1, 1),
        sent(juice, 1, 2),
        sent(juice, 2, 3),
      ]);

      printed(ticket);

      expect(ticket.lines, hasLength(3));
      expect(ticket.lines.map((l) => l.roundNumber), [1, 2, 3]);
    });

    test('the printed lines add up to what they added up to before', () {
      final ticket = ticketOf([
        sent(juice, 1, 1),
        sent(tea, 2, 1),
        sent(juice, 1, 2),
        sent(tea, 1, 3),
      ]);

      final lines = printed(ticket);

      expect(lines, hasLength(2));
      expect(
        lines.fold<int>(0, (sum, l) => sum + l.lineTotal.minor),
        ticket.lines.fold<int>(0, (sum, l) => sum + l.lineTotal.minor),
      );
      expect(
        ReceiptData.fromTicket(ticket).subtotal.minor,
        ticket.totals.subtotal.minor,
        reason: 'the money figures come from the engine, not from the lines',
      );
    });

    test('lines come out in the order the dishes first appeared', () {
      final lines = printed(
        ticketOf([sent(tea, 1, 1), sent(juice, 1, 1), sent(tea, 1, 2)]),
      );

      expect(lines.map((l) => l.name), ['Tea', 'Mango Juice']);
      expect(lines.first.quantity, 2);
    });

    test('a different modifier is a different line', () {
      final lines = printed(
        ticketOf([sent(juice, 1, 1), sent(juice, 1, 2, modifiers: [bread])]),
      );

      expect(lines, hasLength(2));
    });

    test('a different note is a different line', () {
      final lines = printed(
        ticketOf([
          sent(juice, 1, 1),
          sent(juice, 1, 2, note: 'no sugar'),
          sent(juice, 1, 3, note: 'no sugar'),
        ]),
      );

      expect(lines.map((l) => l.quantity), [1, 2]);
    });

    test('a different unit price is a different line', () {
      final lines = printed(
        ticketOf([
          sent(juice, 1, 1),
          sent(juice, 1, 2, override: at(4000)),
        ]),
      );

      expect(lines, hasLength(2));
      expect(lines.last.wasRepriced, isTrue);
    });

    test('the same hand-set price merges and keeps its star', () {
      final lines = printed(
        ticketOf([
          sent(juice, 1, 1, override: at(4000)),
          sent(juice, 2, 2, override: at(4000)),
        ]),
      );

      expect(lines, hasLength(1));
      expect(lines.single.quantity, 3);
      expect(lines.single.lineTotal.minor, 12000);
      expect(lines.single.wasRepriced, isTrue);
    });

    test('a voided line stays on its own, struck through, and never joins a live one',
        () {
      final lines = printed(
        ticketOf([
          sent(juice, 1, 1),
          sent(juice, 1, 2, voided: gone()),
          sent(juice, 1, 3, voided: gone()),
          sent(juice, 1, 4),
        ]),
      );

      expect(lines.map((l) => (l.quantity, l.isVoided)), [
        (2, false),
        (1, true),
        (1, true),
      ]);
    });

    test('a line carrying a discount of its own is not merged', () {
      final lines = printed(
        ticketOf(
          [sent(juice, 1, 1), sent(juice, 1, 2)],
          discounts: [
            AppliedDiscount(
              nameSnapshot: '10% off',
              kind: DiscountKind.percentage,
              amount: const Money(500),
              appliedByStaffId: 1,
              lineKey: TicketLine.keyFor(juice, const []),
              valueBp: 1000,
            ),
          ],
        ),
      );

      expect(lines, hasLength(2));
    });

    test('a line with no merge key is kept exactly as it is', () {
      const a = ReceiptLine(
        name: 'Tea',
        quantity: 1,
        lineTotal: Money(2000),
      );

      expect(ReceiptLine.consolidate([a, a]), hasLength(2));
    });
  });

  group('the slip', () {
    ReceiptDocument slip(ReceiptData data, {AppStrings? strings}) =>
        ReceiptDocument.of(
          data,
          strings: strings ?? const EnStrings(),
          tenantName: 'XOrder Café',
          terminalCode: 'T1',
          cashierName: 'Amer',
          tenderMethods: TenderMethod.seeded,
        );

    for (final strings in <AppStrings>[const EnStrings(), const ArStrings()]) {
      test('prints one Mango Juice row, 4, 200.00 (${strings.languageCode})', () {
        final data = ReceiptData.fromTicket(
          ticketOf([sent(juice, 1, 1), sent(juice, 1, 2), sent(juice, 2, 3)]),
        );

        final rows = slip(data, strings: strings).blocks.whereType<SlipItem>();

        expect(rows, hasLength(1));
        expect(rows.single.name, 'Mango Juice');
        expect(rows.single.quantity, '4');
        expect(rows.single.price, contains('200.00'));
      });
    }
  });

  group('a reprint', () {
    OrderRecord order() => OrderRecord(
      id: 9,
      clientTransactionId: 'txn-9',
      invoiceNumber: 'MAIN-2026-000001',
      status: OrderStatus.paid,
      orderType: OrderType.dineIn,
      occurredAt: DateTime(2026, 10, 28, 20, 41),
      subtotal: const Money(20000),
      discount: Money.zero,
      service: Money.zero,
      vat: Money.zero,
      total: const Money(20000),
    );

    OrderRecordLine row(
      int id,
      int quantity, {
      String key = '1:',
      int unit = 5000,
      DateTime? voidedAt,
      String? note,
    }) => OrderRecordLine(
      id: id,
      lineKey: key,
      name: 'Mango Juice',
      quantity: quantity,
      unitPrice: Money(unit),
      lineTotal: Money(unit * quantity),
      voidedAt: voidedAt,
      note: note,
    );

    List<ReceiptLine> reprinted(
      List<OrderRecordLine> lines, {
      List<OrderRecordDiscount> discounts = const [],
    }) => ReceiptData.fromOrder(
      OrderRecordDetail(
        order: order(),
        lines: lines,
        payments: const [],
        discounts: discounts,
      ),
    ).lines;

    test('merges the stored rounds the same way', () {
      final lines = reprinted([row(1, 1), row(2, 1), row(3, 2)]);

      expect(lines, hasLength(1));
      expect(lines.single.quantity, 4);
      expect(lines.single.lineTotal.minor, 20000);
    });

    test('keeps apart a different key, price, note, void or line discount', () {
      expect(reprinted([row(1, 1), row(2, 1, key: '1:9')]), hasLength(2));
      expect(reprinted([row(1, 1), row(2, 1, unit: 4000)]), hasLength(2));
      expect(reprinted([row(1, 1), row(2, 1, note: 'x')]), hasLength(2));
      expect(
        reprinted([row(1, 1), row(2, 1, voidedAt: DateTime(2026, 10, 28))]),
        hasLength(2),
      );
      expect(
        reprinted(
          [row(1, 1), row(2, 1)],
          discounts: const [
            OrderRecordDiscount(
              name: '10% off',
              amount: Money(500),
              lineKey: '1:',
            ),
          ],
        ),
        hasLength(2),
      );
    });
  });
}
