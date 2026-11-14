import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/dining_table.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/floor_overlay.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

Product _tea() =>
    const Product(id: 7, categoryId: 1, nameEn: 'Tea', price: Money(2500));

final _seven = DateTime(2026, 11, 8, 19, 0);

DiningTable _busy({
  DateTime? seatedAt,
  DateTime? lastSentAt,
  bool draft = false,
  TableState state = TableState.open,
}) => DiningTable(
  id: 1,
  label: 'T1',
  seats: 4,
  state: state,
  seatedAt: seatedAt,
  lastSentAt: lastSentAt,
  hasUnsentDraft: draft,
);

void main() {
  group('attentionFor', () {
    test('a free table never needs attention', () {
      const free = DiningTable(id: 1, label: 'T1', seats: 2);
      expect(attentionFor(free, _seven), TableAttention.none);
    });

    test('a fresh table is fine', () {
      final table = _busy(seatedAt: _seven, draft: true);
      expect(
        attentionFor(table, _seven.add(const Duration(minutes: 1))),
        TableAttention.none,
      );
    });

    test('a draft never fired becomes an unsent round', () {
      final table = _busy(seatedAt: _seven, draft: true);
      expect(
        attentionFor(table, _seven.add(const Duration(minutes: 4))),
        TableAttention.unsentRound,
      );
    });

    test('a fired table with a new draft is not "unsent"', () {
      // The kitchen has heard from them; the second round waiting on the
      // cashier is ordinary. It becomes quiet on the quiet clock instead.
      final table = _busy(
        seatedAt: _seven,
        lastSentAt: _seven.add(const Duration(minutes: 2)),
        draft: true,
      );
      expect(
        attentionFor(table, _seven.add(const Duration(minutes: 10))),
        TableAttention.none,
      );
    });

    test('no round for 25 minutes reads as quiet', () {
      final table = _busy(seatedAt: _seven, lastSentAt: _seven);
      expect(
        attentionFor(table, _seven.add(const Duration(minutes: 24))),
        TableAttention.none,
      );
      expect(
        attentionFor(table, _seven.add(const Duration(minutes: 25))),
        TableAttention.quiet,
      );
    });

    test('a bill asked and unpaid past the limit is waiting', () {
      final table = _busy(
        seatedAt: _seven,
        lastSentAt: _seven,
        state: TableState.billAsked,
      );
      expect(
        attentionFor(table, _seven.add(const Duration(minutes: 5))),
        TableAttention.none,
      );
      expect(
        attentionFor(table, _seven.add(const Duration(minutes: 8))),
        TableAttention.billWaiting,
      );
    });

    test('a bill asked is never "quiet" — the bill outranks the kitchen', () {
      final table = _busy(
        seatedAt: _seven,
        lastSentAt: _seven,
        state: TableState.billAsked,
      );
      expect(
        attentionFor(table, _seven.add(const Duration(hours: 1))),
        TableAttention.billWaiting,
      );
    });

    test('thresholds are the rules object, not constants in code', () {
      final table = _busy(seatedAt: _seven, lastSentAt: _seven);
      const cafe = FloorAttentionRules(quietAfter: Duration(minutes: 10));
      expect(
        attentionFor(
          table,
          _seven.add(const Duration(minutes: 12)),
          rules: cafe,
        ),
        TableAttention.quiet,
      );
    });

    test('a clock behind the seating reads as zero, not negative', () {
      final table = _busy(seatedAt: _seven);
      final earlier = _seven.subtract(const Duration(minutes: 5));
      expect(table.seatedFor(earlier), Duration.zero);
      expect(attentionFor(table, earlier), TableAttention.none);
    });
  });

  group('floorSections', () {
    const floor = [
      DiningTable(id: 1, label: 'B1', seats: 2, areaName: 'Bar', sortOrder: 3),
      DiningTable(id: 2, label: 'T1', seats: 4, sortOrder: 1),
      DiningTable(id: 3, label: 'P1', seats: 6, areaName: 'Terrace', sortOrder: 2),
      DiningTable(id: 4, label: 'P2', seats: 2, areaName: 'Terrace', sortOrder: 5),
      DiningTable(id: 5, label: 'B2', seats: 2, areaName: 'Bar', sortOrder: 4),
    ];

    test('sections follow the order of their first table; main room last', () {
      final sections = floorSections(floor);
      expect(sections.map((s) => s.name), ['Terrace', 'Bar', null]);
    });

    test('tables inside a section keep sort_order', () {
      final sections = floorSections(floor);
      expect(sections.first.tables.map((t) => t.label), ['P1', 'P2']);
      expect(sections[1].tables.map((t) => t.label), ['B1', 'B2']);
    });

    test('a blank section name is the main room', () {
      final sections = floorSections(const [
        DiningTable(id: 1, label: 'T1', seats: 2, areaName: '  '),
      ]);
      expect(sections.single.name, isNull);
    });

    test('busy counts come from the overlaid state', () {
      final overlaid = overlayOpenTickets(floor, {
        3: TicketEngine.addLine(
          TicketEngine.attachTable(
            Ticket(id: 'x', orderType: OrderType.dineIn),
            3,
            'P1',
          ),
          _tea(),
        ).ticket!,
      });
      final terrace = floorSections(overlaid).first;
      expect(terrace.busy, 1);
      expect(terrace.free, 1);
    });
  });

  group('overlay carries the clocks', () {
    test('seated and last-sent come from the ticket, draft flag too', () {
      var ticket = Ticket(id: 'x', orderType: OrderType.dineIn);
      ticket = TicketEngine.attachTable(ticket, 1, 'T1', now: _seven);
      ticket = TicketEngine.addLine(ticket, _tea()).ticket!;
      final fired = _seven.add(const Duration(minutes: 3));
      ticket = TicketEngine.sendRound(ticket, now: fired);

      final table = overlayOpenTickets(
        const [DiningTable(id: 1, label: 'T1', seats: 2)],
        {1: ticket},
      ).single;

      expect(table.seatedAt, _seven);
      expect(table.lastSentAt, fired);
      expect(table.hasUnsentDraft, isFalse);

      final withDraft = overlayOpenTickets(
        const [DiningTable(id: 1, label: 'T1', seats: 2)],
        {1: TicketEngine.addLine(ticket, _tea()).ticket!},
      ).single;
      expect(withDraft.hasUnsentDraft, isTrue);
    });

    test('moving a party keeps the seating time', () {
      var ticket = Ticket(id: 'x', orderType: OrderType.dineIn);
      ticket = TicketEngine.attachTable(ticket, 1, 'T1', now: _seven);
      final later = _seven.add(const Duration(minutes: 40));
      ticket = TicketEngine.attachTable(ticket, 9, 'T9', now: later);
      expect(ticket.seatedAt, _seven);
    });

    test('leaving dine-in clears the seating time', () {
      var ticket = Ticket(id: 'x', orderType: OrderType.dineIn);
      ticket = TicketEngine.attachTable(ticket, 1, 'T1', now: _seven);
      ticket = TicketEngine.setOrderType(ticket, OrderType.takeaway);
      expect(ticket.seatedAt, isNull);
    });
  });
}
