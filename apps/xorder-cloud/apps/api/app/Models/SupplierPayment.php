<?php

namespace App\Models;

use App\Enums\PaymentVoidReason;
use App\Enums\SupplierPaymentMethod;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * CB-09 slice c: money paid to a supplier, per branch.
 *
 * Allocated to zero or more of the supplier's invoices; the unallocated rest
 * is on account. Never edited: a wrong payment is voided (its allocations stop
 * counting) and entered again. Written only by SupplierLedgerService, which
 * audits, so the model is not Auditable.
 */
class SupplierPayment extends Model
{
    use BelongsToRestaurant;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'branch_id' => 'integer',
            'supplier_id' => 'integer',
            'method' => SupplierPaymentMethod::class,
            'amount_minor' => 'integer',
            'exponent' => 'integer',
            'paid_at' => 'date:Y-m-d',
            'pos_cash_movement_id' => 'integer',
            'voided_at' => 'datetime',
            'void_reason' => PaymentVoidReason::class,
        ];
    }

    public function isVoided(): bool
    {
        return $this->voided_at !== null;
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(SupplierPaymentAllocation::class)->orderBy('id');
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function cashMovement(): BelongsTo
    {
        return $this->belongsTo(PosCashMovement::class, 'pos_cash_movement_id');
    }
}
