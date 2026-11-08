import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/discount.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import '../sql/sql.dart';
import '../sql/row_reads.dart';

/// Reads what the business offers from `pos_discounts`.
///
/// Read-only, deliberately: the till's database role is granted `SELECT` here
/// and nothing else. A cashier applies a discount; authoring one is a
/// back-office act and belongs to the administrative credential.
class PostgresDiscountsRepository implements DiscountsRepository {
  const PostgresDiscountsRepository({
    required SqlDatabase database,
    required this.config,
    required this.businessId,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final int businessId;

  /// Matches the ticket's, because a discount priced in another currency from
  /// the bill it comes off would not add up.
  final String currency;
  final int exponent;

  Money _money(Object? minor) =>
      Money(minor is int ? minor : 0, currency: currency, exponent: exponent);

  @override
  Future<List<Discount>> all() async {
    final rows = await _db.query(
      config,
      'SELECT id, code, name_en, name_ar, kind, value_bp, value_minor, scope, '
      '       min_order_minor, max_discount_minor, starts_at, ends_at, '
      '       days_of_week, time_from, time_to, requires_customer, '
      '       requires_manager, is_restricted, is_active, revision '
      'FROM pos_discounts WHERE business_id = @r ORDER BY name_en',
      parameters: {'r': businessId},
    );

    final discounts = <Discount>[];
    for (final row in rows) {
      final id = row[0] as int;
      // A row whose kind or scope this build does not understand is skipped
      // rather than guessed at. Pricing a discount by assuming what it meant is
      // how a customer is charged something nobody configured.
      final kind = DiscountKind.fromWire(row[4] as String);
      final scope = DiscountScope.fromWire(row[7] as String);
      if (kind == null || scope == null) continue;

      discounts.add(
        Discount(
          id: id,
          code: row[1] as String,
          nameEn: row[2] as String,
          nameAr: row[3] as String?,
          kind: kind,
          scope: scope,
          valueBp: row[5] as int?,
          valueMinor: row[6] == null ? null : _money(row[6]),
          minOrder: row[8] == null ? null : _money(row[8]),
          maxDiscount: row[9] == null ? null : _money(row[9]),
          startsAt: row.dateTimeOrNull(10),
          endsAt: row.dateTimeOrNull(11),
          daysOfWeek: {
            for (final day in (row.list(12) ?? const []))
              if (day is int) day,
          },
          timeFrom: _minutes(row[13]),
          timeTo: _minutes(row[14]),
          requiresCustomer: row.booleanOrNull(15) ?? false,
          requiresManager: row.booleanOrNull(16) ?? false,
          isRestricted: row.booleanOrNull(17) ?? false,
          isActive: row.booleanOrNull(18) ?? true,
          targets: await _targetsFor(id),
          revision: row[19] as int? ?? 1,
        ),
      );
    }

    return discounts;
  }

  /// A `time` column, as minutes past midnight.
  ///
  /// The driver may hand this back as a `DateTime` on the epoch date or as a
  /// string, depending on version. Both are read; anything else is null, which
  /// means "no window" rather than midnight — a window nobody configured must
  /// not silently become one that closes at 00:00.
  static int? _minutes(Object? value) {
    if (value is DateTime) return value.hour * 60 + value.minute;
    if (value is String) {
      final parts = value.split(':');
      if (parts.length < 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return null;
      return hour * 60 + minute;
    }
    return null;
  }

  Future<DiscountTargets> _targetsFor(int discountId) async {
    final rows = await _db.query(
      config,
      'SELECT target_type, target_id FROM pos_discount_targets '
      'WHERE discount_id = @d',
      parameters: {'d': discountId},
    );

    final categories = <int>{};
    final products = <int>{};
    final orderTypes = <OrderType>{};

    for (final row in rows) {
      final id = row[1] as String;
      switch (row[0] as String) {
        case 'category':
          final value = int.tryParse(id);
          if (value != null) categories.add(value);
        case 'product':
          final value = int.tryParse(id);
          if (value != null) products.add(value);
        case 'order_type':
          final type = OrderType.fromWire(id);
          if (type != null) orderTypes.add(type);
      }
    }

    return DiscountTargets(
      categoryIds: categories,
      productIds: products,
      orderTypes: orderTypes,
    );
  }

  /// The ceiling on what this person may discount.
  ///
  /// **Two sources, and the tighter of the two wins.** `pos_roles` has carried
  /// `max_discount_bp` since before Wave C; `pos_permission_limits` is the
  /// general form, resolved onto the person at sign-in and covering their own
  /// ceiling as well as every role's. Reading only the new one would silently
  /// lift every ceiling a business has already set, and reading only the old
  /// one would make the new table decorative — so both are read and neither can
  /// loosen the other.
  @override
  Future<DiscountLimit> limitFor(PosStaff? staff) async {
    // Already resolved when they signed in; no query for this half.
    final resolved = staff?.limitFor(LimitKey.discount) ??
        PermissionLimit.unlimited;

    final roleId = staff?.role?.id;
    // Nobody signed in, or nobody on a role. Unlimited is **not** the permissive
    // reading it looks like: the capability check happens before this is ever
    // consulted, so a person who reaches a limit question has already been
    // found allowed to discount at all.
    if (roleId == null) return _asDiscountLimit(resolved);

    final rows = await _db.query(
      config,
      'SELECT max_discount_bp, max_discount_minor FROM pos_roles '
      'WHERE id = @role AND business_id = @r',
      parameters: {'role': roleId, 'r': businessId},
    );
    if (rows.isEmpty) return _asDiscountLimit(resolved);

    return _asDiscountLimit(
      resolved.tightenedBy(
        PermissionLimit(
          maxBp: rows.first[0] as int?,
          maxMinor: rows.first[1] == null
              ? null
              : _money(rows.first[1]).minor,
        ),
      ),
    );
  }

  /// The currency arrives here and not in [PermissionLimit] on purpose: a
  /// ceiling belongs to a role, and a role outlives the currency question.
  DiscountLimit _asDiscountLimit(PermissionLimit limit) => DiscountLimit(
    maxBp: limit.maxBp,
    maxAmount: limit.maxMinor == null ? null : _money(limit.maxMinor),
  );
}

/// What a till binds before it has a database.
///
/// Nothing, and no ceiling. Returning an invented discount list here is the
/// failure `lib/data/unconfigured/` exists to prevent — a terminal mid-setup
/// showing promotions no business configured.
class UnconfiguredDiscountsRepository implements DiscountsRepository {
  const UnconfiguredDiscountsRepository();

  @override
  Future<List<Discount>> all() async => const [];

  @override
  Future<DiscountLimit> limitFor(PosStaff? staff) async =>
      DiscountLimit.unlimited;
}
