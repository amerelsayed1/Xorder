<?php

namespace App\Services;

use App\Models\Branch;
use App\Models\MenuItem;
use App\Models\Plan;
use App\Models\Restaurant;

/**
 * Enforces per-plan resource caps on dashboard creates. Restaurants reference
 * their plan by name (subscription_plan); an unknown plan or a null limit
 * means unlimited, so existing tenants are never blocked retroactively.
 */
class PlanLimitService
{
    /** Returns the exceeded limit, or null when the create is allowed. */
    public function itemLimitReached(Restaurant $restaurant): ?int
    {
        $max = $this->plan($restaurant)?->max_items;

        // Counts are tenant-scoped by the global RestaurantScope.
        return ($max !== null && MenuItem::count() >= $max) ? $max : null;
    }

    /** Returns the exceeded limit, or null when the create is allowed. */
    public function branchLimitReached(Restaurant $restaurant): ?int
    {
        $max = $this->plan($restaurant)?->max_branches;

        return ($max !== null && Branch::count() >= $max) ? $max : null;
    }

    private function plan(Restaurant $restaurant): ?Plan
    {
        if (! $restaurant->subscription_plan) {
            return null;
        }

        return Plan::where('name', $restaurant->subscription_plan)->first();
    }
}
