/// A record the drain took out of the retry loop for a person to look at.
///
/// Both outbox tables can hold one: `pos_outbox` for a sale, `pos_sync_outbox`
/// for everything else that has to reach the platform (shifts, cash movements,
/// refunds, customers). They share the two columns that say so —
/// `quarantined_at` and `quarantine_code` — and this is the one shape the back
/// office reads them in, so the screen does not have to know there are two
/// queues.
///
/// **Held is not lost and not pending.** It is money that changed hands and
/// that the platform has not got, and the drain will not try it again on its
/// own: the code says retrying would change nothing. Counting it as pending —
/// what the till did before this — showed a number on the sync pill that no
/// pass would ever bring down, which taught people to ignore the pill.
library;

/// Which kind of record is held, and therefore which queue it lives in.
///
/// An enum and not the wire `event_type`, so the label switch is total: a sixth
/// lifecycle event added to the outbox's CHECK without a sentence here fails to
/// compile in `AdminText.heldSyncKind`, rather than showing `cash_movement` to
/// a business owner.
enum HeldSyncKind {
  /// A settled sale — a row in `pos_outbox`.
  sale(null),
  shiftOpen('shift_open'),
  shiftClose('shift_close'),
  cashMovement('cash_movement'),
  refund('refund'),
  customer('customer'),

  /// An event type a newer build wrote. Shown, never hidden: it is still a
  /// record the platform has not got.
  other(null);

  const HeldSyncKind(this.wire);

  /// The `pos_sync_outbox.event_type` value, or null for a sale (which lives
  /// in its own table) and for [other].
  final String? wire;

  /// Whether the row lives in `pos_outbox` rather than `pos_sync_outbox`.
  bool get isSale => this == HeldSyncKind.sale;

  static HeldSyncKind fromEventType(String eventType) {
    for (final kind in values) {
      if (kind.wire == eventType) return kind;
    }
    return HeldSyncKind.other;
  }
}

/// Why a record is held — the `quarantine_code` on its row.
///
/// The first six are the platform's own refusals (POS-BE-019), the ones
/// `OutboxDrain.classify` decides condemn the record rather than the moment.
/// The last four are the till's: records it held **before** sending, because
/// sending would have been wrong. [unknown] is a code from a newer build or a
/// newer platform, worded generically rather than shown raw.
///
/// `MALFORMED_ACK` is deliberately absent. It is a *deferred* error written to
/// `last_error` — the record is fine and the network was not — so it is never a
/// quarantine code and never appears here.
enum QuarantineCode {
  validationFailed('VALIDATION_FAILED'),
  idempotencyPayloadMismatch('IDEMPOTENCY_PAYLOAD_MISMATCH'),
  menuItemNotFound('MENU_ITEM_NOT_FOUND'),
  branchNotInTenant('BRANCH_NOT_IN_TENANT'),
  customerNotFound('CUSTOMER_NOT_FOUND'),
  refundExceedsSold('REFUND_EXCEEDS_SOLD'),
  saleNeverQueued('SALE_NEVER_QUEUED'),
  refundHasNoLines('REFUND_HAS_NO_LINES'),
  tenderNotFromPlatform('TENDER_NOT_FROM_PLATFORM'),
  localSourceMissing('LOCAL_SOURCE_MISSING'),
  unknown(null);

  const QuarantineCode(this.wire);

  final String? wire;

  static QuarantineCode fromWire(String? code) {
    if (code == null) return QuarantineCode.unknown;
    for (final value in values) {
      if (value.wire == code) return value;
    }
    return QuarantineCode.unknown;
  }
}

/// One held record, as the Sync pane lists it.
class HeldSyncItem {
  const HeldSyncItem({
    required this.id,
    required this.kind,
    required this.code,
    required this.quarantinedAt,
    required this.attempts,
    this.rawCode,
    this.lastError,
    this.reference,
    this.sourceId,
  });

  /// The outbox row's own id. Unique only within its table, which is why
  /// releasing one needs [kind] as well.
  final int id;

  final HeldSyncKind kind;
  final QuarantineCode code;

  /// The code exactly as the row carries it — kept beside [code] so that an
  /// [QuarantineCode.unknown] can still be read aloud to support.
  final String? rawCode;

  /// What the platform, or the drain, said. Untranslated on purpose: it is the
  /// sentence support will ask for, and a translation of it is a paraphrase.
  final String? lastError;

  /// The sale's local invoice number, for a sale. Null for the rest: they have
  /// no number a cashier would recognise, and [sourceId] is what support asks
  /// for.
  final String? reference;

  /// The id of the shift, movement, refund or customer behind a lifecycle
  /// record. Null for a sale, whose [reference] says more.
  final int? sourceId;

  final DateTime quarantinedAt;

  /// Conversations with the platform so far. Zero for a record the till held
  /// before it ever sent it.
  final int attempts;
}
