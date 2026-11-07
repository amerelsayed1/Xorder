/// What a kind of order requires, as the business configured it (§31).
///
/// **This exists to delete a comparison.** `type == OrderType.dineIn` appeared
/// in the router, the cart panel and the ticket engine, and in all three what
/// it meant was *"does this kind of order have a table"*. A business that
/// seats people for catering, or one whose drive-thru bays are numbered like
/// tables, could not say so — the answer was compiled in.
///
/// The **codes are still an enum.** `OrderType` remains closed for now, and
/// this configures the four it names rather than opening the set. Custom codes
/// need one more thing that is not built: every place that renders an order
/// type reads its name off the enum, so a fifth code would have no name to
/// show until the display path takes a config instead of a value. That is a
/// contained change and it is not this one; saying so is better than shipping
/// a table that implies a freedom the UI does not have.
library;

import 'ticket.dart';

class OrderTypeConfig {
  const OrderTypeConfig({
    required this.type,
    required this.nameEn,
    this.nameAr,
    this.requiresTable = false,
    this.requiresCustomer = false,
    this.requiresAddress = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final OrderType type;
  final String nameEn;
  final String? nameAr;

  /// Whether an order of this kind is seated. The floor picker, the cart's
  /// "no table yet" prompt and the engine's detach-on-switch all ask this.
  final bool requiresTable;

  /// Whether a customer must be named before it can be settled. Nothing reads
  /// this yet — customers are Wave H — and it is stored now because it is the
  /// same row and a business configuring delivery expects to set it.
  final bool requiresCustomer;

  final bool requiresAddress;
  final bool isActive;
  final int sortOrder;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// What the product ships with, and what the migration seeds.
  ///
  /// Kept in step with migration 25 by a test rather than by discipline.
  static const seeded = <OrderTypeConfig>[
    OrderTypeConfig(
      type: OrderType.dineIn,
      nameEn: 'Dine in',
      nameAr: 'صالة',
      requiresTable: true,
      sortOrder: 1,
    ),
    OrderTypeConfig(
      type: OrderType.takeaway,
      nameEn: 'Takeaway',
      nameAr: 'تيك أواي',
      sortOrder: 2,
    ),
    OrderTypeConfig(
      type: OrderType.delivery,
      nameEn: 'Delivery',
      nameAr: 'دليفري',
      requiresCustomer: true,
      requiresAddress: true,
      sortOrder: 3,
    ),
    OrderTypeConfig(
      type: OrderType.driveThru,
      nameEn: 'Drive-thru',
      nameAr: 'سيارة',
      sortOrder: 4,
    ),
  ];
}

/// The configured order types, with the questions the app actually asks.
///
/// A value object rather than a bare list, because every caller wants one of
/// three things — *does this need a table*, *what may this branch sell*, *what
/// is it called* — and a list makes each of them a fold somebody writes
/// slightly differently.
class OrderTypeRules {
  const OrderTypeRules(this.configured);

  /// What a till gets before anything is configured: the seeded four.
  static const fallback = OrderTypeRules(OrderTypeConfig.seeded);

  final List<OrderTypeConfig> configured;

  OrderTypeConfig? forType(OrderType type) {
    for (final config in configured) {
      if (config.type == type) return config;
    }
    return null;
  }

  /// Whether an order of this kind is seated.
  ///
  /// **Defaults to false for a type nobody configured**, which is the safe
  /// direction: a ticket that thinks it has no table simply does not offer
  /// one, where a ticket that thinks it does would send a cashier to a floor
  /// plan with nothing on it.
  bool requiresTable(OrderType type) => forType(type)?.requiresTable ?? false;

  bool requiresCustomer(OrderType type) =>
      forType(type)?.requiresCustomer ?? false;

  bool requiresAddress(OrderType type) =>
      forType(type)?.requiresAddress ?? false;

  /// Whether anything this branch sells is seated — the question the router
  /// asks before it offers a floor plan.
  bool get hasSeating => configured.any((c) => c.isActive && c.requiresTable);

  List<OrderType> get active => [
    for (final config in configured)
      if (config.isActive) config.type,
  ];
}
