/// Where the business keeps its money (XORD-015, stage 1).
///
/// A cash drawer, a bank account, an e-wallet. Stage 1 only records that they
/// exist and which one each payment method pays into; nothing is posted to an
/// account yet, so no sale, shift, cash-up or report reads any of this.
library;

/// What sort of place the money is in.
///
/// A separate list from [TenderKind], on purpose: a payment *method* says how
/// the customer paid ("wallet"), an *account* says where it landed. They share
/// a word and mean different things.
enum AccountKind {
  cash('cash'),
  bank('bank'),
  wallet('wallet');

  const AccountKind(this.wire);

  final String wire;

  /// Null for a word this build does not know, so the caller decides; the
  /// seeder skips such a row rather than invent a kind for it.
  static AccountKind? fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// One account.
///
/// [branchId] null means the whole business shares it (the company bank
/// account); otherwise it belongs to that one branch (a drawer). Never deleted:
/// [isActive] is the way out, because a payment will one day name an account
/// and has to keep a row to point at.
class FinancialAccount {
  const FinancialAccount({
    required this.id,
    required this.name,
    required this.kind,
    this.branchId,
    this.currency,
    this.referenceLabel,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// `0` is a new one, like every other editable row in the back office.
  final int id;
  final String name;
  final AccountKind kind;
  final int? branchId;

  /// The platform's value on a cloud till; null offline, where nothing here
  /// knows the restaurant's currency. Shown, never compared.
  final String? currency;

  /// A short hint to tell accounts apart ("CIB 4521"). Not an account number.
  final String? referenceLabel;
  final bool isActive;
  final int sortOrder;

  FinancialAccount copyWith({
    String? name,
    AccountKind? kind,
    int? branchId,
    bool clearBranch = false,
    String? referenceLabel,
    bool clearReference = false,
    bool? isActive,
    int? sortOrder,
  }) => FinancialAccount(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    branchId: clearBranch ? null : (branchId ?? this.branchId),
    currency: currency,
    referenceLabel: clearReference
        ? null
        : (referenceLabel ?? this.referenceLabel),
    isActive: isActive ?? this.isActive,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}

/// The account a payment method pays into at one branch.
///
/// [branchId] null is the business-wide fallback. [tenderTypeId] is the LOCAL
/// payment-method id; the seeder translates the platform's.
class TenderAccountDefault {
  const TenderAccountDefault({
    required this.tenderTypeId,
    required this.accountId,
    this.branchId,
  });

  final int tenderTypeId;
  final int? branchId;
  final int accountId;
}

/// Why an account or a default could not be saved. Enum-keyed so the message
/// table is exhaustive and a reason added later cannot reach an Arabic screen
/// as a blank.
enum AccountProblem {
  /// The name is blank.
  nameMissing,

  /// Another account of this restaurant already has the name.
  nameTaken,

  /// The reference looks like an account number (nine or more digits).
  referenceLooksLikeNumber,

  /// The name looks like an account number: a name is shown everywhere and
  /// goes to the audit log, so it gets the same guard as the reference.
  nameLooksLikeNumber,

  /// The branch is not one of this restaurant's.
  branchUnknown,

  /// The payment method is not one of this restaurant's.
  methodUnknown,

  /// The account is not one of this restaurant's, or it is switched off.
  accountUnavailable,

  /// A branch's own account cannot serve another branch, nor be the
  /// business-wide fallback.
  accountOfAnotherBranch,

  /// The account is somebody's default; replace that first.
  accountIsDefault,
}

/// The rules the offline till applies. The cloud applies the same ones on the
/// server (`StoreFinancialAccountRequest`, `SetTenderAccountDefaultRequest`);
/// they are two copies, kept in step by hand and by tests on both sides, not
/// one shared definition.
abstract final class AccountRules {
  /// Nine or more digits in a row, up to three non-letter, non-digit characters
  /// between them, in ANY script: an Arabic-Indic number typed on an Arabic
  /// keyboard counts like an ASCII one. A heuristic against storing an account
  /// number by accident, not a guarantee — a number split by letters gets
  /// through.
  static final _looksLikeNumber = RegExp(
    r'\p{Nd}(?:[^\p{L}\p{Nd}]{0,3}\p{Nd}){8,}',
    unicode: true,
  );

  static bool looksLikeNumber(String? text) =>
      text != null && _looksLikeNumber.hasMatch(text);

  static bool referenceLooksLikeNumber(String? reference) =>
      looksLikeNumber(reference);

  /// May [account] be the default of a payment method at [branchId]
  /// (null = business-wide)? Active, and either shared or that branch's own.
  static AccountProblem? defaultProblem(
    FinancialAccount account, {
    required int? branchId,
  }) {
    if (!account.isActive) return AccountProblem.accountUnavailable;
    if (account.branchId != null && account.branchId != branchId) {
      return AccountProblem.accountOfAnotherBranch;
    }
    return null;
  }

  /// The account a payment method pays into at [branchId]: the branch's own
  /// row, else the business-wide one, else none (stage 1 only reports this; no
  /// payment uses it yet).
  static int? effectiveAccountId(
    List<TenderAccountDefault> defaults, {
    required int tenderTypeId,
    required int? branchId,
  }) {
    int? fallback;
    for (final row in defaults) {
      if (row.tenderTypeId != tenderTypeId) continue;
      if (row.branchId == branchId && branchId != null) return row.accountId;
      if (row.branchId == null) fallback = row.accountId;
    }
    return fallback;
  }
}
