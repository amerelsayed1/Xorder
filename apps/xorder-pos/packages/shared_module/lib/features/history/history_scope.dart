import '../../domain/models/order_record.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/refund_history.dart';
import '../../domain/models/shift.dart';
import '../../domain/services/authorization.dart';

/// Whose sales a person at the till may read (plan 17 §5).
///
/// `order.view_all` sees the branch. Without it, a person sees the sales they
/// rang up themselves and nobody else's — SALES-§23's `sales.view_own`, which
/// is the default for anybody who may operate the till rather than a
/// capability of its own.
///
/// **Applied where history is read, not where it is drawn.** The screen hides
/// the cashier filter from somebody who may not use it, but a hidden control
/// is not a rule: the providers every history reader goes through pass each
/// query through [scope] first, so no widget — this screen, or the next one
/// somebody builds on the same provider — can ask for more than the person is
/// allowed.
///
/// Asked through [Authorization.check], never `PosStaff.capabilities`: that
/// field is the person's direct grants only, and reading it would tell a
/// supervisor whose role carries `order.view_all` that they may only see their
/// own sales.
abstract final class HistoryScope {
  /// Whether [viewer] may read every sale at the branch.
  static bool seesEveryone(PosStaff? viewer) =>
      Authorization.check(viewer, PosCapability.orderViewAll).isAllowed;

  /// [query], narrowed to what [viewer] may read — or null when they may read
  /// nothing.
  ///
  /// Nobody signed in reads nothing. An unattended till is not a till that may
  /// list the day's takings.
  ///
  /// The seller is **overwritten**, not merely defaulted. A query that arrived
  /// already asking for somebody else's sales — built by a screen that forgot
  /// to hide the picker, or restored from state saved under a manager — is
  /// narrowed to the viewer, never honoured.
  static OrderHistoryQuery? scope(OrderHistoryQuery query, PosStaff? viewer) {
    if (viewer == null) return null;
    if (seesEveryone(viewer)) return query;
    return query.copyWith(servedByStaffId: viewer.id);
  }

  /// [query], narrowed the way [scope] narrows sales — or null for nobody.
  ///
  /// **By the seller of the sale refunded, not by who gave the money back.**
  /// Returns is the other side of the same sales: a cashier sees the refunds
  /// against the sales their own list shows, and every one of them opens in
  /// that list. Scoped by `refunded_by` instead, a cashier who gave money
  /// back on a colleague's sale under a supervisor's approval would be shown
  /// a refund whose sale [mayOpen] then refuses them.
  static RefundHistoryQuery? scopeRefunds(
    RefundHistoryQuery query,
    PosStaff? viewer,
  ) {
    if (viewer == null) return null;
    if (seesEveryone(viewer)) return query;
    return query.copyWith(servedByStaffId: viewer.id);
  }

  /// Whether [viewer] may open [order] in the detail pane.
  ///
  /// The list is scoped, so a cashier only ever clicks their own rows; this is
  /// the same rule for an id that arrived some other way. An order with no
  /// recorded seller belongs to nobody, so only the branch view opens it.
  static bool mayOpen(OrderRecord order, PosStaff? viewer) {
    if (viewer == null) return false;
    if (seesEveryone(viewer)) return true;
    return order.servedByStaffId == viewer.id;
  }
}
