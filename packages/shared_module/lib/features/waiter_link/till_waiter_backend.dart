import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../../core/money/money.dart';
import '../../data/postgres/postgres_parked_tickets.dart';
import '../../data/postgres/postgres_waiter_devices.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/models/ticket.dart';
import '../../domain/services/ticket_engine.dart';

/// Where a table's open check is kept: `pos_parked_tickets`, versioned
/// (XORD-044). An interface so the backend can be tested without a database.
abstract interface class WaiterCheckStore {
  /// The branch's open checks, failing loudly (an outage must not read as
  /// "every table is free").
  Future<ParkedFloor> read(Catalog catalog);

  /// Save [ticket] on its table if the row is still at [expectedVersion];
  /// throws [ParkedTicketChanged] otherwise. Returns the new version.
  Future<int> save(Ticket ticket, {int? expectedVersion});

  /// Clear the table's row, only at [expectedVersion].
  Future<void> remove({required int tableId, required String transactionId, int? expectedVersion});
}

/// [PostgresParkedTickets] as a [WaiterCheckStore].
class ParkedTicketsCheckStore implements WaiterCheckStore {
  const ParkedTicketsCheckStore(this._parked);
  final PostgresParkedTickets _parked;

  @override
  Future<ParkedFloor> read(Catalog catalog) => _parked.refresh(catalog);

  @override
  Future<int> save(Ticket ticket, {int? expectedVersion}) =>
      _parked.save(ticket, expectedVersion: expectedVersion);

  @override
  Future<void> remove({required int tableId, required String transactionId, int? expectedVersion}) =>
      _parked.remove(tableId: tableId, transactionId: transactionId, expectedVersion: expectedVersion);
}

/// Paired handhelds. [PostgresWaiterDevices] in the app; a map in tests.
abstract interface class WaiterDeviceStore {
  Future<(WaiterDevice, String)> register(String name);
  Future<WaiterDevice?> byToken(String token);
  Future<void> touch(int id);
}

class PostgresWaiterDeviceStore implements WaiterDeviceStore {
  const PostgresWaiterDeviceStore(this._devices);
  final PostgresWaiterDevices _devices;

  @override
  Future<(WaiterDevice, String)> register(String name) => _devices.register(name);

  @override
  Future<WaiterDevice?> byToken(String token) => _devices.byToken(token);

  @override
  Future<void> touch(int id) => _devices.touch(id);
}

/// The till's half of the waiter link: the questions a handheld asks,
/// answered with this till's own catalog, tables, staff and `TicketEngine`
/// (waiter-app, WA1).
///
/// **Nothing is priced on the handheld.** A waiter's edit arrives as an
/// operation ("two of product 10 with option 30"), is applied here exactly as
/// the sale screen would apply it, and the check that comes back is the one
/// the till computed (BR-2). The save is the same compare-and-swap the tills
/// use against each other (XORD-044), so a handheld and a till — or two
/// handhelds — cannot overwrite one table.
///
/// What a handheld may not do in WA1, and is refused here whatever the screen
/// offers: void a sent line, discount, override a price, take payment (W4),
/// sell an open-price item or a combo, or touch a table whose bill has
/// started being paid at the till.
class TillWaiterBackend implements WaiterLinkBackend {
  TillWaiterBackend({
    required this._name,
    required this._catalog,
    required this._tables,
    required this._taxConfig,
    required Future<PosStaff?> Function({required String username, required String pin}) signInAs,
    required this.checks,
    required this.devices,
    this.onSaved,
    String Function()? newTicketId,
    DateTime Function()? clock,
  }) : _signIn = signInAs,
       _newId = newTicketId ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final Future<String> Function() _name;
  final Future<Catalog> Function() _catalog;
  final Future<List<DiningTable>> Function() _tables;
  final TaxConfig Function() _taxConfig;
  final Future<PosStaff?> Function({required String username, required String pin}) _signIn;
  final WaiterCheckStore checks;
  final WaiterDeviceStore devices;

  /// Called after a handheld changed a table, so the till's own floor shows
  /// it now rather than at its next refresh.
  final void Function()? onSaved;
  final String Function() _newId;
  final DateTime Function() _clock;

