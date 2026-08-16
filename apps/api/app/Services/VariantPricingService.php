<?php

namespace App\Services;

use App\Models\MenuItem;
use App\Models\OptionGroup;
use Illuminate\Support\Collection;

/**
 * Keeps a variant-priced item's own price columns equal to its default size.
 *
 * An item whose group is flagged `is_variant` is not priced by menu_items.price
 * at all — the chosen size replaces it, and the first size is the pre-selected
 * default. The columns are still what the dashboard list and the CSV export
 * read, so leaving them stale makes the manager's list disagree with the menu.
 *
 * Resources derive the same figure at read time (MenuItem::displayPricing()),
 * which is what keeps the customer menu correct even between the writes here.
 * This service exists so the stored columns don't drift from that derivation.
 */
class VariantPricingService
{
    /** Auto-applied library groups, loaded once per tenant per request. */
    private array $autoGroups = [];

    /**
     * Re-derive one item's price columns from its default size. A no-op for an
     * item with no variant group — there the owner's own price is the price.
     */
    public function syncItem(MenuItem $item): void
    {
        $item->loadMissing(['optionGroups.options', 'sharedOptionGroups.options']);

        if ($item->autoOptionGroups === null) {
            $item->withAutoOptionGroups($this->autoGroups($item->restaurant_id));
        }

        if (! $default = $item->defaultVariantOption()) {
            return;
        }

        $item->price = $default->price;
        $item->discounted_price = $default->discounted_price;

        // Unchanged values dirty nothing, so this neither writes nor audits.
        $item->save();
    }

    /**
     * Re-sync every item priced by a shared library group whose sizes just
     * changed. Only variant groups move an item's price, so anything else is
     * skipped before touching the database.
     */
    public function syncGroupItems(OptionGroup $group): void
    {
        if (! $group->is_variant) {
            return;
        }

        $this->itemsFor($group)->each(fn (MenuItem $item) => $this->syncItem($item));
    }

    /**
     * The items a shared group applies to, by the path it applies through.
     * A category-/restaurant-wide group reaches items with no pivot row, so the
     * per-item relation alone would miss them.
     */
    private function itemsFor(OptionGroup $group): Collection
    {
        // RestaurantScope is a no-op for a Super Admin and on the console, so
        // the tenant filter is spelled out rather than assumed.
        $items = MenuItem::where('restaurant_id', $group->restaurant_id)
            ->with(['optionGroups.options', 'sharedOptionGroups.options']);

        return match ($group->apply_scope) {
            OptionGroup::SCOPE_ALL => $items->get(),
            OptionGroup::SCOPE_CATEGORIES => $items
                ->whereIn('category_id', $group->categories()->pluck('categories.id'))
                ->get(),
            default => $items
                ->whereIn('id', $group->menuItems()->pluck('menu_items.id'))
                ->get(),
        };
    }

    /**
     * Library groups that apply by category or restaurant-wide. Needed because
     * such a group can be the variant group that prices an item even though the
     * item has no link to it; memoised so a bulk sync stays at one query.
     */
    private function autoGroups(int $restaurantId): Collection
    {
        return $this->autoGroups[$restaurantId] ??= OptionGroup::autoApplied()
            ->where('restaurant_id', $restaurantId)
            ->with(['options', 'categories:id'])
            ->orderBy('name_en')
            ->orderBy('name_ar')
            ->orderBy('id')
            ->get();
    }
}
