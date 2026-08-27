import '../../core/money/money.dart';

/// A member of staff, as the till knows them.
///
/// Carries the id because a shift belongs to a *person*, not to a name: two
/// cashiers called Ahmed would otherwise share a drawer in the ledger.
class PosStaff {
  const PosStaff({
    required this.id,
    required this.name,
    this.capabilities = const {},
  });

  final int id;
  final String name;
  final Set<String> capabilities;

  bool can(String capability) => capabilities.contains(capability);
}

/// An open or closed till session.
class PosShift {
  const PosShift({
    required this.id,
    required this.openedAt,
    required this.openingFloat,
    required this.openedByName,
    this.closedAt,
  });

  final int id;
  final DateTime openedAt;
  final Money openingFloat;
  final String openedByName;
  final DateTime? closedAt;

  bool get isOpen => closedAt == null;

  /// Derived from the id rather than stored.
  ///
  /// A denormalised reference is a string that drifts: renumber, restore from a
  /// backup, or copy a row, and the label stops matching the thing it labels.
  String get reference => 'SHIFT #${id.toString().padLeft(4, '0')}';
}

/// One tender type's contribution to a shift.
class ShiftTenderTotal {
  const ShiftTenderTotal({required this.label, required this.count, required this.amount});

  final String label;
  final int count;
  final Money amount;
}

/// What the shift did — the Z report, in the only form that matters at the
/// drawer: how much cash *should* be in it.
class ShiftSummary {
  const ShiftSummary({
    required this.shift,
    required this.saleCount,
    required this.gross,
    required this.tenders,
  });

  final PosShift shift;
  final int saleCount;

  /// Everything charged, however it was paid.
  final Money gross;
  final List<ShiftTenderTotal> tenders;

  /// Cash tenders only. Card and wallet do not end up in the drawer, so
  /// counting them against it would manufacture a variance every single shift.
  Money get cashTaken => tenders
      .where((t) => t.label.toLowerCase().contains('cash'))
      .fold(Money.zero, (sum, t) => sum + t.amount);

  /// What the drawer should hold: what was in it at the start, plus the cash
  /// taken since.
  Money get expectedCash => shift.openingFloat + cashTaken;

  /// Positive means more cash in the drawer than the sales explain.
  Money varianceAgainst(Money counted) => counted - expectedCash;
}

/// The outcome of counting the drawer.
class ShiftClose {
  const ShiftClose({
    required this.summary,
    required this.countedCash,
    required this.variance,
    required this.closedAt,
  });

  final ShiftSummary summary;
  final Money countedCash;
  final Money variance;
  final DateTime closedAt;

  bool get balances => variance.minor == 0;
}
