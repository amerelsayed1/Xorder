<?php

namespace App\Enums;

/**
 * CB-09: where a purchase order has got to. The till's five values
 * (xorder-pos lib/domain/models/purchase_order.dart, PurchaseStatus) with its
 * isEditable / isOpen / isClosed rules.
 *
 * The status is never set from a request. PurchaseOrderService moves it
 * (send, cancel) and ReceivingService derives it from the lines, both under
 * a lock on the order row with the current status re-read under that lock.
 */
enum PurchaseStatus: string
{
    case DRAFT = 'draft';
    case SENT = 'sent';
    case PARTIALLY_RECEIVED = 'partially_received';
    case RECEIVED = 'received';
    case CANCELLED = 'cancelled';

    /** The lines may still be changed. */
    public function isEditable(): bool
    {
        return $this === self::DRAFT;
    }

    /** Goods may still be booked in against it. */
    public function isOpen(): bool
    {
        return $this === self::SENT || $this === self::PARTIALLY_RECEIVED;
    }

    /** Finished, one way or the other. */
    public function isClosed(): bool
    {
        return $this === self::RECEIVED || $this === self::CANCELLED;
    }

    /**
     * PurchaseEngine.cancel: from draft or sent only. Refused once anything
     * has arrived: goods in the kitchen are not cancellable.
     */
    public function canCancel(): bool
    {
        return $this === self::DRAFT || $this === self::SENT;
    }

    /**
     * CB-09 D11: the way out of a part delivery is to close the difference,
     * not to cancel. Only a partly received order can be closed short; it
     * becomes `received` (the till's own meaning: "all of it arrived, or
     * somebody closed the difference deliberately"), marked closed short.
     */
    public function canCloseShort(): bool
    {
        return $this === self::PARTIALLY_RECEIVED;
    }
}
