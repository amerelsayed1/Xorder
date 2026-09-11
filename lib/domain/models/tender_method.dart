/// How money moves, in or out.
///
/// One list, shared by settlement and by refunds. They were separate lists for
/// exactly as long as refunds did not exist, and two lists of tender types is
/// how a till ends up refunding to a method it cannot take payment on.
///
/// **Data since §40 (Wave D).** These used to be four constants compiled into
/// the binary. They are now rows a restaurant edits, and [seeded] is what the
/// migration writes rather than what the code believes. The constants remain
/// only as the fallback for a till with no database yet — see
/// [UnconfiguredTenderTypesRepository].
library;

/// The class of thing a tender is, for the code that treats classes
/// differently.
///
/// ETA files cash and everything-electronic under different codes, and a wallet
/// is not a card to a reconciliation. A free-text kind would make both of those
/// a string comparison somebody eventually gets wrong.
enum TenderKind {
  cash('cash'),
  card('card'),
  wallet('wallet'),
  account('account'),
  voucher('voucher'),
  other('other');

  const TenderKind(this.wire);

  final String wire;

  /// Unknown kinds from a newer build fall to [other] rather than throwing. A
  /// tender type this binary does not understand must still be *takeable* —
  /// refusing it would stop a till selling because somebody added a payment
  /// method in the back office.
  static TenderKind fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return other;
  }
}

/// What the platform calls a kind of tender (POS-BE-013): `cash | card |
/// external | other`.
///
/// A separate vocabulary from [TenderKind], not four more members on it. The
/// two lists share three words and disagree about the fourth, and folding
/// `external` into [TenderKind] would put it in the offline editor, where it
/// means nothing. The translation is one exhaustive switch, so a fifth
/// platform kind is a compile error in [tillKind] rather than a payment
/// method that quietly lands in the wrong column of a reconciliation.
enum PlatformTenderKind {
  cash('cash'),
  card('card'),
  external('external'),
  other('other');

  const PlatformTenderKind(this.wire);

  final String wire;

  /// Null for a kind this build has never heard of. The caller decides what
  /// unknown means — for the seeder, a takeable tender that is not cash —
  /// rather than this pretending it knows.
  static PlatformTenderKind? fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }

  TenderKind get tillKind => switch (this) {
    cash => TenderKind.cash,
    card => TenderKind.card,
    // A card taken on the bank's own standalone terminal — which is what the
    // platform's model says `external` exists for. Card rather than other
    // because of the one reader that tells them apart: the branch-sales
    // breakdown (`PaymentBucket`) puts card in ELECTRONIC and other beside
    // vouchers, and electronic is the figure a manager holds up against the
    // bank terminal's settlement slip. Filing it as other would leave that
    // slip short by every external payment, every night. ETA does not care
    // either way: it files C/V/M from the payment's own cash flag, and this
    // is not cash. Wallet was the other candidate, and is wrong for the same
    // reason the platform did not call it one — nothing here is InstaPay.
    external => TenderKind.card,
    other => TenderKind.other,
  };
}

class TenderMethod {
  const TenderMethod({
    required this.id,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.kind = TenderKind.other,
    this.countsAsCash = false,
    this.opensDrawer = false,
    this.requiresReference = false,
    this.refundAllowed = true,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int id;

  /// Stable, machine-readable, never shown. A restaurant renaming "Card" into
  /// Arabic must not change what the seed and the tests refer to.
  final String code;

  final String nameEn;
  final String? nameAr;
  final TenderKind kind;

  /// Whether taking this tender puts notes in the drawer.
  ///
  /// **This replaced a substring match on the label.** `ShiftSummary` used to
  /// find the drawer's cash with `label.toLowerCase().contains('cash')`, which
  /// was wrong in two directions: a method called "Cashback voucher" counted
  /// toward a drawer it never touched, and an Arabic label stopped matching at
  /// all — leaving every Arabic till reporting an expected drawer of nothing
  /// but the float, a false variance on every single cash-up.
  ///
  /// Note where the flag is *read* from at cash-up time: the payment row, not
  /// this one. See `pos_order_payments.counts_as_cash`.
  final bool countsAsCash;

  /// Whether settling on this method should kick the drawer open. Not the same
  /// question as [countsAsCash]: a restaurant that keeps its vouchers in the
  /// till drawer opens it for them and does not count them as cash.
  final bool opensDrawer;

  /// Whether the cashier must type an authorisation code or a last-four.
  final bool requiresReference;

  /// Whether money may go back out this way. A voucher usually cannot be
  /// refunded to; cash usually can.
  final bool refundAllowed;

  final bool isActive;
  final int sortOrder;

  /// What is **written** to the tender record.
  ///
  /// English, deliberately, on an Arabic till as much as an English one: it is
  /// a wire value on a stored row, and a receipt reprinted in a different
  /// language must still show what was taken. What the cashier *reads* is
  /// [displayName].
  String get wireLabel => nameEn;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// The four a restaurant gets before anybody configures anything.
  ///
  /// Kept in step with migration 23's seed by a test, not by discipline: two
  /// definitions of "what a new restaurant starts with" is how a fresh install
  /// and a migrated one end up different.
  static const seeded = <TenderMethod>[
    TenderMethod(
      id: 1,
      code: 'cash',
      nameEn: 'Cash',
      nameAr: 'نقدي',
      kind: TenderKind.cash,
      countsAsCash: true,
      opensDrawer: true,
      sortOrder: 1,
    ),
    TenderMethod(
      id: 2,
      code: 'card',
      nameEn: 'Card',
      nameAr: 'بطاقة',
      kind: TenderKind.card,
      requiresReference: true,
      sortOrder: 2,
    ),
    TenderMethod(
      id: 3,
      code: 'wallet',
      nameEn: 'Wallet · InstaPay',
      nameAr: 'محفظة',
      kind: TenderKind.wallet,
      requiresReference: true,
      sortOrder: 3,
    ),
    TenderMethod(
      id: 4,
      code: 'account',
      nameEn: 'On account',
      nameAr: 'على الحساب',
      kind: TenderKind.account,
      sortOrder: 4,
    ),
  ];

  /// The highest id [seeded] uses, and the floor every platform-sent row sits
  /// above.
  ///
  /// The payment screen falls back to [seeded] while its list loads and when
  /// no row is active, so a payment can carry one of these ids without any row
  /// having been chosen. On a cloud till that payment must never be mistaken
  /// for one taken on a platform tender — so no platform row may hold one of
  /// these ids. Migration 41's CHECK states the same number; a test keeps
  /// [seeded] under it.
  static const seededIdCeiling = 4;

  /// Whether a tender of this **seeded** type puts money in the drawer.
  ///
  /// Only correct for a till still on the seeded list, which is why nothing at
  /// cash-up time uses it any more: a settled payment carries its own
  /// `counts_as_cash`, snapshotted when the money moved. This remains for the
  /// one caller that has no payment row to read — pricing a tender before it is
  /// taken — and falls back to **false** for a type it does not know.
  static bool isCash(int? typeId) =>
      typeId != null && (byId(typeId)?.countsAsCash ?? false);

  static TenderMethod? byId(int id) {
    for (final method in seeded) {
      if (method.id == id) return method;
    }
    return null;
  }
}
