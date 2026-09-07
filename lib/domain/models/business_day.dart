/// The trading day, and money that moves without a sale.
library;

import '../../core/money/money.dart';

/// One trading day at one branch.
class BusinessDay {
  const BusinessDay({
    required this.id,
    required this.date,
    required this.openedAt,
    this.openedByName,
    this.closedAt,
    this.closedByName,
    this.forced = false,
    this.forceReason,
    this.gross,
    this.net,
  });

  final int id;

  /// Midnight of the business date. Not the calendar date the money arrived on
  /// — see `DayPolicy.dateFor`.
  final DateTime date;

  final DateTime openedAt;
  final String? openedByName;
  final DateTime? closedAt;
  final String? closedByName;

  /// Closed over the top of blockers.
  final bool forced;
  final String? forceReason;

  final Money? gross;
  final Money? net;

  bool get isOpen => closedAt == null;
}

/// Why a day cannot be closed yet.
///
/// Data rather than a sentence, so the screen can offer a route to each one.
/// A close that refused without saying what was in the way would send a manager
/// hunting through four screens at midnight.
class DayBlocker {
  const DayBlocker({required this.kind, required this.count});

  final DayBlockerKind kind;
  final int count;
}

enum DayBlockerKind {
  /// A till still has a drawer open.
  openShift,

  /// A table is still seated with a running ticket.
  parkedTicket,

  /// An order exists that nobody has settled.
  unpaidOrder,
}

/// What is standing between a manager and the end of the night.
class DayCloseCheck {
  const DayCloseCheck({required this.day, required this.blockers});

  final BusinessDay day;
  final List<DayBlocker> blockers;

  bool get isClear => blockers.isEmpty;

  /// Whether closing needs `day.force_close` rather than `day.close`.
  bool get needsForce => blockers.isNotEmpty;
}

/// Money into or out of the drawer that is not a sale.
///
/// **[amount] is always positive; [kind] carries the direction.** Storing a
/// pay-out as a negative would be negated twice by anything that reads the
/// kind, and the two conventions would coexist for exactly as long as it took
/// somebody to write the second reader. Migration 14's CHECK enforces it.
enum CashMovementKind {
  payIn('pay_in'),
  payOut('pay_out'),

  /// The drawer opened with no sale behind it (§23). Moves nothing, and the
  /// database refuses a row that claims otherwise.
  drawerOpen('drawer_open'),

  /// Correcting the opening float.
  floatAdjust('float_adjust');

  const CashMovementKind(this.wire);

  final String wire;

  /// Whether this takes money out of the drawer.
  bool get isOutflow => this == CashMovementKind.payOut;

  /// Whether this puts money in.
  bool get isInflow =>
      this == CashMovementKind.payIn || this == CashMovementKind.floatAdjust;

  static CashMovementKind? fromWire(String value) {
    for (final kind in CashMovementKind.values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

class CashMovement {
  const CashMovement({
    required this.id,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    this.reasonName,
    this.reasonNameAr,
    this.note,
    this.staffName,
    this.approvedByName,
  });

  final int id;
  final CashMovementKind kind;

  /// Always positive. See [CashMovementKind].
  final Money amount;

  final DateTime occurredAt;
  final String? reasonName;
  final String? reasonNameAr;
  final String? note;
  final String? staffName;
  final String? approvedByName;

  /// What this did to the drawer: positive in, negative out, zero for an
  /// opening. The one place the sign is applied, so no caller has to remember
  /// which way a pay-out points.
  Money get signed => switch (kind) {
    CashMovementKind.payOut => -amount,
    CashMovementKind.drawerOpen => amount.copyWith(minor: 0),
    _ => amount,
  };
}

/// The drawer's non-sale movements, totalled.
class CashMovementTotals {
  const CashMovementTotals({
    required this.paidIn,
    required this.paidOut,
    required this.drawerOpens,
    required this.movements,
  });

  factory CashMovementTotals.of(
    List<CashMovement> movements, {
    String currency = 'EGP',
    int exponent = 2,
  }) {
    final zero = Money(0, currency: currency, exponent: exponent);
    var paidIn = zero;
    var paidOut = zero;
    var opens = 0;

    for (final movement in movements) {
      switch (movement.kind) {
        case CashMovementKind.payIn:
        case CashMovementKind.floatAdjust:
          paidIn += movement.amount;
        case CashMovementKind.payOut:
          paidOut += movement.amount;
        case CashMovementKind.drawerOpen:
          opens++;
      }
    }

    return CashMovementTotals(
      paidIn: paidIn,
      paidOut: paidOut,
      drawerOpens: opens,
      movements: movements,
    );
  }

  /// Both positive. The direction is in the name, not in the sign.
  final Money paidIn;
  final Money paidOut;

  /// How many times the drawer was opened without a sale. Not money, but the
  /// number a manager looks at hardest.
  final int drawerOpens;

  final List<CashMovement> movements;

  /// The net effect on the drawer.
  Money get net => paidIn - paidOut;
}
