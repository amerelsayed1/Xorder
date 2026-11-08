import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/discount.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

/// Cancelling a line and voiding one are **not the same act**, and everything
/// here exists to keep them apart.
///
/// Removing something the kitchen has not seen is housekeeping: nothing was
/// made, nothing was wasted, the line leaves. Once it has been fired, removing
/// it is waste with a cost — the line stays, marked, and stops being charged
/// for. A system that recorded both as "line gone" could never afterwards be
/// asked which happened, and that is the first question a month-end review
/// asks.
void main() {
  final now = DateTime(2026, 9, 8, 12);

  Product product(int priceMinor, {int id = 1}) => Product(
    id: id,
    categoryId: 1,
    nameEn: 'Item $id',
    price: Money(priceMinor),
  );

  TicketLine draft(Product p, {int quantity = 1}) =>
      TicketLine(product: p, quantity: quantity);

  TicketLine sent(Product p, {int quantity = 1}) => TicketLine(
    product: p,
    quantity: quantity,
    stage: LineStage.sent,
    roundNumber: 1,
  );

  Ticket ticket(List<TicketLine> lines) => Ticket(
    id: 't',
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    lines: lines,
  );

  Ticket ok(TicketResult result) {
    expect(result.refusal, isNull, reason: 'expected this to be allowed');
    return result.ticket!;
  }

  group('cancelling an unsent line', () {
    test('takes it off the ticket entirely', () {
      final t = ok(
        TicketEngine.cancelLine(
          ticket([draft(product(10000)), draft(product(2500, id: 2))]),
          '1:',
          by: 4,
          now: now,
        ),
      );

      expect(t.lines, hasLength(1));
      expect(t.lines.single.product.id, 2);
      expect(t.totals.subtotal.minor, 2500);
    });

    test('records that it was removed before the kitchen saw it', () {
      final t = ok(
        TicketEngine.cancelLine(
          ticket([draft(product(10000), quantity: 3)]),
          '1:',
          by: 4,
          now: now,
        ),
      );

      final event = t.lineEvents.single;
      expect(event.event, TicketLineEventKind.removedBeforeSend);
      expect(event.lineKey, '1:');
      expect(event.staffId, 4);
      expect(event.quantityBefore, 3);
      expect(event.quantityAfter, 0);
    });

    test('a discount on it goes with it', () {
      var t = ticket([draft(product(10000))]);
      t = ok(
        TicketEngine.applyCustomDiscount(
          t,
          name: 'Ten off',
          kind: DiscountKind.fixed,
          appliedBy: 4,
          valueMinor: const Money(1000),
          lineKey: '1:',
        ),
      );
      expect(t.discounts, hasLength(1));

      t = ok(TicketEngine.cancelLine(t, '1:', by: 4, now: now));

      // Money off a line nobody is being charged for is money off nothing.
      expect(t.discounts, isEmpty);
      expect(t.totals.discount.isZero, isTrue);
    });

    test('refuses a line the kitchen already has', () {
      final result = TicketEngine.cancelLine(
        ticket([sent(product(10000))]),
        '1:',
        by: 4,
        now: now,
      );

      // Silently upgrading it to a void would record waste as housekeeping.
      expect(result.refusal, isA<WrongStageForAct>());
    });

    test('refuses a line that is not there', () {
      final result = TicketEngine.cancelLine(
        ticket([draft(product(10000))]),
        '99:',
        by: 4,
        now: now,
      );
      expect(result.refusal, isA<LineNotOnTicket>());
    });
  });

  group('voiding a sent line', () {
    test('the line stays on the ticket', () {
      final t = ok(
        TicketEngine.voidLine(
          ticket([sent(product(10000))]),
          '1:',
          by: 4,
          now: now,
          reasonId: 2,
        ),
      );

      // Removing it would leave the cashier unable to show a customer what
      // happened, and the kitchen ticket and the bill describing different
      // meals.
      expect(t.lines, hasLength(1));
      expect(t.lines.single.isVoided, isTrue);
    });

    test('and stops being charged for', () {
      final t = ok(
        TicketEngine.voidLine(
          ticket([sent(product(10000)), sent(product(2500, id: 2))]),
          '1:',
          by: 4,
          now: now,
        ),
      );

      expect(t.totals.subtotal.minor, 2500);
      expect(t.totals.total.minor, 2500);
      expect(t.chargeableLines, hasLength(1));
    });

    test('records who, when and why', () {
      final t = ok(
        TicketEngine.voidLine(
          ticket([sent(product(10000), quantity: 2)]),
          '1:',
          by: 4,
          now: now,
          reasonId: 3,
          note: 'Dropped by the runner',
        ),
      );

      final voided = t.lines.single.voided!;
      expect(voided.byStaffId, 4);
      expect(voided.at, now);
      expect(voided.reasonId, 3);
      expect(voided.note, 'Dropped by the runner');

      final event = t.lineEvents.single;
      expect(event.event, TicketLineEventKind.voidedAfterSend);
      expect(event.quantityBefore, 2);
      expect(event.quantityAfter, 0);
      expect(event.reasonId, 3);
    });

    test('carries the supervisor who approved it', () {
      final t = ok(
        TicketEngine.voidLine(
          ticket([sent(product(10000))]),
          '1:',
          by: 4,
          now: now,
          reasonId: 3,
          approvedByStaffId: 9,
          approvedByName: 'Hana Mostafa',
        ),
      );

      expect(t.lines.single.voided!.approvedByName, 'Hana Mostafa');
      expect(t.lines.single.voided!.approvedByStaffId, 9);
      expect(t.lineEvents.single.approvedByStaffId, 9);
    });

    test('a discount on it stops counting too', () {
      var t = ticket([sent(product(10000))]);
      t = ok(
        TicketEngine.applyCustomDiscount(
          t,
          name: 'Ten off',
          kind: DiscountKind.fixed,
          appliedBy: 4,
          valueMinor: const Money(1000),
          lineKey: '1:',
        ),
      );
      expect(t.totals.discount.minor, 1000);

      t = ok(TicketEngine.voidLine(t, '1:', by: 4, now: now));

      // The discount record stays — it happened — but it credits nothing,
      // because the line it came off is no longer being charged for.
      expect(t.discounts, hasLength(1));
      expect(t.totals.discount.isZero, isTrue);
      expect(t.totals.total.isZero, isTrue);
    });

    test('refuses a line the kitchen has not seen', () {
      final result = TicketEngine.voidLine(
        ticket([draft(product(10000))]),
        '1:',
        by: 4,
        now: now,
      );
      expect(result.refusal, isA<WrongStageForAct>());
    });

    test('refuses to void the same line twice', () {
      var t = ticket([sent(product(10000))]);
      t = ok(TicketEngine.voidLine(t, '1:', by: 4, now: now));

      final second = TicketEngine.voidLine(t, '1:', by: 4, now: now);
      expect(second.refusal, isA<AlreadyVoided>());
      // And exactly one event, not two.
      expect(t.lineEvents, hasLength(1));
    });
  });

  group('a ticket of nothing but voided lines', () {
    test('is not empty, but there is nothing to charge', () {
      var t = ticket([sent(product(10000))]);
      t = ok(TicketEngine.voidLine(t, '1:', by: 4, now: now));

      // Not empty: it is a record of a meal that was made and thrown away, and
      // that record is the whole reason voiding exists.
      expect(t.isEmpty, isFalse);
      expect(t.hasNothingToCharge, isTrue);
      expect(t.totals.total.isZero, isTrue);
    });

    test('has no draft left to send', () {
      var t = ticket([draft(product(10000)), sent(product(2500, id: 2))]);
      t = ok(TicketEngine.voidLine(t, '2:', by: 4, now: now));
      expect(t.hasDraft, isTrue);

      t = ok(TicketEngine.cancelLine(t, '1:', by: 4, now: now));
      expect(t.hasDraft, isFalse);
    });
  });

  group('events accumulate', () {
    test('in the order the acts happened', () {
      var t = ticket([
        draft(product(10000, id: 1)),
        sent(product(2500, id: 2)),
      ]);

      t = ok(TicketEngine.cancelLine(t, '1:', by: 4, now: now));
      t = ok(
        TicketEngine.voidLine(
          t,
          '2:',
          by: 4,
          now: now.add(const Duration(minutes: 1)),
          reasonId: 1,
        ),
      );

      expect(t.lineEvents.map((e) => e.event), [
        TicketLineEventKind.removedBeforeSend,
        TicketLineEventKind.voidedAfterSend,
      ]);
    });
  });
}
