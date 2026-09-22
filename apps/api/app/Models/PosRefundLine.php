<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** POS-BE-010: one original order line, and how much of it went back. */
class PosRefundLine extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'quantity' => 'integer',
            'unit_price_minor' => 'integer',
            'amount_minor' => 'integer',
        ];
    }

    public function refund(): BelongsTo
    {
        return $this->belongsTo(PosRefund::class, 'pos_refund_id');
    }

    public function orderItem(): BelongsTo
    {
        return $this->belongsTo(OrderItem::class);
    }
}
