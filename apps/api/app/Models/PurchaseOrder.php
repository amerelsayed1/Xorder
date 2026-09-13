<?php

namespace App\Models;

use App\Enums\PurchaseStatus;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * CB-09 slice b: what a business asked a supplier for, per branch.
 *
 * Nothing on it is mass-assignable. Every write goes through
 * PurchaseOrderService or ReceivingService, which lock the row and re-read
 * the status under the lock, and which write the audit trail themselves
 * (created, updated, sent, cancelled, received). The model is deliberately
 * not Auditable: a status change would otherwise be logged twice, once as a
 * generic "updated" and once as what actually happened.
 */
class PurchaseOrder extends Model
{
    use BelongsToRestaurant;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'status' => PurchaseStatus::class,
            'branch_id' => 'integer',
            'supplier_id' => 'integer',
            'exponent' => 'integer',
            'subtotal_minor' => 'integer',
            'tax_minor' => 'integer',
            'total_minor' => 'integer',
            'ordered_at' => 'datetime',
            'expected_at' => 'date:Y-m-d',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(PurchaseOrderLine::class)->orderBy('sort_order')->orderBy('id');
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
