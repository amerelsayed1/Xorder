import '../../core/money/money.dart';
import 'permissions.dart';

/// A member of staff, as the till knows them.
///
/// Carries the id because a shift belongs to a *person*, not to a name: two
/// cashiers called Ahmed would otherwise share a drawer in the ledger.
class PosStaff {
  const PosStaff({
    required this.id,
    required this.name,
    this.capabilities = const {},
    this.role,
    this.username,
    this.isActive = true,
  });

  final int id;
  final String name;

  /// Granted to *this person*, on top of whatever [role] carries.
  ///
  /// Kept as well as the role rather than replaced by it because the exception
  /// is the common case in a small restaurant: one cashier who is also trusted
  /// to reprint. Making that person a whole new role, or promoting them to
  /// supervisor, are both worse answers than one extra grant against their
  /// name — and the audit trail records which of the two it was.
  final Set<String> capabilities;

  /// Null for a member of staff seeded before roles existed, or one whose role
  /// was deleted. They keep [capabilities] and nothing else, which is the
  /// conservative reading rather than the convenient one.
  final PosRole? role;

  final String? username;
  final bool isActive;

  /// The role's capabilities and the direct grants, under their current names.
  ///
  /// Canonicalised on the way out rather than on the way in, because rows
  /// written by an older build are still on disk and a till that has not been
  /// migrated yet must still read them correctly.
  Set<String> get effectiveCapabilities =>
      PosCapability.canonicalAll({...?role?.capabilities, ...capabilities});

  /// Whether this person may do the thing, ignoring any supervisor standing
  /// behind them. Override is a separate question — `Authorization.check`.
  bool can(String capability) =>
      effectiveCapabilities.contains(PosCapability.canonical(capability));

  PosStaff copyWith({
    String? name,
    Set<String>? capabilities,
    PosRole? role,
    String? username,
    bool? isActive,
  }) => PosStaff(
    id: id,
    name: name ?? this.name,
    capabilities: capabilities ?? this.capabilities,
    role: role ?? this.role,
    username: username ?? this.username,
    isActive: isActive ?? this.isActive,
  );
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
  const ShiftTenderTotal({
    required this.label,
    required this.count,
    required this.amount,
  });

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
