<?php

namespace App\Models;

use App\Enums\CurrencyEnum;
use Illuminate\Database\Eloquent\Model;

class Plan extends Model
{
    protected $fillable = [
        'name',
        'price',
        'currency',
        'features',
        'max_items',
        'max_branches',
        'is_active',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'currency' => CurrencyEnum::class,
            'features' => 'array',
            'is_active' => 'boolean',
        ];
    }
}
