import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

const _doneness = ModifierGroup(
  id: 1,
  nameEn: 'Doneness',
  isRequired: true,
  modifiers: [
    Modifier(id: 11, groupId: 1, nameEn: 'Medium', priceDelta: Money.zero),
    Modifier(id: 12, groupId: 1, nameEn: 'Well done', priceDelta: Money.zero),
  ],
);

const _extras = ModifierGroup(
  id: 2,
  nameEn: 'Extras',
  maxSelect: 2,
  modifiers: [
    Modifier(id: 21, groupId: 2, nameEn: 'Tahina', priceDelta: Money(1500)),
    Modifier(id: 22, groupId: 2, nameEn: 'Bread', priceDelta: Money(1000)),
    Modifier(id: 23, groupId: 2, nameEn: 'Rice', priceDelta: Money(2500)),
  ],
);

const _grill = Product(
  id: 101,
  categoryId: 1,
  nameEn: 'Mixed Grill',
  price: Money(38500),
  modifierGroupIds: [1, 2],
);

const _drink = Product(id: 501, categoryId: 5, nameEn: 'Soft Drink', price: Money(2500));

const _soldOut = Product(
  id: 104,
  categoryId: 1,
  nameEn: 'Lamb Chops',
  price: Money(52000),
  isAvailable: false,
);

Ticket _ticket({OrderType type = OrderType.dineIn, int? tableId = 12}) => Ticket(
      id: 'fixed-client-transaction-id',
      orderType: type,
      tableId: type == OrderType.dineIn ? tableId : null,
      tableLabel: type == OrderType.dineIn && tableId != null ? 'T12' : null,
    );

