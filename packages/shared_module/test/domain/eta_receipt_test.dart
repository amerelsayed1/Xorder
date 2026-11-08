import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/receipt_profile.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/services/eta_receipt.dart';
import 'package:shared_module/domain/services/eta_serialization.dart';

/// The document Egypt's tax authority receives.
///
/// The rules worth pinning are the ones where being wrong is invisible until a
/// filing is rejected: amounts that must not pass through a float, a timestamp
/// that must be UTC, optional fields that must be *absent* rather than empty,
/// and a uuid that must be the last thing computed.
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

  const vat = TaxLine(
    name: 'VAT',
    rateBp: 1400,
    base: Money(4500),
    amount: Money(630),
  );

  EtaItem item({
    int quantity = 1,
    Money unitPrice = const Money(4500),
    Money discount = Money.zero,
    String? internalCode,
  }) => EtaItem(
    description: 'Koshari',
    quantity: quantity,
    unitPrice: unitPrice,
    totalSale: Money(unitPrice.minor * quantity),
    total: const Money(5130),
    taxes: const [vat],
    commercialDiscount: discount,
    internalCode: internalCode,
  );

  EtaReceiptInput input({
    DateTime? issuedAt,
    String previousUuid = '',
    String? referenceOldUuid,
    String receiptType = EtaReceiptType.sale,
    List<EtaItem>? items,
    EtaBuyer buyer = const EtaBuyer.person(),
    ReceiptProfile from = profile,
  }) => EtaReceiptInput(
    profile: from,
    receiptNumber: 'INV-000123',
    issuedAt: issuedAt ?? DateTime.utc(2026, 9, 8, 13, 45, 7),
    deviceSerialNumber: 'TILL-0001',
    items: items ?? [item()],
    totalSales: const Money(4500),
    netAmount: const Money(4500),
    totalAmount: const Money(5130),
    taxTotals: const [vat],
    paymentMethod: 'C',
    buyer: buyer,
    previousUuid: previousUuid,
    referenceOldUuid: referenceOldUuid,
    receiptType: receiptType,
  );

  Map<String, Object?> json(EtaObject document) =>
      EtaSerializer.toJson(document)! as Map<String, Object?>;

  Map<String, Object?> at(EtaObject document, String key) =>
      json(document)[key]! as Map<String, Object?>;

  group('amounts', () {
    test('are decimal strings with the currency\'s own places', () {
      final built = EtaReceiptBuilder.build(input());
      expect(json(built)['totalAmount'], '51.30');
      expect(json(built)['totalSales'], '45.00');
    });

    test('never pass through a double', () {
      // 0.07 + 0.01 in binary floating point is 0.08000000000000002. Every
      // amount here is string surgery on minor units, so nothing in this file
      // can produce that.
      final built = EtaReceiptBuilder.build(
        EtaReceiptInput(
          profile: profile,
          receiptNumber: 'INV-1',
          issuedAt: DateTime.utc(2026),
          deviceSerialNumber: 'T',
          items: [item()],
          totalSales: const Money(7),
          netAmount: const Money(1),
          totalAmount: const Money(8),
          taxTotals: const [],
          paymentMethod: 'C',
        ),
      );
      expect(json(built)['totalSales'], '0.07');
      expect(json(built)['totalAmount'], '0.08');
    });

    test('a currency with no minor unit gets no decimal point', () {
      final built = EtaReceiptBuilder.build(
        EtaReceiptInput(
          profile: profile,
          receiptNumber: 'INV-1',
          issuedAt: DateTime.utc(2026),
          deviceSerialNumber: 'T',
          items: [item()],
          totalSales: const Money(1500, currency: 'JPY', exponent: 0),
          netAmount: const Money(1500, currency: 'JPY', exponent: 0),
          totalAmount: const Money(1500, currency: 'JPY', exponent: 0),
          taxTotals: const [],
          paymentMethod: 'C',
          currency: 'JPY',
        ),
      );
      expect(json(built)['totalAmount'], '1500');
    });

    test('a three-place currency keeps all three', () {
      const dinar = Money(45500, currency: 'KWD', exponent: 3);
      final built = EtaReceiptBuilder.build(
        EtaReceiptInput(
          profile: profile,
          receiptNumber: 'INV-1',
          issuedAt: DateTime.utc(2026),
          deviceSerialNumber: 'T',
          items: [item()],
          totalSales: dinar,
          netAmount: dinar,
          totalAmount: dinar,
          taxTotals: const [],
          paymentMethod: 'C',
          currency: 'KWD',
        ),
      );
      expect(json(built)['totalAmount'], '45.500');
    });
  });

  group('the header', () {
    test('the timestamp is UTC with a Z', () {
      // A local timestamp would put a receipt issued at 23:30 in Cairo on the
      // wrong trading day at the authority's end.
      final built = EtaReceiptBuilder.build(
        input(issuedAt: DateTime.utc(2026, 9, 8, 23, 30).add(Duration.zero)),
      );
      expect(at(built, 'header')['dateTimeIssued'], '2026-09-08T23:30:00Z');
    });

    test('a local time is converted, not relabelled', () {
      final local = DateTime.utc(2026, 9, 8, 21, 30).toLocal();
      final built = EtaReceiptBuilder.build(input(issuedAt: local));
      expect(at(built, 'header')['dateTimeIssued'], '2026-09-08T21:30:00Z');
    });

    test('the first receipt a device issues has an empty previousUUID', () {
      // Empty is a true statement exactly once. Every other receipt points at
      // the one before it, and that chain is what makes a missing receipt
      // visible to the authority.
      final built = EtaReceiptBuilder.build(input());
      expect(at(built, 'header')['previousUUID'], '');
    });

    test('a later receipt names the one before it', () {
      final built = EtaReceiptBuilder.build(input(previousUuid: 'a' * 64));
      expect(at(built, 'header')['previousUUID'], 'a' * 64);
    });

    test('a sale carries no referenceOldUUID at all', () {
      // Absent, not empty. ETA read a present-and-empty field as a reference
      // that failed to resolve.
      expect(at(EtaReceiptBuilder.build(input()), 'header').keys,
          isNot(contains('referenceOldUUID')));
    });

    test('a refund names the sale it undoes', () {
      final built = EtaReceiptBuilder.build(
        input(
          receiptType: EtaReceiptType.refund,
          referenceOldUuid: 'b' * 64,
        ),
      );
      expect(at(built, 'header')['referenceOldUUID'], 'b' * 64);
      expect(at(built, 'documentType')['receiptType'], 'r');
    });

    test('an EGP receipt sends no exchange rate', () {
      // A rate of 1 on a receipt in the filing currency is a conversion the
      // authority reads as having happened.
      expect(at(EtaReceiptBuilder.build(input()), 'header').keys,
          isNot(contains('exchangeRate')));
    });
  });

  group('the seller', () {
    test('is the receipt profile, field for field', () {
      final seller = at(EtaReceiptBuilder.build(input()), 'seller');
      expect(seller['rin'], '123456789');
      expect(seller['companyTradeName'], 'Koshari Abou Tarek');
      expect(seller['branchCode'], 'B1');
      expect(seller['activityCode'], '5610');
      expect(seller['deviceSerialNumber'], 'TILL-0001');
    });

    test('the address carries only the parts that were filled in', () {
      final seller = at(EtaReceiptBuilder.build(input()), 'seller');
      final address = seller['branchAddress']! as Map<String, Object?>;
      expect(address['country'], 'EG');
      expect(address['street'], 'Champollion');
      expect(address.keys, isNot(contains('floor')));
      expect(address.keys, isNot(contains('postalCode')));
    });

    test('an optional address part appears once it is filled in', () {
      const withFloor = ReceiptProfile(
        branchId: 1,
        tradeName: 'Koshari',
        registrationNumber: '123456789',
        activityCode: '5610',
        branchCode: 'B1',
        address: BranchAddress(
          governate: 'Cairo',
          regionCity: 'Downtown',
          street: 'Champollion',
          buildingNumber: '16',
          floor: '2',
        ),
      );
      final seller = at(
        EtaReceiptBuilder.build(input(from: withFloor)),
        'seller',
      );
      expect((seller['branchAddress']! as Map)['floor'], '2');
    });
  });

  group('the buyer', () {
    test('a walk-in is a person and nothing more', () {
      // The overwhelmingly common case in a business, and the one where
      // inventing a placeholder name would be inventing a customer.
      final buyer = at(EtaReceiptBuilder.build(input()), 'buyer');
      expect(buyer, {'type': 'P'});
    });

    test('a company gives a registration number', () {
      final built = EtaReceiptBuilder.build(
        input(
          buyer: const EtaBuyer.business(id: '987654321', name: 'Acme'),
        ),
      );
      expect(at(built, 'buyer'), {
        'type': 'B',
        'id': '987654321',
        'name': 'Acme',
      });
    });
  });

  group('items and tax', () {
    test('a line carries its own tax at its own rate', () {
      final built = EtaReceiptBuilder.build(input());
      final items = json(built)['itemData']! as List;
      final taxes = (items.single as Map)['taxableItems']! as List;
      expect(taxes.single, {
        'taxType': 'T1',
        'amount': '6.30',
        'subType': 'V009',
        'rate': '14',
      });
    });

    test('a fractional rate keeps its fraction', () {
      const half = TaxLine(
        name: 'VAT',
        rateBp: 1450,
        base: Money(4500),
        amount: Money(653),
      );
      final built = EtaReceiptBuilder.build(
        EtaReceiptInput(
          profile: profile,
          receiptNumber: 'INV-1',
          issuedAt: DateTime.utc(2026),
          deviceSerialNumber: 'T',
          items: [
            EtaItem(
              description: 'Koshari',
              quantity: 1,
              unitPrice: const Money(4500),
              totalSale: const Money(4500),
              total: const Money(5153),
              taxes: const [half],
            ),
          ],
          totalSales: const Money(4500),
          netAmount: const Money(4500),
          totalAmount: const Money(5153),
          taxTotals: const [half],
          paymentMethod: 'C',
        ),
      );
      final items = json(built)['itemData']! as List;
      final taxes = (items.single as Map)['taxableItems']! as List;
      expect((taxes.single as Map)['rate'], '14.5');
    });

    test('netSale is the sale less the discount, not recomputed from tax', () {
      final built = EtaReceiptBuilder.build(
        input(items: [item(discount: const Money(500))]),
      );
      final line = (json(built)['itemData']! as List).single as Map;
      expect(line['totalSale'], '45.00');
      expect(line['netSale'], '40.00');
    });

    test('a line with no discount carries no discount block', () {
      final line =
          (json(EtaReceiptBuilder.build(input()))['itemData']! as List).single
              as Map;
      expect(line.keys, isNot(contains('commercialDiscountData')));
    });

    test('a business with no SKUs sends no internal code', () {
      final line =
          (json(EtaReceiptBuilder.build(input()))['itemData']! as List).single
              as Map;
      expect(line.keys, isNot(contains('internalCode')));
    });

    test('a SKU is sent when there is one', () {
      final built = EtaReceiptBuilder.build(
        input(items: [item(internalCode: 'K-1')]),
      );
      final line = (json(built)['itemData']! as List).single as Map;
      expect(line['internalCode'], 'K-1');
    });

    test('two lines are two array elements, in order', () {
      final built = EtaReceiptBuilder.build(
        input(items: [item(), item(quantity: 2)]),
      );
      final items = json(built)['itemData']! as List;
      expect(items, hasLength(2));
      expect((items[1] as Map)['quantity'], '2');
    });
  });

  group('the uuid', () {
    test('is stamped into the header', () {
      final built = EtaReceiptBuilder.build(input());
      expect(at(built, 'header')['uuid'], hasLength(64));
    });

    test('is the hash of everything else — recomputing it agrees', () {
      // The property that makes the document self-describing: anybody holding
      // it can check the uuid without holding the key that signed it.
      final built = EtaReceiptBuilder.build(input());
      expect(at(built, 'header')['uuid'], EtaSerializer.uuidOf(built));
    });

    test('two receipts differing only in number get different uuids', () {
      final one = EtaReceiptBuilder.build(input());
      final other = EtaReceiptBuilder.build(
        EtaReceiptInput(
          profile: profile,
          receiptNumber: 'INV-000124',
          issuedAt: DateTime.utc(2026, 9, 8, 13, 45, 7),
          deviceSerialNumber: 'TILL-0001',
          items: [item()],
          totalSales: const Money(4500),
          netAmount: const Money(4500),
          totalAmount: const Money(5130),
          taxTotals: const [vat],
          paymentMethod: 'C',
        ),
      );
      expect(at(one, 'header')['uuid'], isNot(at(other, 'header')['uuid']));
    });

    test('the same receipt built twice gets the same uuid', () {
      // Not a random identifier: it is a fingerprint, so a resubmission of the
      // same sale is recognisable as the same document rather than as a
      // second one.
      expect(
        at(EtaReceiptBuilder.build(input()), 'header')['uuid'],
        at(EtaReceiptBuilder.build(input()), 'header')['uuid'],
      );
    });
  });

  test('the document type version is pinned', () {
    // Changing this changes what every field means. It should be a deliberate
    // act with a test to update, not a constant somebody edits in passing.
    expect(EtaReceiptBuilder.typeVersion, '1.2');
    expect(
      at(EtaReceiptBuilder.build(input()), 'documentType')['typeVersion'],
      '1.2',
    );
  });
}
