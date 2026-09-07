<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * BE-A01: one tender against one order. Split tender is the normal case at a
 * till — "300 cash + 200 card" is two rows. Each row carries its OWN
 * client_transaction_id (decision a), because settling an open bill later,
 * possibly from another terminal, needs its own dedupe key.
 */
class OrderPayment extends Model
{
    use BelongsToRestaurant;

    /** Created exclusively by PosOrderService via forceFill. */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'amount_minor' => 'integer',
            'received_at' => 'datetime',
            'received_server_at' => 'datetime',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function tenderType(): BelongsTo
    {
        return $this->belongsTo(TenderType::class);
    }
}