  /// The capabilities a handheld is told about. Only for greying controls out;
  /// every op is checked here again.
  static const _shown = [
    PosCapability.operate,
    PosCapability.orderItemCancel,
    PosCapability.orderItemVoid,
    PosCapability.discountApply,
    PosCapability.priceOverride,
  ];

  @override
  Future<String> tillName() => _name();

  @override
  Future<WaiterPairedDevice> registerDevice(String name) async {
    final (device, token) = await devices.register(name);
    return WaiterPairedDevice(id: device.id, token: token);
  }

  @override
  Future<WaiterDeviceRecord?> authenticate(String token) async {
    final device = await devices.byToken(token);
    return device == null
        ? null
        : WaiterDeviceRecord(
            id: device.id,
            name: device.name,
            revoked: device.isRevoked,
            pairedAt: device.pairedAt,
            lastSeenAt: device.lastSeenAt,
          );
  }

  @override
  Future<void> touchDevice(int id) => devices.touch(id);

  @override
  Future<WaiterStaff?> signIn({required String username, required String pin}) async {
    final staff = await _signIn(username: username, pin: pin);
    if (staff == null || !staff.isActive) return null;
    return WaiterStaff(
      id: staff.id,
      name: staff.name,
      capabilities: {for (final c in _shown) if (staff.can(c)) c},
    );
  }

  // ---------------------------------------------------------------- reads

  @override
  Future<WaiterMenu> menu() async {
    final catalog = await _catalog();
    final currency = _currencyOf(catalog);
    // What a handheld can sell: priced items. Open-price items and combos stay
    // at the till in WA1 (the waiter would be typing a price, or choosing a
    // meal's parts on a phone).
    final products = [
      for (final p in catalog.products)
        if (!p.isOpenPrice) p,
    ];
    final categoryIds = {for (final p in products) p.categoryId};
    final groupIds = {for (final p in products) ...p.modifierGroupIds};
    return WaiterMenu(
      currency: currency,
      categories: [
        for (final c in catalog.categories)
          if (c.isActive && categoryIds.contains(c.id))
            WaiterCategory(id: c.id, name: WaiterName(c.nameEn, c.nameAr)),
      ],
      products: [
        for (final p in products)
          WaiterProduct(
            id: p.id,
            categoryId: p.categoryId,
            name: WaiterName(p.nameEn, p.nameAr),
            priceMinor: p.effectivePrice.minor,
            available: p.isAvailable,
            groupIds: p.modifierGroupIds,
          ),
      ],
      groups: [
        for (final g in catalog.modifierGroups)
          if (groupIds.contains(g.id))
            WaiterModifierGroup(
              id: g.id,
              name: WaiterName(g.displayNameEn ?? g.nameEn, g.displayNameAr ?? g.nameAr),
              minSelect: g.effectiveMinimum,
              maxSelect: g.maxSelect,
              isVariant: g.isVariant,
              modifiers: [
                for (final m in g.modifiers)
                  WaiterModifier(
                    id: m.id,
                    name: WaiterName(m.nameEn, m.nameAr),
                    deltaMinor: m.priceDelta.minor,
                    available: m.isAvailable,
                    isDefault: m.isDefault,
                  ),
              ],
            ),
      ],
    );
  }

  @override
  Future<WaiterFloor> floor() async {
    final catalog = await _catalog();
    final tables = await _tables();
    final open = await checks.read(catalog);
    return WaiterFloor(
      currency: _currencyOf(catalog),
      tables: [
        for (final t in tables)
          if (open.onTables[t.id] case final ticket?)
            WaiterTable(
              id: t.id,
              label: t.label,
              area: t.areaName,
              seats: t.seats,
              state: ticket.tenders.isNotEmpty ? WaiterTableState.billAsked : WaiterTableState.open,
              totalMinor: ticket.totals.total.minor,
              items: ticket.lines.where((l) => !l.isVoided).fold(0, (n, l) => n + l.quantity),
              guests: ticket.guestCount,
            )
          else
            WaiterTable(id: t.id, label: t.label, area: t.areaName, seats: t.seats),
      ],
    );
  }

  @override
  Future<WaiterCheck?> check(int tableId) async {
    final table = (await _tables()).firstWhereOrNull((t) => t.id == tableId);
    if (table == null) return null;
    final catalog = await _catalog();
    final open = await checks.read(catalog);
    final ticket = open.onTables[tableId];
    return ticket == null
        ? WaiterCheck.empty(tableId: table.id, tableLabel: table.label, currency: _currencyOf(catalog))
        : _view(ticket, table, open.versions[tableId], catalog);
  }

