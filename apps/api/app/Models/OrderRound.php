<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class OrderRound extends Model
{
    use BelongsToRestaurant;

    protected $fillable = ['order_id', 'menu_session_id', 'sequence', 'total', 'note', 'submitted_at'];

    protected function casts(): array
    {
        return ['total' => 'decimal:2', 'submitted_at' => 'datetime'];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class);
    }
}
