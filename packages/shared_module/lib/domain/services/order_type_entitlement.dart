/// Which order types the licence lets this till sell (XORD-002).
///
/// Pure Dart. The licence's `features` is a set of strings the issuer wrote;
/// the order-type ones are `dine_in`, `pickup` (or `takeaway`) and `delivery`,
/// the same spelling the platform's plan flags use. Drive-thru has no flag of
/// its own — a lane only exists at a till — so it follows `pos`.
///
/// **A licence that names none of them restricts nothing.** Older licences and
/// the dev stub carry only `pos`, and treating "no order-type flags" as "no
/// order types" would take every sale away from a till on the day of an update.
/// The restriction starts when the issuer says anything about order types.
library;

import '../models/ticket.dart';

abstract final class OrderTypeEntitlement {
  static const _dineIn = 'dine_in';
  static const _takeaway = {'pickup', 'takeaway'};
  static const _delivery = 'delivery';
  static const _pos = 'pos';

  /// The types [features] allow, or null when it says nothing about order types
  /// (no restriction).
  static Set<OrderType>? fromFeatures(Set<String> features) {
    final mentionsAny =
        features.contains(_dineIn) ||
        features.contains(_delivery) ||
        features.any(_takeaway.contains);
    if (!mentionsAny) return null;

    return {
      if (features.contains(_dineIn)) OrderType.dineIn,
      if (features.any(_takeaway.contains)) OrderType.takeaway,
      if (features.contains(_delivery)) OrderType.delivery,
      if (features.contains(_pos)) OrderType.driveThru,
    };
  }
}
