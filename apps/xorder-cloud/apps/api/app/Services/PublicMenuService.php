<?php

namespace App\Services;

use App\Enums\SubscriptionStatus;
use App\Models\OptionGroup;
use App\Models\Restaurant;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Collection;

class PublicMenuService
{
    /**
     * Resolve a restaurant by slug. Returns null if it does not exist.
     * Throws nothing — visibility is a separate concern (see isVisible()).
     */
    public function findBySlug(string $slug): ?Restaurant
    {
        return Restaurant::where('slug', $slug)->with('features')->first();
    }

    /**
     * Whether the public menu should be shown. ACTIVE status is required.
     * EXPIRED subscriptions hide the menu only when configured to.
     */
    public function isVisible(Restaurant $restaurant): bool
    {
        if (! $restaurant->isPubliclyVisible()) {
            return false;
        }

        if (config('platform.subscription.hide_menu_when_expired')
            && $restaurant->subscription_status === SubscriptionStatus::EXPIRED) {
            return false;
        }

        return true;
    }

    /**
     * Load the visible menu for a restaurant:
     *  - only active categories
     *  - only categories that contain at least one (non-deleted) item
     *  - items ordered by display_order; unavailable items are INCLUDED
     *    (rendered with a badge), deleted items are excluded by soft-delete
     *
     * @return array{categories: Collection, featured: Collection}
     */
    public function loadMenu(Restaurant $restaurant): array
    {
        // Pin tenant context so every scoped query targets this restaurant.
        TenantContext::overrideId($restaurant->id);

        try {
            $categories = $restaurant->categories()
                ->where('is_active', true)
                ->whereHas('menuItems')
                ->with(['menuItems' => fn ($q) => $q->orderBy('display_order')->orderBy('id')->with(['optionGroups.options', 'sharedOptionGroups.options'])])
                ->orderBy('display_order')
                ->orderBy('id')
                ->get();

            // Categories answer "am I being served right now?" in the
            // restaurant's timezone, so give each one the restaurant it already
            // belongs to instead of letting the resource lazy-load it per row.
            $categories->each(fn ($category) => $category->setRelation('restaurant', $restaurant));

            $offHours = $categories->reject->isAvailableNow()->pluck('id')->all();

            $featured = $restaurant->menuItems()
                ->where('is_featured', true)
                ->where('is_available', true)
                // The featured rail is a shortcut into the menu, so it must not
                // offer what the menu itself is not serving yet — otherwise a
                // breakfast item stays one tap from the cart all afternoon. The
                // item keeps its place inside its own category, where the
                // section says when it comes back.
                ->when($offHours !== [], fn ($q) => $q->whereNotIn('category_id', $offHours))
                ->with(['optionGroups.options', 'sharedOptionGroups.options'])
                ->orderBy('display_order')
                ->orderBy('id')
                ->get();

            $branches = $restaurant->branches()
                ->where('is_active', true)
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get();

            // Expose the loaded branches to the restaurant resource so the menu
            // header/info sheet can source hours (and other per-branch details)
            // from the primary branch, which is where they now live.
            $restaurant->setRelation('branches', $branches);

            $combos = $restaurant->combos()
                ->where('is_active', true)
                ->with('groups.items.menuItem')
                ->get();

            // Library groups that auto-apply by category or restaurant-wide.
            // Loaded once, then merged into each item by its category — so the
            // per-item resolution in orderedOptionGroups() stays N+1-free.
            $autoGroups = OptionGroup::autoApplied()
                ->with(['options', 'categories:id'])
                ->orderBy('name_en')
                ->orderBy('name_ar')
                ->orderBy('id')
                ->get();

            foreach ($categories as $category) {
                foreach ($category->menuItems as $item) {
                    $item->withAutoOptionGroups($autoGroups);
                }
            }
            foreach ($featured as $item) {
                $item->withAutoOptionGroups($autoGroups);
            }

            return [
                'categories' => $categories,
                'featured' => $featured,
                'branches' => $branches,
                'combos' => $combos,
            ];
        } finally {
            TenantContext::clearOverride();
        }
    }
}
