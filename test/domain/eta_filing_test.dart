import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';
import 'package:xorder_pos/domain/services/eta_receipt.dart';
import 'package:xorder_pos/domain/services/eta_serialization.dart';

/// Turning a settled sale into the receipt Egypt is owed.
///
/// The arithmetic is what matters here. The filing has to add up to what the
/// customer was actually charged — not to what recomputing the tax today would
/// produce — because those two numbers disagreeing is the discrepancy an audit
/// is looking for.
void main() {
  const profile = ReceiptProfile(
    branchId: 1,
    tradeName: 'Koshari Abou Tarek',
    registrationNumber: '123456789',
    activityCode: '5610',
    branchCode: 'B1',
    address: BranchAddress(
      governate: 'Cairo',
      regionCity: 'Downtown',
      street: 'Champollion',
      buildingNumber: '16',
    ),
  );

  const koshari = Product(
    id: 1,
    categoryId: 1,
    nameEn: 'Koshari',
    price: Money(4500),
    sku: 'K-1',
  );
  const water = Product(
    id: 2,
    categoryId: 1,
    nameEn: 'Water',
    price: Money(1000),
  );

  Ticket ticket({
    List<TicketLine>? lines,
    List<Tender> tenders = const [],
  }) => Ticket(
    id: 'txn-1',
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 1400),
    lines: lines ?? [TicketLine(product: koshari, quantity: 1)],
    tenders: tenders,
  );

  EtaReceiptInput? input(Ticket from, {ReceiptProfile with_ = profile}) =>
      EtaFiling.inputFor(
        ticket: from,
        profile: with_,
        receiptNumber: 'INV-0001',
        deviceSerial: 'TILL-1',
        issuedAt: DateTime.utc(2026, 9, 8, 13),
      );

  Map<String, Object?> json(EtaReceiptInput from) =>
      EtaSerializer.toJson(EtaReceiptBuilder.build(from))!
          as Map<String, Object?>;

  group('when there is nothing to file with', () {
    test('an incomplete profile files nothing', () {
      // Checked here rather than at the database, because "your activity code
      // is four digits" is a sentence somebody can act on and a constraint
      // violation is not.
      const half = ReceiptProfile(branchId: 1, tradeName: 'Koshari');
      expect(input(ticket(), with_: half), isNull);
    });

    test('a complete profile files', () {
      expect(input(ticket()), isNotNull);
    });
  });

  group('what goes on the filing', () {
    test('the totals are the ticket\'s, not a recomputation', () {
      final sale = ticket();
      final built = input(sale)!;

      expect(built.totalAmount.minor, sale.totals.total.minor);
      expect(built.totalSales.minor, sale.totals.subtotal.minor);
      expect(built.netAmount.minor, sale.totals.net.minor);
    });

    test('a voided line is on the slip and off the filing', () {
      // It stays on the customer's copy because the kitchen made it and they
      // watched it happen. It stays off the filing because nobody was charged.
      final sale = ticket(
        lines: [
          TicketLine(product: koshari, quantity: 1),
          TicketLine(
            product: water,
            quantity: 1,
            voided: LineVoid(byStaffId: 1, at: DateTime.utc(2026)),
          ),
        ],
      );
      expect(input(sale)!.items, hasLength(1));
      expect(input(sale)!.items.single.description, 'Koshari');
    });

    test('a SKU travels as the internal code', () {
      expect(input(ticket())!.items.single.internalCode, 'K-1');
    });

    test('an item with no SKU sends none', () {
      final sale = ticket(lines: [TicketLine(product: water, quantity: 1)]);
      expect(input(sale)!.items.single.internalCode, isNull);
    });

    test('a repriced line files at what was charged, not the menu price', () {
      final sale = ticket(
        lines: [
          TicketLine(
            product: koshari,
            quantity: 1,
            priceOverride: PriceOverride(
              price: const Money(4000),
              original: const Money(4500),
              byStaffId: 1,
              at: DateTime.utc(2026),
            ),
          ),
        ],
      );
      expect(input(sale)!.items.single.unitPrice.minor, 4000);
    });
  });

  group('tax apportionment', () {
    test('the lines add up to what the ticket charged', () {
      // Not to a recomputation. Those two numbers disagreeing is the
      // discrepancy an audit is looking for.
      final sale = ticket(
        lines: [
          TicketLine(product: koshari, quantity: 3),
          TicketLine(product: water, quantity: 2),
        ],
      );
      final built = input(sale)!;

      final perLine = built.items
          .expand((item) => item.taxes)
          .fold(0, (sum, tax) => sum + tax.amount.minor);
      final total = built.taxTotals.fold(0, (sum, tax) => sum + tax.amount.minor);

      // Within one minor unit: integer division drops the remainder, which is
      // why the ticket's own figure is what is filed as the total.
      expect((perLine - total).abs(), lessThanOrEqualTo(built.items.length));
    });

    test('a line carries the rate it was charged at', () {
      final built = input(ticket())!;
      expect(built.items.single.taxes.single.rateBp, 1400);
    });

    test('a zero-rated line is filed at zero, not left off', () {
      // "45.00 at 0%" is exactly what a filing needs to see. Omitting it would
      // file a sale with no tax treatment at all, which reads as an oversight
      // rather than as a decision.
      final sale = Ticket(
        id: 'txn-2',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
        lines: [TicketLine(product: koshari, quantity: 1)],
      );
      final tax = input(sale)!.items.single.taxes.single;
      expect(tax.rateBp, 0);
      expect(tax.amount.minor, 0);
      expect(tax.base.minor, 4500);
    });

    test('a zero rate files under the zero-rated code, not the standard one', () {
      // A filing that said 14% and collected nothing is the discrepancy an
      // audit exists to find.
      final sale = Ticket(
        id: 'txn-3',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
        lines: [TicketLine(product: koshari, quantity: 1)],
      );
      expect(
        input(sale)!.items.single.taxes.single.etaSubType,
        EtaTaxCode.zeroRated,
      );
    });

    test('the ETA codes come from the group, not from the rate', () {
      final built = input(ticket())!;
      expect(built.items.single.taxes.single.etaTaxType, EtaTaxCode.valueAdded);
      expect(built.items.single.taxes.single.etaSubType, EtaTaxCode.standardVat);
    });
  });

  group('the payment method', () {
    test('cash is C', () {
      final sale = ticket(
        tenders: const [
          Tender(
            typeId: 1,
            label: 'Cash',
            amount: Money(5130),
            countsAsCash: true,
          ),
        ],
      );
      expect(input(sale)!.paymentMethod, 'C');
    });

    test('a card is V', () {
      final sale = ticket(
        tenders: const [
          Tender(typeId: 2, label: 'Card', amount: Money(5130)),
        ],
      );
      expect(input(sale)!.paymentMethod, 'V');
    });

    test('a wallet is V too — the authority does not care which app', () {
      final sale = ticket(
        tenders: const [
          Tender(typeId: 3, label: 'Wallet', amount: Money(5130)),
        ],
      );
      expect(input(sale)!.paymentMethod, 'V');
    });

    test('a split between the two is M', () {
      final sale = ticket(
        tenders: const [
          Tender(
            typeId: 1,
            label: 'Cash',
            amount: Money(3000),
            countsAsCash: true,
          ),
          Tender(typeId: 2, label: 'Card', amount: Money(2130)),
        ],
      );
      expect(input(sale)!.paymentMethod, 'M');
    });

    test('no tender recorded files as cash, not as blank', () {
      // A till that took money and did not say how took it out of the drawer.
      expect(input(ticket())!.paymentMethod, 'C');
    });

    test('cash on a platform tender is C — the id is not what makes it cash', () {
      // A cloud till pays on the platform's tenders, every one of them above
      // the seeded four (migration 41). Asking "is this id 1" would file the
      // restaurant's only cash drawer as electronic, every sale, every day.
      final sale = ticket(
        tenders: const [
          Tender(
            typeId: 7,
            label: 'Cash',
            amount: Money(5130),
            countsAsCash: true,
          ),
        ],
      );
      expect(input(sale)!.paymentMethod, 'C');
    });

    test('the flag taken with the money wins over the seeded id', () {
      // Somebody unticked "counts as cash" on the seeded Cash row. The payment
      // says what it was when it was taken, and the reconciler files from that
      // same flag on the payment row — the two must not disagree.
      final sale = ticket(
        tenders: const [
          Tender(typeId: 1, label: 'Cash', amount: Money(5130)),
        ],
      );
      expect(input(sale)!.paymentMethod, 'V');
    });
  });

  test('the document it produces is a valid one', () {
    final built = json(input(ticket())!);
    expect((built['header']! as Map)['uuid'], hasLength(64));
    expect((built['seller']! as Map)['rin'], '123456789');
    expect(built['totalAmount'], '51.30');
  });
}
