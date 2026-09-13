<?php

namespace App\Enums;

/**
 * CB-09 slice c, D11: why a part-delivered purchase order was closed short,
 * i.e. why the rest is not coming.
 *
 * The till has no reason scope for this (it has no short-close yet), so this
 * is the smallest honest list. A code rather than free text, as the till does
 * for every other void and reversal; `other` requires a note.
 */
enum PurchaseCloseReason: string
{
    case SUPPLIER_CANNOT_SUPPLY = 'supplier_cannot_supply';
    case NO_LONGER_NEEDED = 'no_longer_needed';
    case REFUSED_ON_DELIVERY = 'refused_on_delivery';
    case OTHER = 'other';

    public function requiresNote(): bool
    {
        return $this === self::OTHER;
    }
}
