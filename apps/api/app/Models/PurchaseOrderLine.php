<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use App\Support\StockCosting;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * CB-09 slice b: one thing ordered. `restaurant_id` is stamped from the
 * order, never from input. Written only by PurchaseOrderService (a draft's
 * lines are replaced wholesale) and ReceivingService (received_milli).
 */
class PurchaseOrderLine extends Model
{
    use BelongsToRestaurant;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'purchase_order_id' => 'integer',
            'stock_item_id' => 'integer',
            'ordered_milli' => 'integer',
            'received_milli' => 'integer',
            'unit_cost_minor' => 'integer',
            'tax_rate_bp' => 'integer',
            'sort_order' => 'integer',
        ];
    }

    public function purchaseOrder(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrder::class);
    }

    public function stockItem(): BelongsTo
    {
        return $this->belongsTo(StockItem::class);
    }

    /** The cost of what was ordered, before tax: the one rounding point. */
    public function lineTotalMinor(): int
    {
        return StockCosting::costAt($this->ordered_milli, $this->unit_cost_minor);
    }

    /** What is still owed. Never negative: over-delivery closes at zero. */
    public function outstandingMilli(): int
    {
        return max(0, $this->ordered_milli - $this->received_milli);
    }
}
