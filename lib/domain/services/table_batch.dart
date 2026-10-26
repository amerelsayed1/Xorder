/// Planning "add several tables at once" (XORD-006): the names a prefix, a
/// first number and a quantity produce, and what is wrong with them, decided
/// before anything is saved.
///
/// Pure and shared by the dialog's preview and the repository's own check, so
/// the screen cannot promise a batch the database would then refuse for a
/// reason the screen could have said.
library;

enum TableBatchProblem {
  /// Not a whole number from 1 to [TableBatch.maxQuantity].
  quantity,

  /// The first number is not a whole number from 1 up, or the run would go
  /// past [TableBatch.maxNumber].
  start,

  /// A table seats at least one person.
  seats,

  /// The prefix is longer than [TableBatch.maxPrefix] characters.
  prefix,
}

class TableBatchPlan {
  const TableBatchPlan({
    required this.labels,
    this.clashes = const [],
    this.problem,
  });

  /// The names that would be created, in order. Empty when [problem] is set.
  final List<String> labels;

  /// Names that already exist in the branch. A batch with any is refused whole.
  final List<String> clashes;

  final TableBatchProblem? problem;

  bool get canCreate => problem == null && clashes.isEmpty && labels.isNotEmpty;
}

abstract final class TableBatch {
  /// One batch is at most this many tables. A restaurant with more adds a
  /// second batch; a typo of an extra zero is caught here rather than saved.
  static const maxQuantity = 100;

  /// The highest number a run may reach: nobody numbers tables past this, so a
  /// larger one is a typing mistake.
  static const maxNumber = 9999;

  static const maxPrefix = 40;

  /// `Table 1`, `Table 2`… The prefix is trimmed and a space put between it and
  /// the number; with no prefix the label is the bare number.
  static String label(String prefix, int number) {
    final p = prefix.trim();
    return p.isEmpty ? '$number' : '$p $number';
  }

  static TableBatchPlan plan({
    required String prefix,
    required int? start,
    required int? quantity,
    required int? seats,
    Set<String> existing = const {},
  }) {
    if (quantity == null || quantity < 1 || quantity > maxQuantity) {
      return const TableBatchPlan(
        labels: [],
        problem: TableBatchProblem.quantity,
      );
    }
    if (start == null || start < 1 || start + quantity - 1 > maxNumber) {
      return const TableBatchPlan(labels: [], problem: TableBatchProblem.start);
    }
    if (seats == null || seats < 1) {
      return const TableBatchPlan(labels: [], problem: TableBatchProblem.seats);
    }
    if (prefix.trim().length > maxPrefix) {
      return const TableBatchPlan(
        labels: [],
        problem: TableBatchProblem.prefix,
      );
    }

    final labels = [
      for (var n = start; n < start + quantity; n++) label(prefix, n),
    ];
    return TableBatchPlan(
      labels: labels,
      clashes: [
        for (final name in labels)
          if (existing.contains(name)) name,
      ],
    );
  }
}
