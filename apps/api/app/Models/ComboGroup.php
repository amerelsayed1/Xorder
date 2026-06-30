<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ComboGroup extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'combo_id',
        'name_ar',
        'name_en',
        'max_select',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'max_select' => 'integer',
            'sort_order' => 'integer',
        ];
    }

    public function combo(): BelongsTo
    {
        return $this->belongsTo(Combo::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(ComboGroupItem::class)->orderBy('sort_order')->orderBy('id');
    }
}
