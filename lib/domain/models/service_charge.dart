/// What a business adds on top of the food (§38).
///
/// **Data, not a single rate.** The ticket carried one `serviceBp` and one
/// rule — *dine-in only* — which cannot express the two things businesses
/// here actually do: a delivery fee that is a flat amount rather than a
/// percentage, and a second charge that applies to a different set of order
/// types than the first.
///
/// A charge is either a **rate** or a **fixed amount**, never both. Allowing
/// both would make "12% or 20 EGP, whichever" a question the model asks and
/// nobody has answered — and a bill that took both would be a bill nobody
/// could check.
library;

import '../../core/money/money.dart';
import 'ticket.dart';

class ServiceCharge {
  const ServiceCharge({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.rateBp,
    this.fixedMinor,
    this.orderTypes = const {},
    this.isTaxable = true,
    this.isAutomatic = true,
    this.isOptional = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int id;
  final String nameEn;
  final String? nameAr;

  /// Basis points of the discounted subtotal. Null on a fixed charge.
  final int? rateBp;

  /// A flat amount in minor units. Null on a percentage charge.
  ///
  /// Held as minor units rather than as [Money] for the same reason a
  /// permission ceiling is: a charge belongs to a business and the currency
  /// question is the business's, answered once when the ticket is priced.
  final int? fixedMinor;

  /// Which order types it applies to.
  ///
  /// **Empty means every one.** A business that has not thought about it
  /// gets a charge that applies, which is the reading that matches what the
  /// single `serviceDineInOnly` flag replaced — and a charge that silently
  /// applied to nothing would be a charge somebody configured and never saw.
  final Set<OrderType> orderTypes;

  /// Whether VAT is charged on the charge.
  ///
  /// Service is taxable in Egypt; a delivery fee collected on behalf of an
  /// aggregator may not be. A non-taxable charge stays out of the VAT base
  /// entirely rather than being taxed at zero, because those are different
  /// statements on a filing.
  final bool isTaxable;

  /// Added without being asked for. A charge that is not automatic is one the
  /// cashier adds by hand, which is a Wave D screen this model is ready for
  /// and nothing yet offers.
  final bool isAutomatic;

  /// The customer may decline it. Recorded so a cashier can remove it without
  /// needing a permission — declining an optional charge is not an override.
  final bool isOptional;

  final bool isActive;
  final int sortOrder;

  bool get isFixed => fixedMinor != null;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// Whether this charge is added to an order of [type] without being asked.
  bool appliesTo(OrderType type) =>
      isActive &&
      isAutomatic &&
      (orderTypes.isEmpty || orderTypes.contains(type));

  /// What it comes to on [base].
  ///
  /// Rounded here, once, half-up — the same single rounding point every other
  /// rate in this product uses. Two charges on one bill are two roundings
  /// because they are two lines a customer can check, not one number split.
  Money on(Money base) => isFixed
      ? Money(fixedMinor!, currency: base.currency, exponent: base.exponent)
      : base.percentBp(rateBp ?? 0);

  ServiceCharge copyWith({
    String? nameEn,
    String? nameAr,
    int? rateBp,
    int? fixedMinor,
    Set<OrderType>? orderTypes,
    bool? isTaxable,
    bool? isAutomatic,
    bool? isOptional,
    bool? isActive,
    int? sortOrder,
    bool clearRate = false,
    bool clearFixed = false,
  }) => ServiceCharge(
    id: id,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    rateBp: clearRate ? null : (rateBp ?? this.rateBp),
    fixedMinor: clearFixed ? null : (fixedMinor ?? this.fixedMinor),
    orderTypes: orderTypes ?? this.orderTypes,
    isTaxable: isTaxable ?? this.isTaxable,
    isAutomatic: isAutomatic ?? this.isAutomatic,
    isOptional: isOptional ?? this.isOptional,
    isActive: isActive ?? this.isActive,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  bool operator ==(Object other) =>
      other is ServiceCharge &&
      other.id == id &&
      other.rateBp == rateBp &&
      other.fixedMinor == fixedMinor &&
      other.isTaxable == isTaxable &&
      other.isActive == isActive &&
      other.isAutomatic == isAutomatic &&
      other.nameEn == nameEn;

  @override
  int get hashCode =>
      Object.hash(id, rateBp, fixedMinor, isTaxable, isActive, isAutomatic, nameEn);
}

/// What a ticket is actually charged, split by whether VAT applies.
///
/// Two numbers rather than one, because they enter the totals at different
/// points: the taxable part joins the VAT base, the rest does not. Collapsing
/// them would mean either taxing a delivery fee that should not be taxed, or
/// not taxing a service charge that should — and both are errors somebody
/// notices on a filing rather than at the till.
class ServiceTotal {
  const ServiceTotal({required this.taxable, required this.untaxed});

  static const none = ServiceTotal(taxable: Money.zero, untaxed: Money.zero);

  final Money taxable;
  final Money untaxed;

  Money get total => taxable + untaxed;

  bool get isZero => taxable.isZero && untaxed.isZero;
}
