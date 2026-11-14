import '../models/ticket.dart';
import '../repositories/repositories.dart';

/// Wraps the local repository so every settled sale immediately pokes the
/// drain. The write itself is untouched — the sale commits to PostgreSQL with
/// its outbox claim in the same transaction, exactly as before; this only
/// makes "sold" and "synced" seconds apart instead of a timer apart.
class SyncingOrdersRepository implements OrdersRepository {
  const SyncingOrdersRepository(this._inner, this._kick);

  final OrdersRepository _inner;
  final void Function() _kick;

  @override
  Future<SubmitOrderResult> submit(
    Ticket ticket, {
    PosStaff? servedBy,
    int? parkedVersion,
  }) async {
    final result = await _inner.submit(
      ticket,
      servedBy: servedBy,
      parkedVersion: parkedVersion,
    );
    _kick();
    return result;
  }

  @override
  Future<int> pendingSyncCount() => _inner.pendingSyncCount();

  @override
  Future<String?> platformInvoiceNumber(String clientTransactionId) =>
      _inner.platformInvoiceNumber(clientTransactionId);

  /// Kicks the drain too. A voided order is a row the platform has to hear
  /// about as much as a paid one — arguably more, since it is the one a
  /// business will be asked about.
  @override
  Future<SubmitOrderResult> voidOrder(
    Ticket ticket, {
    required PosStaff by,
    int? reasonId,
    String? note,
    Approval? approval,
    PosStaff? servedBy,
    int? parkedVersion,
  }) async {
    final result = await _inner.voidOrder(
      ticket,
      by: by,
      reasonId: reasonId,
      note: note,
      approval: approval,
      servedBy: servedBy,
      parkedVersion: parkedVersion,
    );
    _kick();
    return result;
  }
}
