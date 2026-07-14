<?php

namespace App\Models;

use App\Enums\OrderStatus;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

class Order extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'status',
        'items',
        'total',
        'currency',
        'customer_name',
        'customer_phone',
        'note',
        'source',
    ];

    protected function casts(): array
    {
        return [
            'status' => OrderStatus::class,
            'items' => 'array',
            'total' => 'decimal:2',
        ];
    }

    /** Short human reference the restaurant can read back to the customer. */
    public function code(): string
    {
        return 'ORD-'.$this->id;
    }
}
