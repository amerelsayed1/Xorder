<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use App\Support\StockCosting;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * CB-09 slice b: the position of one stock item in one branch. A cache of
 * the ledger (a moving average is a fold), written only by ReceivingService
 * in the same transaction as the movement, under a row lock. It always
 * equals the last movement's balance and average; StockLedger::replay
 * checks that.
 *
 * It is "received to date", not "on hand": tills don't deduct sales (D4).
 */
class StockLevel extends Model
{
    use BelongsToRestaurant;

    public const CREATED_AT = null;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'branch_id' => 'integer',
            'stock_item_id' => 'integer',
            'quantity_milli' => 'integer',
            'average_cost_minor' => 'integer',
        ];
    }

    public function stockItem(): BelongsTo
    {
        return $this->belongsTo(StockItem::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function valueMinor(): int
    {
        return StockCosting::value($this->quantity_milli, $this->average_cost_minor);
    }
}
