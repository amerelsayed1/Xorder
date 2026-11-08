/// A receipt on its way to Egypt's tax authority, and how far it has got.
library;

/// Where a receipt is between the till and the authority.
///
/// Six states, not two, because the interesting failures live between them: a
/// receipt that was built but never signed is a different problem from one
/// that was signed and never sent, and both are different from one the
/// authority looked at and refused.
enum EtaStatus {
  /// Built and fingerprinted. Not yet sealed.
  pending('pending'),

  /// Sealed and ready to go. This is the state a till sits in through an
  /// outage, and it is the safe one: the document is final and the deadline
  /// is the only thing still running.
  signed('signed'),

  /// Handed over, no verdict yet. ETA accept a submission and validate it
  /// afterwards, so this is a real state and not a transient one.
  submitted('submitted'),

  /// Filed. The only state that discharges the obligation.
  accepted('accepted'),

  /// Refused, with a reason. Needs a person: the fix is almost always a
  /// wrong field in the receipt profile, not a retry.
  rejected('rejected'),

  /// Given up on deliberately, by somebody who said why. Never automatic.
  cancelled('cancelled');

  const EtaStatus(this.wire);

  final String wire;

  static EtaStatus fromWire(String value) => EtaStatus.values.firstWhere(
    (status) => status.wire == value,
    // An unknown status from a newer schema is not something to guess at: a
    // till that read it as `accepted` would stop chasing a receipt that was
    // never filed.
    orElse: () => throw ArgumentError.value(value, 'status', 'unknown'),
  );

  /// Still the business's problem.
  bool get isOutstanding => this != accepted && this != cancelled;

  /// Nothing more will happen without a person.
  bool get needsAttention => this == rejected;
}

/// One queued receipt, as the screen and the drain read it.
class EtaSubmission {
  const EtaSubmission({
    required this.id,
    required this.orderId,
    required this.uuid,
    required this.receiptNumber,
    required this.issuedAt,
    required this.status,
    required this.deviceSerial,
    this.attempts = 0,
    this.submittedAt,
    this.errorMessage,
    this.longId,
    this.refundId,
  });

  final int id;
  final int orderId;
  final int? refundId;
  final String uuid;
  final String receiptNumber;
  final DateTime issuedAt;
  final EtaStatus status;
  final String deviceSerial;
  final int attempts;
  final DateTime? submittedAt;
  final String? errorMessage;

  /// ETA's own long identifier, which is what a QR code points at.
  final String? longId;

  /// How long this has been outstanding, against [now].
  ///
  /// Takes the clock rather than reading it, so the screen and its test see
  /// the same number.
  Duration age(DateTime now) => now.difference(issuedAt);

  /// Egypt's window is 24 hours from issuance.
  static const window = Duration(hours: 24);

  /// Past the deadline and still not filed.
  bool isLate(DateTime now) =>
      status.isOutstanding && age(now) >= window;

  /// Inside the window but close enough to say so. Four hours is a shift.
  bool isDueSoon(DateTime now) =>
      status.isOutstanding &&
      !isLate(now) &&
      age(now) >= window - const Duration(hours: 4);
}

/// What the whole queue looks like at a glance.
///
/// **The screen this feeds is not decoration.** A queue growing where nobody
/// looks is a failure mode this codebase has already been bitten by once, and
/// here the cost of not looking is a legal one.
class EtaQueueSummary {
  const EtaQueueSummary({
    required this.outstanding,
    required this.rejected,
    required this.late,
    required this.oldest,
  });

  static const empty = EtaQueueSummary(
    outstanding: 0,
    rejected: 0,
    late: 0,
    oldest: null,
  );

  final int outstanding;
  final int rejected;
  final int late;

  /// When the oldest outstanding receipt was issued, or null if there is none.
  final DateTime? oldest;

  bool get isClear => outstanding == 0;

  /// Worth interrupting somebody about.
  bool get isUrgent => late > 0 || rejected > 0;
}
