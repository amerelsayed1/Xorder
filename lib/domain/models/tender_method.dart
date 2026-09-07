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
  const TenderMethod(this.id, this.wireLabel);

  final int id;

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
    TenderMethod(1, 'Cash'),
    TenderMethod(2, 'Card'),
    TenderMethod(3, 'Wallet · InstaPay'),
    TenderMethod(4, 'On account'),
  ];

  static TenderMethod? byId(int id) {
    for (final method in seeded) {
      if (method.id == id) return method;
    }
    return null;
  }
}
