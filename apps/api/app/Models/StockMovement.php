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

    /**
     * The till's seven kinds. Slice b writes `receipt`; slice d writes
     * `opening`, `waste` and `adjustment` (a count is an adjustment with
     * reason `stock_count`). `sale` and the transfers have no writer.
     */
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

    /**
     * One row of the ledger as the dashboard reads it (the movements list and
     * the slice-d create response). Load purchaseOrder / createdBy first to
     * avoid a query per row.
     *
     * @return array<string,mixed>
     */
    public function ledgerRow(): array
    {
        return [
            'id' => $this->id,
            'branch_id' => $this->branch_id,
            'stock_item_id' => $this->stock_item_id,
            'kind' => $this->kind,
            'quantity_milli' => $this->quantity_milli,
            'unit_code' => $this->unit_code,
            'unit_cost_minor' => $this->unit_cost_minor,
            'balance_milli' => $this->balance_milli,
            'average_cost_minor' => $this->average_cost_minor,
            'purchase_order_id' => $this->purchase_order_id,
            'purchase_order_reference' => $this->purchase_order_id ? $this->purchaseOrder?->reference : null,
            'reason' => $this->reason,
            'note' => $this->note,
            'occurred_at' => $this->occurred_at?->toIso8601String(),
            'created_by' => $this->createdBy?->name,
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
