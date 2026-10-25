import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/cloud/outbox_drain.dart';
import 'package:xorder_pos/domain/models/held_sync.dart';

/// The held-record vocabulary agrees with the drain that writes it.
///
/// The two lists live in different layers — the drain decides which codes
/// condemn a record, the domain names them for a person — and nothing but this
/// file says they have to match. A code the drain started quarantining on
/// without a case here would be shown as "held for a reason this version does
/// not recognise" on the very build that wrote it.
void main() {
  test('every code the drain quarantines on is one the screen can name', () {
    const platformCodes = [
      'VALIDATION_FAILED',
      'IDEMPOTENCY_PAYLOAD_MISMATCH',
      'MENU_ITEM_NOT_FOUND',
      'BRANCH_NOT_IN_TENANT',
      'CUSTOMER_NOT_FOUND',
      'REFUND_EXCEEDS_SOLD',
    ];
    for (final code in platformCodes) {
      expect(OutboxDrain.classify(code), DrainAction.quarantine, reason: code);
      expect(QuarantineCode.fromWire(code), isNot(QuarantineCode.unknown));
    }

    // The till's own holds.
    for (final code in [
      OutboxDrain.tenderNotFromPlatform,
      OutboxDrain.refundHasNoLines,
      'SALE_NEVER_QUEUED',
      'LOCAL_SOURCE_MISSING',
    ]) {
      expect(QuarantineCode.fromWire(code), isNot(QuarantineCode.unknown));
    }
  });

  test('every named code round-trips through its wire value', () {
    for (final code in QuarantineCode.values) {
      if (code == QuarantineCode.unknown) continue;
      expect(QuarantineCode.fromWire(code.wire), code);
    }
  });

  test('MALFORMED_ACK is a deferral, never a hold', () {
    // It goes in `last_error` on a row that stays in the loop. If it ever
    // became a quarantine code, a captive portal would strand sales.
    expect(OutboxDrain.classify(OutboxDrain.malformedAck), DrainAction.defer);
    expect(
      QuarantineCode.fromWire(OutboxDrain.malformedAck),
      QuarantineCode.unknown,
    );
  });

  test('a code from a newer build is unknown, not dropped', () {
    expect(QuarantineCode.fromWire('SOMETHING_NEW'), QuarantineCode.unknown);
    expect(QuarantineCode.fromWire(null), QuarantineCode.unknown);
  });

  test('every lifecycle event type the outbox accepts has a kind', () {
    // The values in `pos_sync_outbox_event_known` (migration 51).
    const accepted = {
      'shift_open': HeldSyncKind.shiftOpen,
      'shift_close': HeldSyncKind.shiftClose,
      'cash_movement': HeldSyncKind.cashMovement,
      'refund': HeldSyncKind.refund,
      'customer': HeldSyncKind.customer,
    };
    accepted.forEach((wire, kind) {
      expect(HeldSyncKind.fromEventType(wire), kind, reason: wire);
      expect(kind.isSale, isFalse);
    });
    expect(HeldSyncKind.fromEventType('stock_count'), HeldSyncKind.other);
    expect(HeldSyncKind.sale.isSale, isTrue);
  });
}
