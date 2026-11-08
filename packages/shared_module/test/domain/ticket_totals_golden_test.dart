import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/ticket.dart';

/// The money a ticket comes to, pinned case by case **before discounts exist**.
///
/// Wave A moves the VAT base from `subtotal + service` to
/// `subtotal − discount + service`. That is the single riskiest calculation
/// change in the programme: every one of these numbers is a real receipt, and a
/// discount feature that quietly shifts a rounding step changes what a
/// business charges without anybody deciding to.
///
/// So these land **first**, against today's behaviour. When discounts arrive,
/// every case here must still produce these totals with no discount applied —
/// and the ones that do not are the cases the change actually affected, which
/// is exactly the list worth reading.
///
/// Every expectation is a literal in minor units. Nothing is computed from the
/// same expression the code under test uses, because a test that recomputes the
/// formula only proves the formula is spelled the same way twice.
void main() {
  Product product(int priceMinor, {int id = 1, bool available = true}) =>
      Product(
        id: id,
        categoryId: 1,
        nameEn: 'Item $id',
        price: Money(priceMinor),
        isAvailable: available,
      );

  Modifier modifier(int deltaMinor, {int id = 1}) => Modifier(
    id: id,
    groupId: 1,
    nameEn: 'Mod $id',
    priceDelta: Money(deltaMinor),
  );

  Ticket ticket({
    required List<TicketLine> lines,
    OrderType type = OrderType.dineIn,
    TaxConfig tax = const TaxConfig(),
    List<Tender> tenders = const [],
  }) => Ticket(
    id: 'golden',
    orderType: type,
    tableId: type == OrderType.dineIn ? 1 : null,
    lines: lines,
    tenders: tenders,
    taxConfig: tax,
  );

  TicketLine line(Product p, int quantity, {List<Modifier> modifiers = const []}) =>
      TicketLine(product: p, quantity: quantity, modifiers: modifiers);

  /// One case: the lines that were rung up, and what the receipt must say.
  void golden(
    String description, {
    required Ticket Function() build,
    required int subtotal,
    required int service,
    required int vat,
    required int total,
    int paid = 0,
    // Defaults to [total]: a ticket nobody has tendered against owes all of it.
    // Spelling that out on every case would be forty repetitions of the one
    // fact that is never in question.
    int? due,
    int change = 0,
  }) {
    test(description, () {
      final totals = build().totals;

      expect(totals.subtotal.minor, subtotal, reason: 'subtotal');
      expect(totals.service.minor, service, reason: 'service');
      expect(totals.vat.minor, vat, reason: 'vat');
      expect(totals.total.minor, total, reason: 'total');
      expect(totals.paid.minor, paid, reason: 'paid');
      expect(totals.due.minor, due ?? total, reason: 'due');
      expect(totals.change.minor, change, reason: 'change');

      // The identity every receipt has to satisfy, restated independently of
      // the four numbers above: the parts foot to the whole.
      expect(
        totals.subtotal.minor + totals.service.minor + totals.vat.minor,
        totals.total.minor,
        reason: 'subtotal + service + vat must equal total',
      );
    });
  }

  group('dine-in · service 12% · VAT 14%', () {
    golden(
      'a single item',
      build: () => ticket(lines: [line(product(10000), 1)]),
      // 100.00 → service 12.00 → VAT on 112.00 = 15.68 → 127.68
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
    );

    golden(
      'quantity multiplies before tax',
      build: () => ticket(lines: [line(product(10000), 3)]),
      subtotal: 30000,
      service: 3600,
      vat: 4704,
      total: 38304,
    );

    golden(
      'several lines',
      build: () => ticket(
        lines: [
          line(product(24500, id: 1), 2),
          line(product(3500, id: 2), 1),
          line(product(1750, id: 3), 4),
        ],
      ),
      // 490.00 + 35.00 + 70.00 = 595.00
      subtotal: 59500,
      service: 7140,
      // 666.40 × 14% = 93.2960 → 93.30. Half-up, so the .296 rounds *up* — the
      // case that caught a hand-written 93.29 while this suite was being
      // written, which is the whole argument for literals over recomputation.
      vat: 9330,
      total: 75970,
    );

    golden(
      'a modifier raises the unit price before quantity',
      build: () => ticket(
        lines: [
          line(product(10000), 2, modifiers: [modifier(500)]),
        ],
      ),
      // (100.00 + 5.00) × 2 = 210.00
      subtotal: 21000,
      service: 2520,
      vat: 3293, // 235.20 × 14% = 32.928 → 32.93
      total: 26813,
    );

    golden(
      'a negative modifier lowers it',
      build: () => ticket(
        lines: [
          line(product(10000), 1, modifiers: [modifier(-1500)]),
        ],
      ),
      subtotal: 8500,
      service: 1020,
      vat: 1333, // 95.20 × 14% = 13.328 → 13.33
      total: 10853,
    );

    golden(
      'a free modifier changes nothing',
      build: () => ticket(
        lines: [
          line(product(10000), 1, modifiers: [modifier(0)]),
        ],
      ),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
    );

    golden(
      'an empty ticket is zero throughout',
      build: () => ticket(lines: []),
      subtotal: 0,
      service: 0,
      vat: 0,
      total: 0,
    );

    golden(
      'a zero-priced line stays zero',
      build: () => ticket(lines: [line(product(0), 2)]),
      subtotal: 0,
      service: 0,
      vat: 0,
      total: 0,
    );
  });

  group('rounding — half-up, applied once at the tax line', () {
    golden(
      'a half-piastre rounds up, not to even',
      build: () => ticket(lines: [line(product(2500), 1)]),
      // 25.00 → service 3.00 → 28.00 × 14% = 3.92 exactly
      subtotal: 2500,
      service: 300,
      vat: 392,
      total: 3192,
    );

    golden(
      'a price that cannot divide cleanly still foots',
      build: () => ticket(lines: [line(product(3333), 1)]),
      // 33.33 → service 3.9996 → 4.00 ; 37.33 × 14% = 5.2262 → 5.23
      subtotal: 3333,
      service: 400,
      vat: 523,
      total: 4256,
    );

    golden(
      'one piastre',
      build: () => ticket(lines: [line(product(1), 1)]),
      // 0.01 → service 0.0012 → 0.00 ; 0.01 × 14% = 0.0014 → 0.00
      subtotal: 1,
      service: 0,
      vat: 0,
      total: 1,
    );

    golden(
      'rounding is applied to the ticket, not per line',
      build: () => ticket(
        lines: [
          line(product(333, id: 1), 1),
          line(product(333, id: 2), 1),
          line(product(333, id: 3), 1),
        ],
      ),
      // 9.99 as one sum. Three lines each rounded alone would drift.
      subtotal: 999,
      service: 120, // 1.1988 → 1.20
      vat: 157, // 11.19 × 14% = 1.5666 → 1.57
      total: 1276,
    );

    golden(
      'a large ticket does not accumulate error',
      build: () => ticket(lines: [line(product(999999), 7)]),
      // 69,999.93
      subtotal: 6999993,
      service: 839999, // 8,399.9916 → 8,399.99
      vat: 1097599, // 78,399.92 × 14% = 10,975.9888 → 10,975.99
      total: 8937591,
    );
  });

  group('service charge is dine-in only, by default', () {
    golden(
      'takeaway takes no service charge',
      build: () =>
          ticket(lines: [line(product(10000), 1)], type: OrderType.takeaway),
      subtotal: 10000,
      service: 0,
      vat: 1400,
      total: 11400,
    );

    golden(
      'delivery takes no service charge',
      build: () =>
          ticket(lines: [line(product(10000), 1)], type: OrderType.delivery),
      subtotal: 10000,
      service: 0,
      vat: 1400,
      total: 11400,
    );

    golden(
      'drive-thru takes no service charge',
      build: () =>
          ticket(lines: [line(product(10000), 1)], type: OrderType.driveThru),
      subtotal: 10000,
      service: 0,
      vat: 1400,
      total: 11400,
    );

    golden(
      'a business that charges service on everything',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        type: OrderType.takeaway,
        tax: const TaxConfig(serviceDineInOnly: false),
      ),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
    );
  });

  group('tax rates a business might actually be on', () {
    golden(
      'no service charge at all',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tax: const TaxConfig(serviceBp: 0),
      ),
      subtotal: 10000,
      service: 0,
      vat: 1400,
      total: 11400,
    );

    golden(
      'no VAT — an unregistered business',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tax: const TaxConfig(vatBp: 0),
      ),
      subtotal: 10000,
      service: 1200,
      vat: 0,
      total: 11200,
    );

    golden(
      'neither',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tax: const TaxConfig(serviceBp: 0, vatBp: 0),
      ),
      subtotal: 10000,
      service: 0,
      vat: 0,
      total: 10000,
    );

    golden(
      'a fractional service rate — 12.5%',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tax: const TaxConfig(serviceBp: 1250),
      ),
      subtotal: 10000,
      service: 1250,
      vat: 1575, // 112.50 × 14% = 15.75 exactly
      total: 12825,
    );

    golden(
      'Saudi VAT at 15%, no service',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tax: const TaxConfig(serviceBp: 0, vatBp: 1500),
      ),
      subtotal: 10000,
      service: 0,
      vat: 1500,
      total: 11500,
    );
  });

  group('tender, balance and change', () {
    golden(
      'nothing tendered leaves the whole total due',
      build: () => ticket(lines: [line(product(10000), 1)]),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
      due: 12768,
    );

    golden(
      'exact cash clears the balance with no change',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tenders: [
          const Tender(typeId: 1, label: 'Cash', amount: Money(12768)),
        ],
      ),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
      paid: 12768,
      due: 0,
    );

    golden(
      'overpayment becomes change, never a negative balance',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tenders: [
          const Tender(typeId: 1, label: 'Cash', amount: Money(15000)),
        ],
      ),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
      paid: 15000,
      due: 0,
      change: 2232,
    );

    golden(
      'a part payment leaves the rest due',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tenders: [
          const Tender(typeId: 1, label: 'Cash', amount: Money(5000)),
        ],
      ),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
      paid: 5000,
      due: 7768,
    );

    golden(
      'split tender — cash and card — sums to the total',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tenders: [
          const Tender(typeId: 1, label: 'Cash', amount: Money(4000)),
          const Tender(typeId: 2, label: 'Card', amount: Money(8768)),
        ],
      ),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
      paid: 12768,
      due: 0,
    );

    golden(
      'three tenders, still exact',
      build: () => ticket(
        lines: [line(product(10000), 1)],
        tenders: [
          const Tender(typeId: 1, label: 'Cash', amount: Money(4000)),
          const Tender(typeId: 2, label: 'Card', amount: Money(4000)),
          const Tender(typeId: 3, label: 'Wallet', amount: Money(4768)),
        ],
      ),
      subtotal: 10000,
      service: 1200,
      vat: 1568,
      total: 12768,
      paid: 12768,
      due: 0,
    );
  });

  group('three-decimal currencies', () {
    test('a Kuwaiti ticket keeps three places end to end', () {
      final kwd = Ticket(
        id: 'kwd',
        orderType: OrderType.takeaway,
        currency: 'KWD',
        exponent: 3,
        taxConfig: TaxConfig(serviceBp: 0, vatBp: 0),
      );

      final totals = kwd
          .copyWith(
            lines: [
              TicketLine(
                product: Product(
                  id: 1,
                  categoryId: 1,
                  nameEn: 'Item',
                  price: const Money(12500, currency: 'KWD', exponent: 3),
                ),
                quantity: 2,
              ),
            ],
          )
          .totals;

      // 12.500 × 2 = 25.000. The exponent is why `Money` carries one at all.
      expect(totals.subtotal.minor, 25000);
      expect(totals.subtotal.exponent, 3);
      expect(totals.subtotal.format(), '25.000');
      expect(totals.total.minor, 25000);
    });
  });

  group('the tax source is disclosed, not assumed', () {
    test('device config is the default, and says so', () {
      expect(const TaxConfig().source, TaxSource.deviceConfig);
    });

    test('a server-authored config compares unequal to a device one', () {
      // Callers compare configurations to decide whether a live ticket needs
      // repricing. Identity comparison here would reprice on every sync pass.
      const device = TaxConfig(serviceBp: 1200, vatBp: 1400);
      const server = TaxConfig(
        serviceBp: 1200,
        vatBp: 1400,
        source: TaxSource.server,
      );

      expect(device == server, isFalse);
      expect(device == const TaxConfig(serviceBp: 1200, vatBp: 1400), isTrue);
    });
  });
}
