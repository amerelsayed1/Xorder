<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class OrderItem extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'order_id', 'order_round_id', 'name', 'quantity', 'variant', 'options', 'note',
        'unit_price', 'line_total',
    ];

    protected function casts(): array
    {
        return [
            'options' => 'array', 'quantity' => 'integer',
            'unit_price' => 'decimal:2', 'line_total' => 'decimal:2',
            'unit_price_minor' => 'integer', 'line_total_minor' => 'integer',
            // POS-BE-010: the counter a refund checks under a row lock.
            'refunded_quantity' => 'integer',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function round(): BelongsTo
    {
        return $this->belongsTo(OrderRound::class, 'order_round_id');
    }
}
