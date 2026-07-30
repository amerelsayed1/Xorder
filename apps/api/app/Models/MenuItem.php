<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Collection;

class MenuItem extends Model
{
    use Auditable, BelongsToRestaurant, HasFactory, SoftDeletes;

    protected $fillable = [
        'category_id',
        'name_ar',
        'name_en',
        'description_ar',
        'description_en',
        'price',
        'discounted_price',
        'image_url',
        'is_available',
        'is_featured',
        'display_order',
    ];

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'discounted_price' => 'decimal:2',
            'is_available' => 'boolean',
            'is_featured' => 'boolean',
            'display_order' => 'integer',
        ];
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    /** Inline groups defined directly on this item (menu_item_id set). */
    public function optionGroups(): HasMany
    {
        return $this->hasMany(OptionGroup::class)->orderBy('sort_order')->orderBy('id');
    }

    /** Reusable groups from the shared library attached to this item (pivot). */
    public function sharedOptionGroups(): BelongsToMany
    {
        return $this->belongsToMany(OptionGroup::class, 'menu_item_option_group')
            ->withPivot('sort_order')
            ->withTimestamps()
            ->orderByPivot('sort_order');
    }

    /**
     * Inline + shared groups merged into a single list, ordered by the position
     * the admin gave each one. Both flavours share one sort_order sequence per
     * item (inline on the row, shared on the pivot), so a plain sortBy is exact.
     * Each returned group carries `is_shared` so callers can tell them apart.
     * Relations must be eager-loaded first; unloaded ones contribute nothing.
     */
    public function orderedOptionGroups(): Collection
    {
        $inline = ($this->relationLoaded('optionGroups') ? $this->optionGroups : collect())
            ->map(fn ($g) => tap($g)->setAttribute('is_shared', false)
                ->setAttribute('_sort', $g->sort_order));

        $shared = ($this->relationLoaded('sharedOptionGroups') ? $this->sharedOptionGroups : collect())
            ->map(fn ($g) => tap($g)->setAttribute('is_shared', true)
                ->setAttribute('_sort', $g->pivot->sort_order));

        return $inline->concat($shared)->sortBy('_sort')->values();
    }
}
