<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use LogicException;

/**
 * CB-09 slice b: one line of the stock ledger. APPEND-ONLY.
 *
 * Correcting stock is a new movement (slice d), never an edit to an old one:
 * each row records the balance and average that resulted from it, so an
 * edited row would silently falsify every later one. The model refuses
 * update and delete. (A raw query-builder update bypasses model events; no
 * code path does that, and nothing exposes one.)
 */
class StockMovement extends Model
{
    use BelongsToRestaurant;

    public const UPDATED_AT = null;

    /** The till's seven kinds. Slice b writes only `receipt`. */
    public const KINDS = ['receipt', 'sale', 'waste', 'adjustment', 'opening', 'transfer_in', 'transfer_out'];

    protected $guarded = ['*'];

    protected static function booted(): void
    {
        static::updating(function () {
            throw new LogicException('Stock movements are append-only.');
        });
        static::deleting(function () {
            throw new LogicException('Stock movements are append-only.');
        });
    }

    protected function casts(): array
    {
        return [
            'branch_id' => 'integer',
            'stock_item_id' => 'integer',
            'quantity_milli' => 'integer',
            'unit_cost_minor' => 'integer',
            'balance_milli' => 'integer',
            'average_cost_minor' => 'integer',
            'purchase_order_id' => 'integer',
            'purchase_order_line_id' => 'integer',
            'occurred_at' => 'datetime',
        ];
    }

    public function purchaseOrder(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrder::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
