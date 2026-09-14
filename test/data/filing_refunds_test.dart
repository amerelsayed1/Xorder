import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/data/eta/filing_refunds_repository.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';
import 'package:xorder_pos/domain/services/refund_engine.dart'
    show RefundQuote;

/// Filing a refund receipt for every refund that reaches the database.
///
/// Same rule as a sale: **a filing failure never fails the refund.** The money
/// has already crossed the counter.
void main() {
  Future<RefundResult> issue(FilingRefundsRepository refunds) => refunds.issue(
    order: _Order(),
    quote: _Quote(),
    by: const PosStaff(id: 1, name: 'Nour'),
    tenders: const [],
    clientRefundId: 'r-1',
  );

  test('an issued refund is filed, by the id it was written under', () async {
    final filer = _Filer();
    await issue(FilingRefundsRepository(_Refunds(), filer: filer));
    expect(filer.refunds, [77]);
  });

  test('a filer that throws does not lose the refund', () async {
    final problems = <EtaFilingSkipped>[];
    final result = await issue(
      FilingRefundsRepository(
        _Refunds(),
        filer: _Filer(throws: true),
        onProblem: problems.add,
      ),
    );

    expect(result.refundId, 77);
    expect(problems.single, isA<FilingFailed>());
  });

  test('a refund waiting for its sale is the system working, not a problem',
      () async {
    final problems = <EtaFilingSkipped>[];
    await issue(
      FilingRefundsRepository(
        _Refunds(),
        filer: _Filer(answer: const RefundAwaitingSale()),
        onProblem: problems.add,
      ),
    );
    expect(problems, isEmpty);
  });
}

class _Order extends Mock implements OrderRecord {}

class _Quote extends Mock implements RefundQuote {}

class _Refunds implements RefundsRepository {
  @override
  Future<RefundResult> issue({
    required OrderRecord order,
    required RefundQuote quote,
    required PosStaff by,
    required List<RefundTender> tenders,
    required String clientRefundId,
    Approval? approval,
    int? reasonId,
    String? note,
  }) async => RefundResult(
    clientRefundId: clientRefundId,
    refundId: 77,
    replayed: false,
  );

  @override
  Future<List<Refund>> forOrder(int orderId) async => const [];
}

class _Filer implements EtaFilingPort {
  _Filer({this.answer, this.throws = false});

  final EtaFilingSkipped? answer;
  final bool throws;
  final refunds = <int>[];

  @override
  Future<EtaFilingSkipped?> fileOrder(int orderId) async => answer;

  @override
  Future<EtaFilingSkipped?> fileRefund(int refundId) async {
    if (throws) throw StateError('connection reset');
    refunds.add(refundId);
    return answer;
  }
}
