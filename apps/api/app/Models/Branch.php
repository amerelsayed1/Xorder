<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

class Branch extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'name_ar',
        'name_en',
        'address',
        'phone',
        'whatsapp_number',
        'opening_hours',
        'map_url',
        'latitude',
        'longitude',
        'is_open',
        'is_active',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'is_open' => 'boolean',
            'is_active' => 'boolean',
            'latitude' => 'float',
            'longitude' => 'float',
        ];
    }
}
