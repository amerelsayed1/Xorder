import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/branch_sales.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

/// Payment methods as data (§40), in the pure half.
///
/// The rule with teeth is that what counts as cash travels **with the money**.
/// Everything else here is naming, and naming matters for one reason: a
/// business that renames its own payment method should see the name it typed,
/// not the one the product shipped with.
void main() {
  const product = Product(
    id: 1,
    categoryId: 1,
    nameEn: 'Thing',
    price: Money(10000),
  );

  Ticket ticket() => TicketEngine.addLine(
    Ticket(id: 'txn-1', orderType: OrderType.takeaway),
    product,
  ).ticket!;

  group('the cash flag travels with the money', () {
    test('a cash tender carries it', () {
      final settled = TicketEngine.addTender(
        ticket(),
        typeId: 1,
        label: 'Cash',
        countsAsCash: true,
      ).ticket!;
      expect(settled.tenders.single.countsAsCash, isTrue);
    });

    test('a card tender does not', () {
      final settled = TicketEngine.addTender(
        ticket(),
        typeId: 2,
        label: 'Card',
      ).ticket!;
      expect(settled.tenders.single.countsAsCash, isFalse);
    });

    test('the engine does not decide it', () {
      // What counts as cash is a property of the method the cashier chose. An
      // engine that worked it out from the id would be an engine that has to
      // know the business's configuration — and would get the answer wrong
      // the moment somebody added a fifth method.
      final settled = TicketEngine.addTender(
        ticket(),
        typeId: 1,
        label: 'Cash',
        countsAsCash: false,
      ).ticket!;
      expect(
        settled.tenders.single.countsAsCash,
        isFalse,
        reason: 'the caller said no, and the caller is holding the method',
      );
    });

    test('it defaults to false, which is the safe direction', () {
      // An unknown method counted as cash manufactures a variance nobody can
      // explain. One counted as non-cash understates the drawer, which the
      // count itself then surfaces.
      final settled = TicketEngine.addTender(
        ticket(),
        typeId: 99,
        label: 'Something new',
      ).ticket!;
      expect(settled.tenders.single.countsAsCash, isFalse);
    });
  });

  group('the seeded four', () {
    test('are what a business starts with, once', () {
      expect(TenderMethod.seeded.map((t) => t.code), [
        'cash',
        'card',
        'wallet',
        'account',
      ]);
    });

    test('only cash counts as cash and opens the drawer', () {
      expect(
        TenderMethod.seeded.where((t) => t.countsAsCash).map((t) => t.code),
        ['cash'],
      );
      expect(
        TenderMethod.seeded.where((t) => t.opensDrawer).map((t) => t.code),
        ['cash'],
      );
    });

    test('the two that clear through somebody else want a reference', () {
      expect(
        TenderMethod.seeded
            .where((t) => t.requiresReference)
            .map((t) => t.code),
        ['card', 'wallet'],
      );
    });

    test('every one has a distinct code and id', () {
      expect(TenderMethod.seeded.map((t) => t.code).toSet(), hasLength(4));
      expect(TenderMethod.seeded.map((t) => t.id).toSet(), hasLength(4));
    });

    test('the wire label is the English name, whatever the till speaks', () {
      // It is a value on a stored row: a receipt reprinted in another language
      // still has to say what was taken.
      final cash = TenderMethod.seeded.first;
      expect(cash.wireLabel, 'Cash');
      expect(cash.displayName('ar'), 'نقدي');
      expect(cash.displayName('en'), 'Cash');
    });

    test('a method with no Arabic name falls back rather than blanking', () {
      const method = TenderMethod(id: 9, code: 'x', nameEn: 'Voucher');
      expect(method.displayName('ar'), 'Voucher');
    });
  });

  group('kinds', () {
    test('an unknown kind is takeable, not fatal', () {
      // A till on an older build must not refuse to sell because somebody
      // added a payment method in the back office.
      expect(TenderKind.fromWire('crypto'), TenderKind.other);
      expect(TenderKind.fromWire(null), TenderKind.other);
    });

    test('the ones that exist round-trip', () {
      for (final kind in TenderKind.values) {
        expect(TenderKind.fromWire(kind.wire), kind);
      }
    });
  });

  group('what the platform calls them (POS-BE-013)', () {
    test('each lands on the till kind that reconciles it right', () {
      expect(PlatformTenderKind.cash.tillKind, TenderKind.cash);
      expect(PlatformTenderKind.card.tillKind, TenderKind.card);
      expect(PlatformTenderKind.external.tillKind, TenderKind.card);
      expect(PlatformTenderKind.other.tillKind, TenderKind.other);
    });

    test('a card on the bank\'s own terminal is electronic takings', () {
      // The reason `external` is not `other`: the manager checks electronic
      // against the bank terminal's settlement slip.
      expect(
        PaymentBucket.of(
          kind: PlatformTenderKind.external.tillKind,
          countsAsCash: false,
        ),
        PaymentBucket.electronic,
      );
    });

    test('a kind this build has not heard of is unknown, never a throw', () {
      expect(PlatformTenderKind.fromWire('crypto'), isNull);
      expect(PlatformTenderKind.fromWire(null), isNull);
      for (final kind in PlatformTenderKind.values) {
        expect(PlatformTenderKind.fromWire(kind.wire), kind);
      }
    });

    test('the compiled-in four sit at or under the platform floor', () {
      // Migration 41's CHECK keeps platform rows above this number. A fifth
      // seeded method above it would be a fallback payment that could share
      // an id with a platform tender — the collision the ceiling exists for.
      expect(
        TenderMethod.seeded.every(
          (t) => t.id <= TenderMethod.seededIdCeiling,
        ),
        isTrue,
      );
    });
  });
}
