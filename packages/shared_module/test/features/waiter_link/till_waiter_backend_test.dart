import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/postgres_parked_tickets.dart';
import 'package:shared_module/data/postgres/postgres_waiter_devices.dart';
import 'package:shared_module/data/postgres/postgres_waiter_shifts.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/dining_table.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';
import 'package:shared_module/features/waiter_link/till_waiter_backend.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// The till's half of the waiter link (waiter-app, WA1): a handheld's edits
/// applied by the real `TicketEngine`, saved with the tables' version check.
void main() {
  late _MemoryChecks checks;
  late TillWaiterBackend backend;
  late _MemoryShifts shifts;
  var saved = 0;
  var ids = 0;

  const waiter = WaiterStaff(
    id: 7,
    name: 'Mona',
    capabilities: {PosCapability.operate, PosCapability.orderItemCancel},
  );
  const noCancel = WaiterStaff(id: 8, name: 'Sami', capabilities: {PosCapability.operate});
  const device = WaiterDeviceRecord(id: 1, name: 'Phone');

  setUp(() {
    checks = _MemoryChecks();
    shifts = _MemoryShifts();
    saved = 0;
    ids = 0;
    backend = TillWaiterBackend(
      name: () async => 'Main till',
      catalog: () async => _catalog,
      tables: () async => _tables,
      taxConfig: () => const TaxConfig(),
      signInAs: ({required username, required pin}) async => switch ((username, pin)) {
        ('mona', '1111') => const PosStaff(
          id: 7,
          name: 'Mona',
          capabilities: {PosCapability.operate, PosCapability.orderItemCancel},
        ),
        ('gone', '3333') => const PosStaff(id: 9, name: 'Gone', isActive: false, capabilities: {PosCapability.operate}),
        _ => null,
      },
      checks: checks,
      devices: _NoDevices(),
      shifts: shifts,
      onSaved: () => saved++,
      newTicketId: () => 'ticket-${++ids}',
      clock: () => DateTime(2026, 11, 9, 21),
    );
  });

  Future<WaiterApplyResult> apply(int table, int? version, List<WaiterOp> ops, {WaiterStaff staff = waiter}) =>
      backend.apply(tableId: table, expectedVersion: version, ops: ops, staff: staff, device: device);

  WaiterCheck applied(WaiterApplyResult r) {
    expect(r, isA<WaiterApplied>(), reason: '$r');
    return (r as WaiterApplied).check;
  }

  String refusal(WaiterApplyResult r) {
    expect(r, isA<WaiterRefusal>(), reason: '$r');
    return (r as WaiterRefusal).reason;
  }

  group('what a handheld reads', () {
    test('the menu is priced items only, in minor units, with their groups', () async {
      final menu = await backend.menu();
      expect([for (final p in menu.products) p.id], [10, 11], reason: 'the open-price item stays at the till');
      expect(menu.products.first.priceMinor, 10000);
      expect(menu.products[1].priceMinor, 3000, reason: 'the discounted price is the selling price');
      expect(menu.groups.single.id, 5);
      expect(menu.groups.single.isRequired, isTrue);
      expect(menu.currency.code, 'EGP');
    });

    test('signing in gives the person and what the handheld may show them', () async {
      final staff = await backend.signIn(username: 'mona', pin: '1111');
      expect(staff!.name, 'Mona');
      expect(staff.can(PosCapability.orderItemCancel), isTrue);
      expect(staff.can(PosCapability.priceOverride), isFalse);
      expect(await backend.signIn(username: 'gone', pin: '3333'), isNull, reason: 'an inactive person cannot sign in');
      expect(await backend.signIn(username: 'mona', pin: '0000'), isNull);
    });

    test('the floor shows open checks with their totals', () async {
      applied(await apply(1, null, const [WaiterAdd(productId: 10, modifierIds: [50])]));
      final floor = await backend.floor();
      final t1 = floor.tables.firstWhere((t) => t.id == 1);
      expect(t1.state, WaiterTableState.open);
      expect(t1.items, 1);
      expect(t1.totalMinor, greaterThan(10000));
      expect(floor.tables.firstWhere((t) => t.id == 2).state, WaiterTableState.free);
    });

    test('a free table has an empty check; an unknown one has none', () async {
      final check = await backend.check(2);
      expect(check!.isEmpty, isTrue);
      expect(check.version, isNull);
      expect(await backend.check(99), isNull);
    });
  });

  group('editing a check', () {
    test('the first item seats the table, priced by the till exactly as the sale screen would', () async {
      final check = applied(await apply(1, null, const [WaiterAdd(productId: 10, modifierIds: [50], quantity: 2)]));
      expect(check.version, 1);
      expect(check.lines.single.quantity, 2);
      expect(check.lines.single.modifiers.single.en, 'Spicy');

      // The same order rung up through the engine directly.
      final reference = TicketEngine.addLine(
        TicketEngine.attachTable(Ticket(id: 'x', orderType: OrderType.dineIn), 1, 'T1', guests: 4),
        _catalog.products.first,
        modifiers: [_catalog.modifierGroups.single.modifiers.first],
        groups: _catalog.modifierGroups,
        quantity: 2,
      ).ticket!;
      expect(check.totalMinor, reference.totals.total.minor);
      expect(check.serviceMinor, reference.totals.service.minor);
      expect(check.taxMinor, reference.totals.vat.minor);

      final stored = checks.rows[1]!;
      expect(stored.$1.tableId, 1);
      expect(stored.$1.orderType, OrderType.dineIn);
      expect(saved, 1, reason: "the till's floor is told at once");
    });

    test('sending a round fires every unsent line, and an empty send is refused', () async {
      var check = applied(await apply(1, null, const [WaiterAdd(productId: 10, modifierIds: [50])]));
      check = applied(await apply(1, check.version, const [WaiterAdd(productId: 11), WaiterSendRound()]));
      expect(check.roundsSent, 1);
      expect(check.lines.every((l) => l.stage == WaiterLineStage.sent && l.round == 1), isTrue);
      expect(refusal(await apply(1, check.version, const [WaiterSendRound()])), 'nothing_to_send');
    });

    test('a required option is required, and options must belong to the item', () async {
      expect(refusal(await apply(1, null, const [WaiterAdd(productId: 10)])), 'options_required');
      expect(refusal(await apply(1, null, const [WaiterAdd(productId: 10, modifierIds: [999])])), 'unknown_option');
      expect(refusal(await apply(1, null, const [WaiterAdd(productId: 12)])), 'open_price');
      expect(refusal(await apply(1, null, const [WaiterAdd(productId: 404)])), 'unknown_product');
      expect(refusal(await apply(1, null, const [WaiterAdd(productId: 11, quantity: 0)])), 'bad_quantity');
      expect(checks.rows, isEmpty);
    });

    test('all or none: one refused op saves nothing of the others', () async {
      final r = await apply(1, null, const [WaiterAdd(productId: 11), WaiterAdd(productId: 404)]);
      expect(refusal(r), 'unknown_product');
      expect(checks.rows, isEmpty);
      expect(saved, 0);
    });

    test('taking an unsent line off needs the cancel permission and is recorded', () async {
      final check = applied(await apply(1, null, const [WaiterAdd(productId: 11), WaiterAdd(productId: 10, modifierIds: [50])]));
      final key = check.lines.first.key;

      final denied = await apply(1, check.version, [WaiterRemoveLine(lineKey: key)], staff: noCancel);
      expect(denied, isA<WaiterForbidden>());
      expect((denied as WaiterForbidden).capability, PosCapability.orderItemCancel);

      final after = applied(await apply(1, check.version, [WaiterRemoveLine(lineKey: key)]));
      expect(after.lines, hasLength(1));
      final events = checks.rows[1]!.$1.lineEvents;
      expect(events.single.event, TicketLineEventKind.removedBeforeSend);
      expect(events.single.staffId, 7);
    });

    test('a sent line cannot be changed or removed from a handheld', () async {
      var check = applied(await apply(1, null, const [WaiterAdd(productId: 11), WaiterSendRound()]));
      final key = check.lines.single.key;
      expect(refusal(await apply(1, check.version, [WaiterChangeQuantity(lineKey: key, delta: 1)])), 'line_sent');
      expect(refusal(await apply(1, check.version, [WaiterRemoveLine(lineKey: key)])), 'line_sent');
      check = (await backend.check(1))!;
      expect(check.lines.single.stage, WaiterLineStage.sent);
    });

    test('quantity down to nothing is a cancel; notes and guests are kept', () async {
      var check = applied(await apply(1, null, const [WaiterAdd(productId: 11, quantity: 2)]));
      final key = check.lines.single.key;
      check = applied(await apply(1, check.version, [
        WaiterSetNote(lineKey: key, note: ' no ice '),
        const WaiterSetGuests(3),
      ]));
      expect(check.lines.single.note, 'no ice');
      expect(check.guests, 3);
      expect(refusal(await apply(1, check.version, const [WaiterSetGuests(0)])), 'bad_guests');
      expect(
        await apply(1, check.version, [WaiterChangeQuantity(lineKey: key, delta: -2)], staff: noCancel),
        isA<WaiterForbidden>(),
      );
    });

    test('a check emptied before anything was saved seats nobody', () async {
      final r = applied(await apply(2, null, const [WaiterAdd(productId: 11)]));
      final emptied = applied(await apply(2, r.version, [WaiterRemoveLine(lineKey: r.lines.single.key)]));
      expect(emptied.isEmpty, isTrue);
      expect(checks.rows.containsKey(2), isFalse);
    });
  });

  group('two devices, one table (XORD-044)', () {
    test('an edit against an old version is refused with the current check', () async {
      final first = applied(await apply(1, null, const [WaiterAdd(productId: 11)]));
      applied(await apply(1, first.version, const [WaiterAdd(productId: 11)]));

      final stale = await apply(1, first.version, const [WaiterSendRound()]);
      expect(stale, isA<WaiterConflict>());
      final current = (stale as WaiterConflict).current;
      expect(current.version, 2);
      expect(current.lines.single.quantity, 2);
      expect(checks.rows[1]!.$1.roundsSent, 0, reason: 'the stale send changed nothing');
    });

    test('a table seated elsewhere while the waiter saw it free is a conflict', () async {
      applied(await apply(1, null, const [WaiterAdd(productId: 11)]));
      expect(await apply(1, null, const [WaiterAdd(productId: 10, modifierIds: [50])]), isA<WaiterConflict>());
    });

    test('a save that loses the race at the database is a conflict too', () async {
      final first = applied(await apply(1, null, const [WaiterAdd(productId: 11)]));
      checks.raceNextSave = true;
      expect(await apply(1, first.version, const [WaiterAdd(productId: 11)]), isA<WaiterConflict>());
    });

    test('once the cashier starts taking payment, the handheld is refused', () async {
      final first = applied(await apply(1, null, const [WaiterAdd(productId: 11)]));
      final (ticket, version) = checks.rows[1]!;
      checks.rows[1] = (
        TicketEngine.addTender(ticket, typeId: 1, label: 'Cash', amount: ticket.totals.total).ticket!,
        version,
      );
      expect(refusal(await apply(1, first.version, const [WaiterAdd(productId: 11)])), 'payment_started');
      expect((await backend.floor()).tables.first.state, WaiterTableState.billAsked);
    });

    test('an unknown table is not found', () async {
      expect(await apply(99, null, const [WaiterAdd(productId: 11)]), isA<WaiterNoTable>());
    });
  });

  group('the shift clock', () {
    test('start opens one shift, a second start returns it, finish closes it', () async {
      expect(await backend.openShift(waiter.id), isNull);
      final started = await backend.startShift(waiter, device);
      expect(started.isOpen, isTrue);
      expect((await backend.startShift(waiter, device)).id, started.id, reason: 'never two open shifts');
      expect((await backend.openShift(waiter.id))!.id, started.id);

      final finished = await backend.finishShift(waiter, device);
      expect(finished!.id, started.id);
      expect(finished.isOpen, isFalse);
      expect(await backend.openShift(waiter.id), isNull);
      expect(await backend.finishShift(waiter, device), isNull, reason: 'nothing open to finish');
      expect(shifts.rows.single.startedDevice, '1', reason: 'the device is recorded');
    });

    test("one waiter's shift is theirs alone", () async {
      await backend.startShift(waiter, device);
      expect(await backend.openShift(noCancel.id), isNull);
    });
  });
}

