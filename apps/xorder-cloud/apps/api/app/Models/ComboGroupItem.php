<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ComboGroupItem extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'combo_group_id',
        'menu_item_id',
        'extra_price',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'extra_price' => 'decimal:2',
            'sort_order' => 'integer',
        ];
    }

    public function comboGroup(): BelongsTo
    {
        return $this->belongsTo(ComboGroup::class);
    }

    public function menuItem(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class);
    }
}