void main() {
  _orderTypeSynonyms();
  group('adding lines', () {
    test('adds a plain product straight to the ticket', () {
      final result = TicketEngine.addLine(_ticket(), _drink);

      expect(result.isOk, isTrue);
      expect(result.ticket!.lines.single.quantity, 1);
    });

    test('refuses an out-of-stock product', () {
      final result = TicketEngine.addLine(_ticket(), _soldOut);

      expect(result.isOk, isFalse);
      expect(result.refusal, isA<OutOfStock>());
    });

    test('refuses when a required group has no selection', () {
      final result = TicketEngine.addLine(
        _ticket(),
        _grill,
        groups: const [_doneness, _extras],
      );

      expect(result.isOk, isFalse);
      expect(result.refusal, isA<RequiredGroupUnsatisfied>());
    });

    test('refuses more selections than the group allows', () {
      final result = TicketEngine.addLine(
        _ticket(),
        _grill,
        groups: const [_extras],
        modifiers: _extras.modifiers, // three, cap is two
      );

      expect(result.refusal, isA<TooManySelected>());
    });
  });

  group('line merging', () {
    test('merges identical product + modifiers into one line', () {
      var ticket = _ticket();
      ticket = TicketEngine.addLine(ticket, _drink).ticket!;
      ticket = TicketEngine.addLine(ticket, _drink).ticket!;

      expect(ticket.lines, hasLength(1));
      expect(ticket.lines.single.quantity, 2);
    });

    test('merges regardless of the order modifiers were picked in', () {
      final forward = [_extras.modifiers[0], _extras.modifiers[1]];
      final reversed = [_extras.modifiers[1], _extras.modifiers[0]];

      var ticket = _ticket();
      ticket = TicketEngine.addLine(ticket, _grill,
              groups: const [_extras], modifiers: forward)
          .ticket!;
      ticket = TicketEngine.addLine(ticket, _grill,
              groups: const [_extras], modifiers: reversed)
          .ticket!;

      expect(ticket.lines, hasLength(1), reason: 'the line key sorts modifier ids');
      expect(ticket.lines.single.quantity, 2);
    });

    test('keeps different modifier sets as separate lines', () {
      var ticket = _ticket();
      ticket = TicketEngine.addLine(ticket, _grill,
              groups: const [_extras], modifiers: [_extras.modifiers[0]])
          .ticket!;
      ticket = TicketEngine.addLine(ticket, _grill,
              groups: const [_extras], modifiers: [_extras.modifiers[1]])
          .ticket!;

      expect(ticket.lines, hasLength(2));
    });

    test('never merges into a line already sent to the kitchen', () {
      var ticket = _ticket();
      ticket = TicketEngine.addLine(ticket, _drink).ticket!;
      ticket = TicketEngine.sendRound(ticket);
      ticket = TicketEngine.addLine(ticket, _drink).ticket!;

      expect(ticket.lines, hasLength(2));
      expect(ticket.sentLines.single.quantity, 1);
      expect(ticket.draftLines.single.quantity, 1);
    });
  });

  group('quantity', () {
    test('removes the line when the quantity reaches zero', () {
      var ticket = TicketEngine.addLine(_ticket(), _drink).ticket!;
      final key = ticket.lines.single.key;

      ticket = TicketEngine.changeQuantity(ticket, key, -1);
      expect(ticket.lines, isEmpty);
    });

    test('will not change a sent line', () {
      var ticket = TicketEngine.addLine(_ticket(), _drink).ticket!;
      ticket = TicketEngine.sendRound(ticket);
      final key = ticket.lines.single.key;

      ticket = TicketEngine.changeQuantity(ticket, key, 5);
      expect(ticket.lines.single.quantity, 1);
    });
  });

  group('rounds', () {
    test('sendRound moves draft to sent and stamps the round number', () {
      var ticket = TicketEngine.addLine(_ticket(), _drink).ticket!;
      ticket = TicketEngine.sendRound(ticket);

      expect(ticket.roundsSent, 1);
      expect(ticket.sentLines.single.roundNumber, 1);
      expect(ticket.hasDraft, isFalse);
    });

    test('sending an empty draft is a no-op', () {
      final ticket = TicketEngine.sendRound(_ticket());
      expect(ticket.roundsSent, 0);
    });
  });

  group('order type', () {
    test('leaving dine-in detaches the table — a bill never follows a switch', () {
      final ticket = TicketEngine.setOrderType(_ticket(), OrderType.takeaway);

      expect(ticket.tableId, isNull);
      expect(ticket.tableLabel, isNull);
      expect(ticket.isSeated, isFalse);
    });

    test('staying on dine-in keeps the table', () {
      final ticket = TicketEngine.setOrderType(_ticket(), OrderType.dineIn);
      expect(ticket.tableId, 12);
    });
  });

  group('totals', () {
    test('applies service to dine-in and VAT on subtotal + service', () {
      // 385.00 subtotal · service 12% = 46.20 · VAT 14% of 431.20 = 60.368 → 60.37
      var ticket = _ticket();
      ticket = TicketEngine.addLine(ticket, _grill,
              groups: const [_doneness], modifiers: [_doneness.modifiers.first])
          .ticket!;

      final totals = ticket.totals;
      expect(totals.subtotal.minor, 38500);
      expect(totals.service.minor, 4620);
      expect(totals.vat.minor, 6037);
      expect(totals.total.minor, 49157);
    });

    test('omits service on takeaway', () {
      var ticket = _ticket(type: OrderType.takeaway);
      ticket = TicketEngine.addLine(ticket, _grill,
              groups: const [_doneness], modifiers: [_doneness.modifiers.first])
          .ticket!;

      final totals = ticket.totals;
      expect(totals.service.minor, 0);
      expect(totals.vat.minor, 5390); // 14% of 385.00
      expect(totals.total.minor, 43890);
    });

    test('counts modifier deltas into the line total', () {
      var ticket = _ticket();
      ticket = TicketEngine.addLine(
        ticket,
        _grill,
        groups: const [_doneness, _extras],
        modifiers: [_doneness.modifiers.first, _extras.modifiers.first],
        quantity: 2,
      ).ticket!;

      // (385.00 + 15.00) × 2
      expect(ticket.totals.subtotal.minor, 80000);
    });
  });

  group('tenders', () {
    Ticket seeded() {
      var ticket = _ticket(type: OrderType.takeaway);
      ticket = TicketEngine.addLine(ticket, _drink).ticket!; // 25.00
      return ticket;
    }

    test('a null amount tenders the whole remaining due', () {
      final ticket = seeded();
      final result = TicketEngine.addTender(ticket, typeId: 1, label: 'Cash');

      expect(result.isOk, isTrue);
      expect(result.ticket!.totals.isSettled, isTrue);
      expect(result.ticket!.totals.due.isZero, isTrue);
    });

    test('split payment leaves the balance owing until it clears', () {
      var ticket = seeded();
      final total = ticket.totals.total;

      ticket = TicketEngine.addTender(
        ticket,
        typeId: 1,
        label: 'Cash',
        amount: const Money(1000),
      ).ticket!;

      expect(ticket.totals.isSettled, isFalse);
      expect(ticket.totals.due.minor, total.minor - 1000);

      ticket = TicketEngine.addTender(ticket, typeId: 2, label: 'Card').ticket!;
      expect(ticket.totals.isSettled, isTrue);
      expect(ticket.tenders, hasLength(2));
    });

    test('overpayment produces change, never a negative due', () {
      var ticket = seeded();
      ticket = TicketEngine.addTender(
        ticket,
        typeId: 1,
        label: 'Cash',
        amount: const Money(10000),
      ).ticket!;

      expect(ticket.totals.due.minor, 0);
      expect(ticket.totals.change.minor, 10000 - ticket.totals.total.minor);
    });

    test('refuses a zero tender', () {
      final result = TicketEngine.addTender(
        seeded(),
        typeId: 1,
        label: 'Cash',
        amount: Money.zero,
      );

      expect(result.refusal, isA<ZeroTender>());
    });

    test('refuses to tender against an empty ticket', () {
      final result = TicketEngine.addTender(_ticket(), typeId: 1, label: 'Cash');
      expect(result.refusal, isA<NothingToTender>());
    });

    // Taking a payment back off the bill. It had no key and no check at all —
    // the act a card-for-cash swap is made of — so the engine asks now, not
    // only the payment screen.
    PosStaff on(String code, {int id = 1}) => PosStaff(
      id: id,
      name: code,
      role: PosRole(
        id: id,
        code: code,
        nameEn: code,
        capabilities: SystemRoles.seeded[code]!.capabilities,
      ),
    );

    Ticket paidByCard() => TicketEngine.addTender(
      seeded(),
      typeId: 2,
      label: 'Card',
    ).ticket!;

    test('a cashier cannot take a payment off on their own', () {
      final result = TicketEngine.removeTenderAt(
        paidByCard(),
        0,
        by: on(SystemRoles.cashierCode),
      );
      expect(result.refusal, isA<NotPermittedHere>());
    });

    test('a supervisor can', () {
      final result = TicketEngine.removeTenderAt(
        paidByCard(),
        0,
        by: on(SystemRoles.supervisorCode),
      );
      expect(result.ticket!.tenders, isEmpty);
    });

    test('a cashier can on a supervisor\'s approval for this ticket — once', () {
      final ticket = paidByCard();
      final approval = (Authorization.approve(
        approver: on(SystemRoles.supervisorCode, id: 2),
        capability: PosCapability.paymentRemove,
        subject: ticket.id,
      ) as Allowed).approval!;
      final cashier = on(SystemRoles.cashierCode);

      final first = TicketEngine.removeTenderAt(
        ticket,
        0,
        by: cashier,
        approval: approval,
      );
      expect(first.ticket!.tenders, isEmpty);

      final again = TicketEngine.removeTenderAt(
        ticket,
        0,
        by: cashier,
        approval: approval,
      );
      expect(again.refusal, isA<NotPermittedHere>());
    });
  });

  group('modifier toggling', () {
    test('a single-select group replaces rather than accumulates', () {
      var selected = <Modifier>[];
      selected = TicketEngine.toggleModifier(selected, _doneness, _doneness.modifiers[0]);
      selected = TicketEngine.toggleModifier(selected, _doneness, _doneness.modifiers[1]);

      expect(selected, hasLength(1));
      expect(selected.single.id, 12);
    });

    test('tapping a selected option deselects it', () {
      var selected = <Modifier>[];
      selected = TicketEngine.toggleModifier(selected, _extras, _extras.modifiers[0]);
      selected = TicketEngine.toggleModifier(selected, _extras, _extras.modifiers[0]);

      expect(selected, isEmpty);
    });

    test('a multi-select group stops at the cap and reports it by not changing', () {
      var selected = <Modifier>[];
      selected = TicketEngine.toggleModifier(selected, _extras, _extras.modifiers[0]);
      selected = TicketEngine.toggleModifier(selected, _extras, _extras.modifiers[1]);
      final atCap = selected;

      selected = TicketEngine.toggleModifier(selected, _extras, _extras.modifiers[2]);
      expect(identical(selected, atCap), isTrue, reason: 'caller shows the toast');
    });
  });

  group('clear', () {
    test('mints a new client transaction id so the next sale is not a replay', () {
      final ticket = TicketEngine.addLine(_ticket(), _drink).ticket!;
      final next = TicketEngine.clear(ticket, newId: 'a-new-id');

      expect(next.id, 'a-new-id');
      expect(next.lines, isEmpty);
      expect(next.tenders, isEmpty);
      expect(next.orderType, ticket.orderType);
    });
  });
}

void _orderTypeSynonyms() {
  group('order type vocabulary', () {
    test('pickup is takeaway by another name', () {
      // The onboarding wizard and the plan features say `pickup`; the POS
      // says `takeaway`. A branch onboarded through the wizard must not lose
      // its takeaway tab because two screens disagree about a word.
      expect(OrderType.fromWire('pickup'), OrderType.takeaway);
      expect(OrderType.fromWire('takeaway'), OrderType.takeaway);
      expect(OrderType.fromWire('dine_in'), OrderType.dineIn);
      expect(OrderType.fromWire('drive_thru'), OrderType.driveThru);
    });

    test('a word neither vocabulary knows is still null, never a throw', () {
      expect(OrderType.fromWire('teleportation'), isNull);
      expect(OrderType.fromWire(''), isNull);
    });
  });
}
