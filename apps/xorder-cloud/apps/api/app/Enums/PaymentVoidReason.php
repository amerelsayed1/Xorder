<?php

namespace App\Enums;

/**
 * CB-09 slice c: why a supplier payment was voided. The till's six
 * `payment_void` reason codes (xorder-pos migration 31), verbatim. `other`
 * requires a note.
 */
enum PaymentVoidReason: string
{
    case WRONG_AMOUNT = 'wrong_amount';
    case WRONG_INVOICE = 'wrong_invoice';
    case WRONG_SUPPLIER = 'wrong_supplier';
    case CHEQUE_BOUNCED = 'cheque_bounced';
    case ENTERED_TWICE = 'entered_twice';
    case OTHER = 'other';

    public function requiresNote(): bool
    {
        return $this === self::OTHER;
    }
}
