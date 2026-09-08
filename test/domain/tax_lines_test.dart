import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/discount.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

/// Tax by rate — the `tax_lines[]` a filing needs.
///
/// The risk register promised this "from day one so a compliance layer has
/// something to attach to", and nothing was built. Egypt's ETA e-receipt cannot
/// be produced without it: a receipt stating one VAT figure with no rates behind
/// it is not filable.
///
/// **The load-bearing claim is that nothing moved.** A menu where every product
/// shares one rate must total exactly as it did before this existed, to the
/// piastre. The 31 golden money tests are what check that; this file checks
/// what the change makes newly possible.
void main() {
  const standard = TaxGroup(id: 1, nameEn: 'VAT 14%', rateBp: 1400, isDefault: true);
  const zeroRated = TaxGroup(id: 2, nameEn: 'Zero-rated', rateBp: 0);
  const reduced = TaxGroup(id: 3, nameEn: 'VAT 5%', rateBp: 500);

  Product product(int id, int price, {int? taxGroupId}) => Product(
    id: id,
    categoryId: 1,
    nameEn: 'Item $id',
    price: Money(price),
    taxGroupId: taxGroupId,
  );

  Ticket ticket({
    required List<TicketLine> lines,
    List<TaxGroup> groups = const [standard, zeroRated, reduced],
    int serviceBp = 0,
    List<AppliedDiscount> discounts = const [],
  }) => Ticket(
    id: 'txn-1',
    orderType: OrderType.dineIn,
    taxConfig: TaxConfig(
      serviceBp: serviceBp,
      vatBp: 1400,
      taxGroups: groups,
    ),
    lines: lines,
    discounts: discounts,
  );

  group('one rate behaves exactly as before', () {
    test('a single group produces one tax line', () {
      final totals = ticket(
        lines: [TicketLine(product: product(1, 10000), quantity: 1)],
      ).totals;

      expect(totals.taxLines, hasLength(1));
      expect(totals.taxLines.single.rateBp, 1400);
      expect(totals.taxLines.single.base.minor, 10000);
      expect(totals.vat.minor, 1400);
    });

    test('rounding is per rate, not per line', () {
      // The case that caught the first implementation. Three lines of 3.33 at
      // 14% round to 0.47 apiece and sum to 1.41; 9.99 taxed once is 1.40.
      final totals = ticket(
        lines: [
          for (var i = 1; i <= 3; i++)
            TicketLine(product: product(i, 333), quantity: 1),
        ],
      ).totals;

      expect(totals.taxLines, hasLength(1));
      expect(totals.taxLines.single.base.minor, 999);
      expect(totals.vat.minor, 140);
    });

    test('a restaurant with no groups configured still charges its rate', () {
      // The normal case, and the one every existing order was written under.
      final totals = ticket(
        lines: [TicketLine(product: product(1, 10000), quantity: 1)],
        groups: const [],
      ).totals;

      expect(totals.vat.minor, 1400);
      expect(totals.taxLines.single.rateBp, 1400);
    });

    test('a branch on a non-standard rate keeps it', () {
      // The fallback is built from `vatBp`, not from Egypt's headline rate: a
      // branch configured at 15% must not silently revert to 14%.
      final totals = Ticket(
        id: 'txn',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 1500),
        lines: [TicketLine(product: product(1, 10000), quantity: 1)],
      ).totals;

      expect(totals.vat.minor, 1500);
    });
  });

  group('several rates on one ticket', () {
    test('each rate gets its own line, and they sum to the VAT', () {
      final totals = ticket(
        lines: [
          TicketLine(product: product(1, 10000, taxGroupId: 1), quantity: 1),
          TicketLine(product: product(2, 4000, taxGroupId: 2), quantity: 1),
        ],
      ).totals;

      expect(totals.taxLines, hasLength(2));
      expect(totals.vat.minor, 1400);

      final byRate = {for (final l in totals.taxLines) l.rateBp: l};
      expect(byRate[1400]!.base.minor, 10000);
      expect(byRate[1400]!.amount.minor, 1400);
      // Kept, not dropped: "40.00 at 0%" is exactly what a filing needs.
      expect(byRate[0]!.base.minor, 4000);
      expect(byRate[0]!.amount.minor, 0);
    });

    test('the amounts always sum to the VAT figure', () {
      final totals = ticket(
        lines: [
          TicketLine(product: product(1, 3333, taxGroupId: 1), quantity: 1),
          TicketLine(product: product(2, 6667, taxGroupId: 3), quantity: 1),
        ],
      ).totals;

      final summed = totals.taxLines.fold(0, (s, l) => s + l.amount.minor);
      // Not "about equal" — the VAT is built from the lines, so it cannot
      // disagree with them.
      expect(summed, totals.vat.minor);
    });

    test('lines sharing a rate are one entry', () {
      final totals = ticket(
        lines: [
          TicketLine(product: product(1, 5000, taxGroupId: 1), quantity: 1),
          TicketLine(product: product(2, 5000, taxGroupId: 1), quantity: 1),
        ],
      ).totals;

      expect(totals.taxLines, hasLength(1));
      expect(totals.taxLines.single.base.minor, 10000);
    });

    test('the standard rate leads', () {
      final totals = ticket(
        lines: [
          TicketLine(product: product(1, 4000, taxGroupId: 2), quantity: 1),
          TicketLine(product: product(2, 4000, taxGroupId: 3), quantity: 1),
          TicketLine(product: product(3, 4000, taxGroupId: 1), quantity: 1),
        ],
      ).totals;

      // Highest first, so exceptions read as exceptions.
      expect(totals.taxLines.map((l) => l.rateBp), [1400, 500, 0]);
    });

    test('a product naming a group this build has not synced falls back', () {
      // Under-charging tax is a debt the restaurant owes; over-charging is
      // money taken from a customer. The default is the safe answer.
      final totals = ticket(
        lines: [TicketLine(product: product(1, 10000, taxGroupId: 99), quantity: 1)],
      ).totals;

      expect(totals.vat.minor, 1400);
    });
  });

  group('service charge', () {
    test('is taxed at the default rate', () {
      final totals = ticket(
        lines: [TicketLine(product: product(1, 10000), quantity: 1)],
        serviceBp: 1200,
      ).totals;

      // 100.00 + 12.00 service, both at 14% = 15.68.
      expect(totals.service.minor, 1200);
      expect(totals.taxLines.single.base.minor, 11200);
      expect(totals.vat.minor, 1568);
    });

    test('does not inherit a zero-rated product’s treatment', () {
      // Service is the restaurant's charge for service, not a product. A
      // ticket of nothing but bottled water still owes tax on the service.
      final totals = ticket(
        lines: [TicketLine(product: product(1, 10000, taxGroupId: 2), quantity: 1)],
        serviceBp: 1200,
      ).totals;

      final byRate = {for (final l in totals.taxLines) l.rateBp: l};
      expect(byRate[0]!.base.minor, 10000);
      expect(byRate[1400]!.base.minor, 1200);
      expect(totals.vat.minor, 168);
    });
  });

  group('a discount is apportioned before tax', () {
    test('comes off the base, not off the tax', () {
      final totals = ticket(
        lines: [TicketLine(product: product(1, 10000), quantity: 1)],
        discounts: const [
          AppliedDiscount(
            nameSnapshot: 'Staff meal',
            kind: DiscountKind.fixed,
            amount: Money(2000),
            appliedByStaffId: 4,
          ),
        ],
      ).totals;

      expect(totals.taxLines.single.base.minor, 8000);
      expect(totals.vat.minor, 1120);
    });

    test('splits across rates by value', () {
      // 100 standard + 100 zero-rated, 20.00 off the order: 10.00 comes off
      // each, so 90.00 is taxed at 14%.
      final totals = ticket(
        lines: [
          TicketLine(product: product(1, 10000, taxGroupId: 1), quantity: 1),
          TicketLine(product: product(2, 10000, taxGroupId: 2), quantity: 1),
        ],
        discounts: const [
          AppliedDiscount(
            nameSnapshot: 'Manager comp',
            kind: DiscountKind.fixed,
            amount: Money(2000),
            appliedByStaffId: 4,
          ),
        ],
      ).totals;

      final byRate = {for (final l in totals.taxLines) l.rateBp: l};
      expect(byRate[1400]!.base.minor, 9000);
      expect(byRate[0]!.base.minor, 9000);
      expect(totals.vat.minor, 1260);
    });

    test('the bases always sum to the net, whatever the rounding', () {
      // The last line takes the remainder. Apportioning each share
      // independently would leave a piastre untaxed or taxed twice, and a
      // receipt whose parts do not add to its total is one a customer argues
      // with.
      final totals = ticket(
        lines: [
          for (var i = 1; i <= 3; i++)
            TicketLine(product: product(i, 3333, taxGroupId: i), quantity: 1),
        ],
        discounts: const [
          AppliedDiscount(
            nameSnapshot: 'Odd one',
            kind: DiscountKind.fixed,
            amount: Money(1000),
            appliedByStaffId: 4,
          ),
        ],
      ).totals;

      final bases = totals.taxLines.fold(0, (s, l) => s + l.base.minor);
      expect(bases, totals.subtotal.minor - totals.discount.minor);
    });

    test('a discount larger than the goods leaves nothing to tax', () {
      final totals = ticket(
        lines: [TicketLine(product: product(1, 5000), quantity: 1)],
        discounts: const [
          AppliedDiscount(
            nameSnapshot: 'Comped',
            kind: DiscountKind.fixed,
            amount: Money(9000),
            appliedByStaffId: 4,
          ),
        ],
      ).totals;

      expect(totals.vat.minor, 0);
      expect(totals.total.minor, 0);
      // No line at all, rather than one reading "0.00 at 14%".
      expect(totals.taxLines, isEmpty);
    });
  });

  group('TaxEngine', () {
    test('drops a rate with nothing under it', () {
      expect(
        TaxEngine.linesFor({standard: Money.zero}),
        isEmpty,
      );
    });

    test('keeps a zero-rated group with a real base', () {
      final lines = TaxEngine.linesFor({zeroRated: const Money(4000)});
      expect(lines, hasLength(1));
      expect(lines.single.amount.minor, 0);
      expect(lines.single.base.minor, 4000);
    });

    test('groups compare by value, not by identity', () {
      // Two fallbacks built separately must land in the same bucket, or every
      // line is rounded alone.
      const a = TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400);
      final b = TaxGroup(
        id: 0,
        nameEn: 'VAT',
        rateBp: int.parse('1400'),
      );
      expect(a, b);

      // Built at runtime so the analyser cannot fold them: the point is that
      // two *separately constructed* fallbacks land in one bucket.
      final buckets = <TaxGroup, int>{};
      buckets[a] = 1;
      buckets[b] = 2;
      expect(buckets, hasLength(1));
    });
  });
}
