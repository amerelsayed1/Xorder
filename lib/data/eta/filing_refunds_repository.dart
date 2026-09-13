// The collaborators are private fields with public parameter names: the
// names belong to the call site, the fields do not belong to the API.
// ignore_for_file: prefer_initializing_formals
import '../../domain/models/order_record.dart';
import '../../domain/models/refund.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/eta_filing.dart';
import '../../domain/services/refund_engine.dart' show RefundQuote;
import 'filing_orders_repository.dart';

/// Files a refund receipt for every refund that reaches the database.
///
/// Until this, refunds never reached `pos_eta_receipts` at all: every one was
/// an unfiled credit note, and the filed sales overstated turnover by what had
/// been handed back. A refund receipt names the sale it undoes by uuid, so one
/// whose sale has no receipt yet waits — [EtaFiler] says so rather than
/// filing a reference to nothing — and the reconciler files it on the pass
/// after its sale.
///
/// **A failure here never fails the refund**, for the same reason a filing
/// failure never fails a sale: the money has already crossed the counter.
class FilingRefundsRepository implements RefundsRepository {
  const FilingRefundsRepository(
    this._inner, {
    required EtaFilingPort filer,
    this.onProblem,
  }) : _filer = filer;

  final RefundsRepository _inner;
  final EtaFilingPort _filer;
  final void Function(EtaFilingSkipped)? onProblem;

  @override
  Future<RefundResult> issue({
    required OrderRecord order,
    required RefundQuote quote,
    required PosStaff by,
    required List<RefundTender> tenders,
    required String clientRefundId,
    PosStaff? approvedBy,
    int? reasonId,
    String? note,
  }) async {
    final result = await _inner.issue(
      order: order,
      quote: quote,
      by: by,
      tenders: tenders,
      clientRefundId: clientRefundId,
      approvedBy: approvedBy,
      reasonId: reasonId,
      note: note,
    );
    try {
      FilingOrdersRepository.report(
        await _filer.fileRefund(result.refundId),
        onProblem,
      );
    } on Object catch (error) {
      onProblem?.call(FilingFailed('$error'));
    }
    return result;
  }

  @override
  Future<List<Refund>> forOrder(int orderId) => _inner.forOrder(orderId);
}