  // ---------------------------------------------------------------- the edit

  @override
  Future<WaiterApplyResult> apply({
    required int tableId,
    required int? expectedVersion,
    required List<WaiterOp> ops,
    required WaiterStaff staff,
    required WaiterDeviceRecord device,
  }) async {
    final table = (await _tables()).firstWhereOrNull((t) => t.id == tableId);
    if (table == null) return const WaiterNoTable();
    final catalog = await _catalog();
    final open = await checks.read(catalog);
    final current = open.onTables[tableId];
    final currentVersion = open.versions[tableId];

    WaiterCheck currentView() => current == null
        ? WaiterCheck.empty(tableId: table.id, tableLabel: table.label, currency: _currencyOf(catalog))
        : _view(current, table, currentVersion, catalog);

    // The handheld edited what it last saw. Anything else is a stale copy.
    if (currentVersion != expectedVersion) return WaiterConflict(currentView());

    // Payment has started at the till: the bill is the cashier's now.
    if (current != null && current.tenders.isNotEmpty) {
      return const WaiterRefusal('payment_started');
    }

    var ticket = current ??
        TicketEngine.attachTable(
          Ticket(id: _newId(), orderType: OrderType.dineIn, taxConfig: _taxConfig()),
          table.id,
          table.label,
          guests: table.seats,
        );

    // All or none: the first refusal returns before anything is saved.
    for (final op in ops) {
      switch (_applyOne(ticket, op, catalog, staff)) {
        case _Next(ticket: final next):
          ticket = next;
        case _Stop(:final result):
          return result;
      }
    }

    // A new check that ends with nothing on it seats nobody.
    if (ticket.lines.isEmpty && ticket.roundsSent == 0) {
      if (expectedVersion == null) {
        return WaiterApplied(
          WaiterCheck.empty(tableId: table.id, tableLabel: table.label, currency: _currencyOf(catalog)),
        );
      }
      await checks.remove(tableId: tableId, transactionId: ticket.id, expectedVersion: expectedVersion);
      final after = await checks.read(catalog);
      if (after.onTables.containsKey(tableId)) {
        return WaiterConflict(_view(after.onTables[tableId]!, table, after.versions[tableId], catalog));
      }
      onSaved?.call();
      return WaiterApplied(
        WaiterCheck.empty(tableId: table.id, tableLabel: table.label, currency: _currencyOf(catalog)),
      );
    }

    try {
      final version = await checks.save(ticket, expectedVersion: expectedVersion);
      onSaved?.call();
      return WaiterApplied(_view(ticket, table, version, catalog));
    } on ParkedTicketChanged {
      final now = await checks.read(catalog);
      final latest = now.onTables[tableId];
      return WaiterConflict(
        latest == null
            ? WaiterCheck.empty(tableId: table.id, tableLabel: table.label, currency: _currencyOf(catalog))
            : _view(latest, table, now.versions[tableId], catalog),
      );
    }
  }

  _Step _applyOne(Ticket ticket, WaiterOp op, Catalog catalog, WaiterStaff staff) {
    switch (op) {
      case WaiterAdd():
        final product = catalog.products.firstWhereOrNull((p) => p.id == op.productId);
        if (product == null) return const _Stop(WaiterRefusal('unknown_product'));
        if (product.isOpenPrice) return const _Stop(WaiterRefusal('open_price'));
        if (op.quantity < 1 || op.quantity > 99) return const _Stop(WaiterRefusal('bad_quantity'));
        final groups = [
          for (final id in product.modifierGroupIds)
            ?catalog.modifierGroups.firstWhereOrNull((g) => g.id == id),
        ];
        final modifiers = <Modifier>[];
        for (final id in op.modifierIds) {
          final m = groups.expand((g) => g.modifiers).firstWhereOrNull((m) => m.id == id);
          if (m == null) return const _Stop(WaiterRefusal('unknown_option'));
          modifiers.add(m);
        }
        final note = op.note?.trim();
        return _result(
          TicketEngine.addLine(
            ticket,
            product,
            modifiers: modifiers,
            groups: groups,
            quantity: op.quantity,
            note: note == null || note.isEmpty ? null : note,
          ),
        );

      case WaiterChangeQuantity():
        final line = _draft(ticket, op.lineKey);
        if (line == null) return _Stop(WaiterRefusal(_missing(ticket, op.lineKey)));
        if (op.delta == 0) return _Next(ticket);
        if (line.quantity + op.delta <= 0) return _cancel(ticket, op.lineKey, staff);
        if (line.quantity + op.delta > 99) return const _Stop(WaiterRefusal('bad_quantity'));
        return _Next(TicketEngine.changeQuantity(ticket, op.lineKey, op.delta));

      case WaiterRemoveLine():
        return _cancel(ticket, op.lineKey, staff);

      case WaiterSetNote():
        return _result(TicketEngine.setLineNote(ticket, op.lineKey, op.note.trim()));

      case WaiterSetGuests():
        if (op.guests < 1 || op.guests > 99) return const _Stop(WaiterRefusal('bad_guests'));
        return _Next(ticket.copyWith(guestCount: op.guests));

      case WaiterSendRound():
        if (!ticket.hasDraft) return const _Stop(WaiterRefusal('nothing_to_send'));
        return _Next(TicketEngine.sendRound(ticket));
    }
  }

