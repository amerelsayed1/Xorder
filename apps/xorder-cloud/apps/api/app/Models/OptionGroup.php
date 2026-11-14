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
        'apply_scope',
        'name_ar',
        'name_en',
        'display_name_ar',
        'display_name_en',
        'is_required',
        'is_variant',
        'max_select',
        'sort_order',
    ];

    /** How broadly a global group applies to items. */
    public const SCOPE_ITEMS = 'items';       // attached per item (default)

    public const SCOPE_CATEGORIES = 'categories'; // every item in linked categories

    public const SCOPE_ALL = 'all';           // every item in the restaurant (general)

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

    /**
     * The heading a diner should see for this group in the given language.
     *
     * Falls back to the library name, so a group whose one name already reads
     * well on the menu needs no second entry — which is every group that
     * existed before the two were split.
     */
    public function publicName(string $lang): ?string
    {
        $column = $lang === 'ar' ? 'ar' : 'en';

        return filled($this->{"display_name_{$column}"})
            ? $this->{"display_name_{$column}"}
            : $this->{"name_{$column}"};
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

    /** Categories a category-scoped group auto-applies to (via the pivot). */
    public function categories(): BelongsToMany
    {
        return $this->belongsToMany(Category::class, 'option_group_category')
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

    /** Global groups that auto-apply to items by category or restaurant-wide. */
    public function scopeAutoApplied(Builder $query): Builder
    {
        return $query->where('is_global', true)
            ->whereIn('apply_scope', [self::SCOPE_ALL, self::SCOPE_CATEGORIES]);
    }
}
