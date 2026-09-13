<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * CB-09 slice c: part (or all) of a payment, pointed at one invoice.
 *
 * Written once, with its payment, by SupplierLedgerService under a lock on the
 * invoice row; never updated. It counts only while its payment is live.
 */
class SupplierPaymentAllocation extends Model
{
    use BelongsToRestaurant;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'supplier_payment_id' => 'integer',
            'supplier_invoice_id' => 'integer',
            'amount_minor' => 'integer',
        ];
    }

    public function payment(): BelongsTo
    {
        return $this->belongsTo(SupplierPayment::class, 'supplier_payment_id');
    }

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(SupplierInvoice::class, 'supplier_invoice_id');
    }
}
