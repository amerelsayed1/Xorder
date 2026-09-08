import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';

/// What the restaurant asked for, and what arrived.
///
/// The rules worth testing are the ones about *when* an order may change. A
/// buyer editing an order that has already gone out is normal operation, and
/// what the model must not allow is editing one whose goods are already in the
/// kitchen — the paper has to keep saying what came.
void main() {
  PurchaseOrderLine line({
    int id = 1,
    String description = 'Chicken',
    int orderedMilli = 12500,
    int receivedMilli = 0,
    int unitCostMinor = 4730,
    int taxRateBp = 0,
    QuantityUnit unit = QuantityUnit.kilogram,
  }) => PurchaseOrderLine(
    id: id,
    description: description,
    ordered: Quantity(orderedMilli, unit: unit),
    received: Quantity(receivedMilli, unit: unit),
    unitCost: Money(unitCostMinor),
    taxRateBp: taxRateBp,
  );

  PurchaseOrder order({
    PurchaseStatus status = PurchaseStatus.draft,
    List<PurchaseOrderLine>? lines,
  }) => PurchaseOrder(
    id: 1,
    supplierId: 1,
    reference: 'PO-2026-000001',
    status: status,
    lines: lines ?? [line()],
  );

  group('what a line costs', () {
    test('a fractional quantity rounds once', () {
      // 12.5 kg at 47.30 is 591.25 exactly.
      expect(line().lineTotal.minor, 59125);
    });

    test('tax is a share of the line, rounded once', () {
      expect(line(taxRateBp: 1400).lineTax.minor, 8278);
    });

    test('a line with no tax has none', () {
      expect(line().lineTax.minor, 0);
    });
  });

  group('what the order comes to', () {
    test('lines sum', () {
      final totals = order(
        lines: [line(orderedMilli: 2000, unitCostMinor: 5000),
                line(id: 2, orderedMilli: 1000, unitCostMinor: 3000)],
      ).totals;

      expect(totals.subtotal.minor, 10000 + 3000);
      expect(totals.total.minor, 13000);
    });

    test('tax rounds per rate, not per line', () {
      // Three lines of 33.33 at 14% round to 4.67 apiece and sum to 14.01;
      // the same 99.99 taxed once gives 14.00. A return is filed by rate, so
      // per-rate is what it has to be — the same rule the ticket uses.
      final totals = order(
        lines: [
          for (var i = 1; i <= 3; i++)
            line(id: i, orderedMilli: 1000, unitCostMinor: 3333, taxRateBp: 1400),
        ],
      ).totals;

      expect(totals.subtotal.minor, 9999);
      expect(totals.tax.minor, 1400, reason: 'not 1401');
    });

    test('two rates are two roundings', () {
      final totals = order(
        lines: [
          line(orderedMilli: 1000, unitCostMinor: 10000, taxRateBp: 1400),
          line(id: 2, orderedMilli: 1000, unitCostMinor: 10000, taxRateBp: 500),
        ],
      ).totals;

      expect(totals.tax.minor, 1400 + 500);
    });

    test('an empty order comes to nothing', () {
      final totals = order(lines: []).totals;
      expect(totals.total.minor, 0);
    });
  });

  group('what arrived', () {
    test('nothing yet leaves everything outstanding', () {
      expect(line().outstanding.milli, 12500);
      expect(line().isFullyReceived, isFalse);
    });

    test('a part delivery leaves the rest owed', () {
      final partial = line(receivedMilli: 8000);
      expect(partial.outstanding.milli, 4500);
      expect(partial.isFullyReceived, isFalse);
    });

    test('a full delivery owes nothing', () {
      expect(line(receivedMilli: 12500).isFullyReceived, isTrue);
      expect(line(receivedMilli: 12500).outstanding.milli, 0);
    });

    test('over-delivery is not a debt the supplier owes back', () {
      // Suppliers round up to a full crate. It closes at zero rather than
      // going negative.
      final over = line(receivedMilli: 13000);
      expect(over.outstanding.milli, 0);
      expect(over.isOverReceived, isTrue);
      expect(over.isFullyReceived, isTrue);
    });

    test('the received value is what the invoice should match, not the order',
        () {
      // The moment anything is short these differ, and it is this number a
      // supplier's invoice is checked against.
      final short = order(
        status: PurchaseStatus.partiallyReceived,
        lines: [line(orderedMilli: 12500, receivedMilli: 8000)],
      );
      expect(short.totals.subtotal.minor, 59125);
      expect(short.receivedValue.minor, 37840, reason: '8 kg at 47.30');
    });
  });

  group('the status follows the lines, it is not set', () {
    test('nothing received stays sent', () {
      expect(
        order(status: PurchaseStatus.sent).statusFromReceipts,
        PurchaseStatus.sent,
      );
    });

    test('some received is partial', () {
      final partial = order(
        status: PurchaseStatus.sent,
        lines: [line(receivedMilli: 8000)],
      );
      expect(partial.statusFromReceipts, PurchaseStatus.partiallyReceived);
    });

    test('all received is received', () {
      final done = order(
        status: PurchaseStatus.sent,
        lines: [line(receivedMilli: 12500)],
      );
      expect(done.statusFromReceipts, PurchaseStatus.received);
    });

    test('one line short keeps the whole order open', () {
      final mixed = order(
        status: PurchaseStatus.sent,
        lines: [
          line(receivedMilli: 12500),
          line(id: 2, orderedMilli: 5000, receivedMilli: 1000),
        ],
      );
      expect(mixed.statusFromReceipts, PurchaseStatus.partiallyReceived);
    });

    test('a cancelled order stays cancelled whatever the lines say', () {
      final cancelled = order(
        status: PurchaseStatus.cancelled,
        lines: [line(receivedMilli: 12500)],
      );
      expect(cancelled.statusFromReceipts, PurchaseStatus.cancelled);
    });

    test('a draft stays a draft', () {
      expect(order().statusFromReceipts, PurchaseStatus.draft);
    });
  });

  group('editing', () {
    test('a draft takes lines', () {
      final result = PurchaseEngine.addLine(order(lines: []), line());
      expect(result.succeeded, isTrue);
      expect(result.order!.lines, hasLength(1));
    });

    test('a sent order does not', () {
      // It has gone to the supplier. Changing what it says here would leave
      // the restaurant and the supplier holding different pieces of paper.
      final result = PurchaseEngine.addLine(
        order(status: PurchaseStatus.sent),
        line(id: 2),
      );
      expect(result.refusal, isA<OrderNotEditable>());
      expect(
        (result.refusal! as OrderNotEditable).status,
        PurchaseStatus.sent,
      );
    });

    test('a line of nothing is refused', () {
      final result = PurchaseEngine.addLine(
        order(lines: []),
        line(orderedMilli: 0),
      );
      expect(result.refusal, isA<LineQuantityNotPositive>());
    });
  });

  group('sending', () {
    test('stamps when it went', () {
      final at = DateTime.utc(2026, 9, 9, 8);
      final result = PurchaseEngine.send(order(), at: at);

      expect(result.order!.status, PurchaseStatus.sent);
      expect(result.order!.orderedAt, at);
    });

    test('an empty order is refused — there is nothing to ask for', () {
      final result = PurchaseEngine.send(order(lines: []), at: DateTime.utc(2026));
      expect(result.refusal, isA<OrderHasNoLines>());
    });

    test('sending twice is refused', () {
      final result = PurchaseEngine.send(
        order(status: PurchaseStatus.sent),
        at: DateTime.utc(2026),
      );
      expect(result.refusal, isA<OrderNotEditable>());
    });
  });

  group('cancelling', () {
    test('a draft can be called off', () {
      expect(
        PurchaseEngine.cancel(order()).order!.status,
        PurchaseStatus.cancelled,
      );
    });

    test('so can a sent order that nothing has arrived for', () {
      expect(
        PurchaseEngine.cancel(order(status: PurchaseStatus.sent)).order!.status,
        PurchaseStatus.cancelled,
      );
    });

    test('but not once goods are in the kitchen', () {
      // The way out of a part delivery is to close the difference, not to
      // pretend the order never happened.
      final result = PurchaseEngine.cancel(
        order(status: PurchaseStatus.partiallyReceived),
      );
      expect(result.refusal, isA<OrderAlreadyClosed>());
    });

    test('and not twice', () {
      final result = PurchaseEngine.cancel(
        order(status: PurchaseStatus.cancelled),
      );
      expect(result.refusal, isA<OrderAlreadyClosed>());
    });
  });

  group('status', () {
    test('only a draft is editable', () {
      expect(PurchaseStatus.draft.isEditable, isTrue);
      for (final s in PurchaseStatus.values.where((s) => s != PurchaseStatus.draft)) {
        expect(s.isEditable, isFalse, reason: s.wire);
      }
    });

    test('sent and partial are open for receiving', () {
      expect(PurchaseStatus.sent.isOpen, isTrue);
      expect(PurchaseStatus.partiallyReceived.isOpen, isTrue);
      expect(PurchaseStatus.draft.isOpen, isFalse);
      expect(PurchaseStatus.received.isOpen, isFalse);
    });

    test('an unknown status throws rather than being guessed at', () {
      // Reading it as `received` would close an order nothing arrived for.
      expect(() => PurchaseStatus.fromWire('invoiced'), throwsArgumentError);
      expect(PurchaseStatus.fromWire('sent'), PurchaseStatus.sent);
    });
  });
}