class _MemoryShifts implements WaiterShiftStore {
  final rows = <WaiterShiftRecord>[];
  var _now = DateTime.utc(2026, 11, 9, 18);

  @override
  Future<WaiterShiftRecord?> open(int staffId) async =>
      rows.where((r) => r.staffId == staffId && r.isOpen).firstOrNull;

  @override
  Future<WaiterShiftRecord> start(int staffId, {int? deviceId}) async {
    final existing = await open(staffId);
    if (existing != null) return existing;
    final row = WaiterShiftRecord(id: rows.length + 1, staffId: staffId, startedAt: _now, startedDevice: '$deviceId');
    rows.add(row);
    return row;
  }

  @override
  Future<WaiterShiftRecord?> finish(int staffId, {int? deviceId}) async {
    final existing = await open(staffId);
    if (existing == null) return null;
    _now = _now.add(const Duration(hours: 8));
    final closed = WaiterShiftRecord(
      id: existing.id,
      staffId: staffId,
      startedAt: existing.startedAt,
      endedAt: _now,
      startedDevice: existing.startedDevice,
      endedDevice: '$deviceId',
    );
    rows[rows.indexOf(existing)] = closed;
    return closed;
  }
}

// ---------------------------------------------------------------------------

const _egp = Money(0);

final _catalog = Catalog(
  syncedAt: DateTime(2026, 11, 9),
  categories: const [Category(id: 1, nameEn: 'Mains', nameAr: 'رئيسي')],
  modifierGroups: const [
    ModifierGroup(
      id: 5,
      nameEn: 'Heat',
      isRequired: true,
      minSelect: 1,
      modifiers: [
        Modifier(id: 50, groupId: 5, nameEn: 'Spicy', nameAr: 'حار', priceDelta: Money(500)),
        Modifier(id: 51, groupId: 5, nameEn: 'Mild', priceDelta: _egp),
      ],
    ),
  ],
  products: const [
    Product(id: 10, categoryId: 1, nameEn: 'Kofta', nameAr: 'كفتة', price: Money(10000), modifierGroupIds: [5]),
    Product(id: 11, categoryId: 1, nameEn: 'Tea', price: Money(4000), discountedPrice: Money(3000)),
    Product(id: 12, categoryId: 1, nameEn: 'Open item', price: Money(0), isOpenPrice: true),
  ],
);

