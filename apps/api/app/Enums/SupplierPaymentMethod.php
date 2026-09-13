<?php

namespace App\Enums;

/**
 * CB-09 slice c: how money left the business to pay a supplier. The till's
 * SupplierPaymentMethod (supplier_invoice.dart), verbatim.
 *
 * Deliberately not the POS tender types: those describe how a customer pays
 * the business, these how the business pays somebody else.
 */
enum SupplierPaymentMethod: string
{
    case CASH = 'cash';
    case BANK_TRANSFER = 'bank_transfer';
    case CHEQUE = 'cheque';
    case CARD = 'card';
    case OTHER = 'other';

    /** A cheque or a transfer is identified by a number a bank can find. Cash is not. */
    public function expectsReference(): bool
    {
        return $this === self::CHEQUE || $this === self::BANK_TRANSFER || $this === self::CARD;
    }
}
