<?php

namespace App\Services;

use App\Enums\SubscriptionStatus;
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
        return Restaurant::where('slug', $slug)->first();
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
                ->with(['menuItems' => fn ($q) => $q->orderBy('display_order')->orderBy('id')->with('optionGroups.options')])
                ->orderBy('display_order')
                ->orderBy('id')
                ->get();

            $featured = $restaurant->menuItems()
                ->where('is_featured', true)
                ->where('is_available', true)
                ->with('optionGroups.options')
                ->orderBy('display_order')
                ->orderBy('id')
                ->get();

            $branches = $restaurant->branches()->where('is_active', true)->get();

            $combos = $restaurant->combos()
                ->where('is_active', true)
                ->with('groups.items.menuItem')
                ->get();

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