  _Step _cancel(Ticket ticket, String lineKey, WaiterStaff staff) {
    if (!staff.can(PosCapability.orderItemCancel)) {
      return const _Stop(WaiterForbidden(PosCapability.orderItemCancel));
    }
    return _result(TicketEngine.cancelLine(ticket, lineKey, by: staff.id, now: _clock()));
  }

  static TicketLine? _draft(Ticket ticket, String key) =>
      ticket.lines.firstWhereOrNull((l) => l.key == key && l.stage == LineStage.draft);

  static String _missing(Ticket ticket, String key) =>
      ticket.lines.any((l) => l.key == key) ? 'line_sent' : 'unknown_line';

  static _Step _result(TicketResult result) =>
      result.isOk ? _Next(result.ticket!) : _Stop(WaiterRefusal(reasonOf(result.refusal!)));

  /// A [TicketRefusal] as the stable code the handheld words.
  static String reasonOf(TicketRefusal refusal) => switch (refusal) {
    OutOfStock() => 'out_of_stock',
    RequiredGroupUnsatisfied() => 'options_required',
    TooManySelected() => 'too_many_options',
    LineNotOnTicket() => 'unknown_line',
    WrongStageForAct() => 'line_sent',
    NotPermittedHere() => 'not_permitted',
    _ => 'refused',
  };

  // ---------------------------------------------------------------- views

  static WaiterCurrency _currencyOf(Catalog catalog) {
    final first = catalog.products.firstOrNull?.price;
    return first == null
        ? const WaiterCurrency('EGP', 2)
        : WaiterCurrency(first.currency, first.exponent);
  }

  WaiterCheck _view(Ticket ticket, DiningTable table, int? version, Catalog catalog) {
    final totals = ticket.totals;
    final Money total = totals.total;
    return WaiterCheck(
      tableId: table.id,
      tableLabel: table.label,
      currency: WaiterCurrency(total.currency, total.exponent),
      version: version,
      guests: ticket.guestCount,
      roundsSent: ticket.roundsSent,
      subtotalMinor: totals.subtotal.minor,
      discountMinor: totals.discount.minor,
      serviceMinor: totals.service.minor,
      taxMinor: totals.vat.minor,
      totalMinor: total.minor,
      lines: [
        for (final line in ticket.lines)
          WaiterLine(
            key: line.key,
            name: WaiterName(line.product.nameEn, line.product.nameAr),
            quantity: line.quantity,
            totalMinor: line.isVoided ? 0 : line.lineTotal.minor,
            modifiers: [for (final m in line.modifiers) WaiterName(m.nameEn, m.nameAr)],
            note: line.note,
            stage: line.isVoided
                ? WaiterLineStage.voided
                : (line.stage == LineStage.draft ? WaiterLineStage.draft : WaiterLineStage.sent),
            round: line.roundNumber,
            productId: line.product.id,
          ),
      ],
    );
  }
}

sealed class _Step {
  const _Step();
}

class _Next extends _Step {
  const _Next(this.ticket);
  final Ticket ticket;
}

class _Stop extends _Step {
  const _Stop(this.result);
  final WaiterApplyResult result;
}
