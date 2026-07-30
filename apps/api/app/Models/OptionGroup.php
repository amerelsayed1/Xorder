<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class OptionGroup extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'menu_item_id',
        'is_global',
        'name_ar',
        'name_en',
        'is_required',
        'is_variant',
        'max_select',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'is_global' => 'boolean',
            'is_required' => 'boolean',
            'is_variant' => 'boolean',
            'max_select' => 'integer',
            'sort_order' => 'integer',
        ];
    }

    /** The owning item for an inline (per-item) group; null for global groups. */
    public function menuItem(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class);
    }

    /** Items a global group is attached to (via the pivot). */
    public function menuItems(): BelongsToMany
    {
        return $this->belongsToMany(MenuItem::class, 'menu_item_option_group')
            ->withPivot('sort_order')
            ->withTimestamps();
    }

    public function options(): HasMany
    {
        return $this->hasMany(Option::class)->orderBy('sort_order')->orderBy('id');
    }

    /** Reusable groups that live in the shared library (not tied to one item). */
    public function scopeGlobal(Builder $query): Builder
    {
        return $query->where('is_global', true);
    }
}