const _tables = [
  DiningTable(id: 1, label: 'T1', seats: 4),
  DiningTable(id: 2, label: 'T2', seats: 2),
];

class _MemoryChecks implements WaiterCheckStore {
  final rows = <int, (Ticket, int)>{};
  bool raceNextSave = false;

  @override
  Future<ParkedFloor> read(Catalog catalog) async => ParkedFloor(
    onTables: {for (final e in rows.entries) e.key: e.value.$1},
    versions: {for (final e in rows.entries) e.key: e.value.$2},
  );

  @override
  Future<int> save(Ticket ticket, {int? expectedVersion}) async {
    final table = ticket.tableId!;
    if (raceNextSave) {
      raceNextSave = false;
      final (t, v) = rows[table]!;
      rows[table] = (t, v + 1);
      throw ParkedTicketChanged(table);
    }
    if (rows[table]?.$2 != expectedVersion) throw ParkedTicketChanged(table);
    final next = (expectedVersion ?? 0) + 1;
    rows[table] = (ticket, next);
    return next;
  }

  @override
  Future<void> remove({required int tableId, required String transactionId, int? expectedVersion}) async {
    if (rows[tableId]?.$2 == expectedVersion) rows.remove(tableId);
  }
}

class _NoDevices implements WaiterDeviceStore {
  @override
  Future<(WaiterDevice, String)> register(String name) => throw UnimplementedError();
  @override
  Future<WaiterDevice?> byToken(String token) async => null;
  @override
  Future<void> touch(int id) async {}
}
