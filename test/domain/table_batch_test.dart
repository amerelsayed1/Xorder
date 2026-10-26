import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/services/table_batch.dart';

/// XORD-006 — what a prefix, a first number and a quantity make, and what is
/// wrong with them, decided before anything is saved.
void main() {
  TableBatchPlan plan({
    String prefix = 'Table',
    int? start = 1,
    int? quantity = 10,
    int? seats = 2,
    Set<String> existing = const {},
  }) => TableBatch.plan(
    prefix: prefix,
    start: start,
    quantity: quantity,
    seats: seats,
    existing: existing,
  );

  test('ten from one is Table 1 to Table 10, exactly', () {
    final p = plan();
    expect(p.labels, [for (var n = 1; n <= 10; n++) 'Table $n']);
    expect(p.canCreate, isTrue);
    expect(p.labels.toSet().length, 10, reason: 'all unique');
  });

  test('a first number other than one, and a prefix with stray spaces', () {
    expect(plan(prefix: '  T ', start: 21, quantity: 3).labels, ['T 21', 'T 22', 'T 23']);
  });

  test('no prefix is the bare number', () {
    expect(plan(prefix: '', start: 5, quantity: 2).labels, ['5', '6']);
  });

  test('a name the branch already has is reported, and nothing can be created', () {
    final p = plan(existing: {'Table 3', 'Table 4', 'Other'});
    expect(p.clashes, ['Table 3', 'Table 4']);
    expect(p.canCreate, isFalse);
    expect(p.labels, hasLength(10), reason: 'the preview still shows the run');
  });

  test('the quantity runs from 1 to 100', () {
    expect(plan(quantity: 100).canCreate, isTrue);
    for (final q in [0, -1, 101, null]) {
      expect(plan(quantity: q).problem, TableBatchProblem.quantity, reason: '$q');
    }
  });

  test('the first number is at least 1 and the last at most 9999', () {
    expect(plan(start: 9990, quantity: 10).canCreate, isTrue);
    for (final s in [0, -3, null]) {
      expect(plan(start: s).problem, TableBatchProblem.start, reason: '$s');
    }
    expect(plan(start: 9991, quantity: 10).problem, TableBatchProblem.start);
  });

  test('seats are at least one', () {
    for (final s in [0, -1, null]) {
      expect(plan(seats: s).problem, TableBatchProblem.seats, reason: '$s');
    }
  });

  test('a prefix of more than 40 characters is refused', () {
    expect(plan(prefix: 'x' * 41).problem, TableBatchProblem.prefix);
    expect(plan(prefix: 'x' * 40).problem, isNull);
  });

  test('a problem leaves no labels to create', () {
    final p = plan(quantity: 0);
    expect(p.labels, isEmpty);
    expect(p.canCreate, isFalse);
  });
}
