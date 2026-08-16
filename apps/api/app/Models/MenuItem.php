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

        // Category-/restaurant-wide groups injected by the menu builder. They
        // carry no per-item sort_order, so they trail the explicit ones.
        $auto = ($this->autoOptionGroups ?? collect())
            ->map(fn ($g) => tap($g)->setAttribute('is_shared', true)
                ->setAttribute('_sort', 1_000_000 + $g->sort_order));

        return $inline->concat($shared)->concat($auto)
            ->unique('id') // guard against a group applying via more than one path
            ->sortBy('_sort')->values();
    }

    /**
     * Groups that auto-apply to this item by category or restaurant-wide.
     * Populated by the menu builder from a single restaurant-level query, so
     * per-item resolution stays N+1-free. Declared as a real property so it
     * bypasses Eloquent's attribute magic.
     */
    public ?Collection $autoOptionGroups = null;

    /**
     * Pick, from the restaurant's auto-applied groups, the ones that target
     * this item (restaurant-wide, or a category this item belongs to).
     */
    public function withAutoOptionGroups(Collection $groups): static
    {
        $this->autoOptionGroups = $groups->filter(function ($g) {
            if ($g->apply_scope === OptionGroup::SCOPE_ALL) {
                return true;
            }

            return $g->apply_scope === OptionGroup::SCOPE_CATEGORIES
                && $g->categories->contains('id', $this->category_id);
        })->values();

        return $this;
    }

    /**
     * The size the diner gets before touching anything: the first available
     * option of the item's first variant group, in display order. The menu app
     * pre-selects exactly this row (defaultSelection() in the menu SPA), and a
     * variant option REPLACES the item price rather than adding to it — so this
     * option, not the item's own price column, is what an untouched "add to
     * cart" charges. Null when the item has no variant group, i.e. it really is
     * priced by its own column.
     *
     * Reordering the sizes therefore changes the item's advertised price: the
     * first row IS the default. That's intended, and the form says so.
     *
     * Relations must be eager-loaded — orderedOptionGroups() only sees what is.
     */
    public function defaultVariantOption(): ?Option
    {
        $group = $this->orderedOptionGroups()->first(fn ($g) => $g->is_variant);

        // Options come back in sort_order; unavailable ones are stripped from
        // the public menu, so the diner's default is the first AVAILABLE row.
        return $group?->options->firstWhere('is_available', true);
    }

    /**
     * The [price, discounted_price] pair the menu must advertise. Returned as a
     * pair so both figures always come from one source — pairing a size's price
     * with the item's own discount would render a strike-through that no
     * selection ever charges.
     */
    public function displayPricing(): array
    {
        $default = $this->defaultVariantOption();

        return $default
            ? [$default->price, $default->discounted_price]
            : [$this->price, $this->discounted_price];
    }
}
