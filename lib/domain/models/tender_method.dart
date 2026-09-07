/// How money moves, in or out.
///
/// One list, shared by settlement and by refunds. They were separate lists for
/// exactly as long as refunds did not exist, and two lists of tender types is
/// how a till ends up refunding to a method it cannot take payment on.
///
/// §37 makes payment methods configurable data (Wave D). When that lands, this
/// list becomes the seed rather than the definition — and [wireLabel] is why
/// that migration has to be careful: see the note on it.
library;

class TenderMethod {
  const TenderMethod(this.id, this.wireLabel, {this.countsAsCash = false});

  final int id;

  /// Whether taking this tender puts notes in the drawer.
  ///
  /// **This replaces a substring match on [wireLabel].** `ShiftSummary` used to
  /// find the drawer's cash with `label.toLowerCase().contains('cash')`, which
  /// is wrong in two directions: a method called "Cashback voucher" counted
  /// toward a drawer it never touched, and the moment payment methods become
  /// configurable data (§37, Wave D) an Arabic label stops matching at all —
  /// leaving every Arabic till reporting an expected drawer of nothing but the
  /// float, a false variance on every single cash-up.
  ///
  /// The gap-closure plan names that as a Wave B risk to be fixed *in the same
  /// change* that makes methods data. Fixing it before is cheaper and means the
  /// trap is already gone when Wave D arrives: the flag becomes a column, and
  /// nothing that reads it changes.
  final bool countsAsCash;

  /// What is **written** to the tender record, and it stays English on an
  /// Arabic till on purpose.
  ///
  /// `ShiftSummary.cashTaken` finds the drawer's cash by matching this text, so
  /// translating what gets stored would leave every Arabic shift reporting an
  /// expected drawer of nothing but the float — a false variance on every
  /// cash-up, in the one number the count exists to check. Replacing this match
  /// with a `counts_as_cash` column is a named risk in the gap-closure plan and
  /// must happen in the same change that makes methods configurable.
  final String wireLabel;

  /// The four a restaurant gets before anybody configures anything.
  static const seeded = <TenderMethod>[
    TenderMethod(1, 'Cash', countsAsCash: true),
    TenderMethod(2, 'Card'),
    TenderMethod(3, 'Wallet · InstaPay'),
    TenderMethod(4, 'On account'),
  ];

  /// Whether a stored tender put money in the drawer.
  ///
  /// Falls back to **false** for a type this build does not know. An unknown
  /// method counted as cash would manufacture a variance the cashier cannot
  /// explain; one counted as non-cash under-states the drawer, which the count
  /// itself then surfaces. Wrong quietly beats wrong loudly here only because
  /// the count is the thing that catches it.
  static bool isCash(int? typeId) =>
      typeId != null && (byId(typeId)?.countsAsCash ?? false);

  static TenderMethod? byId(int id) {
    for (final method in seeded) {
      if (method.id == id) return method;
    }
    return null;
  }
}
