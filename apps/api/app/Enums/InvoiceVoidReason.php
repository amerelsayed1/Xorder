<?php

namespace App\Enums;

/**
 * CB-09 slice c: why a supplier invoice was voided. The till's six
 * `invoice_void` reason codes (xorder-pos migration 31), verbatim. A code,
 * not a sentence, so "how many did we void for entered twice last month" has
 * an answer. `other` requires a note, as on the till.
 *
 * Restaurant-editable reason lists are out of scope (design §4.9).
 */
enum InvoiceVoidReason: string
{
    case ENTERED_TWICE = 'entered_twice';
    case WRONG_SUPPLIER = 'wrong_supplier';
    case WRONG_AMOUNT = 'wrong_amount';
    case CREDIT_NOTE = 'credit_note';
    case GOODS_RETURNED = 'goods_returned';
    case OTHER = 'other';

    public function requiresNote(): bool
    {
        return $this === self::OTHER;
    }
}
