<?php

namespace App\Services;

use App\Enums\RoleEnum;
use App\Models\Branch;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\User;

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
    public function categoryLimitReached(Restaurant $restaurant): ?int
    {
        $max = $this->plan($restaurant)?->max_categories;

        // Counts are tenant-scoped by the global RestaurantScope.
        return ($max !== null && Category::count() >= $max) ? $max : null;
    }

    /**
     * Returns the plan's category cap when adding [$adding] more would pass it,
     * else null. The batch counts whole: a cap of 10 with 8 on file refuses a
     * batch of 3, it does not store two.
     */
    public function categoryLimitWouldBeExceeded(Restaurant $restaurant, int $adding): ?int
    {
        $max = $this->plan($restaurant)?->max_categories;

        return ($max !== null && Category::count() + $adding > $max) ? $max : null;
    }

    /** Returns the exceeded limit, or null when the create is allowed. */
    public function branchLimitReached(Restaurant $restaurant): ?int
    {
        $max = $this->plan($restaurant)?->max_branches;

        return ($max !== null && Branch::count() >= $max) ? $max : null;
    }

    /**
     * Returns the exceeded limit, or null when another staff account is allowed.
     *
     * Counts staff only. The owner holds the subscription rather than occupying
     * a seat under it, so a "3 users" plan means three employees plus the owner
     * — counting the owner would silently sell one fewer seat than advertised.
     */
    public function staffLimitReached(Restaurant $restaurant): ?int
    {
        $max = $this->plan($restaurant)?->max_staff;

        if ($max === null) {
            return null;
        }

        $staff = User::where('restaurant_id', $restaurant->id)
            ->where('role', RoleEnum::RESTAURANT_STAFF)
            ->count();

        return $staff >= $max ? $max : null;
    }

    private function plan(Restaurant $restaurant): ?Plan
    {
        if (! $restaurant->subscription_plan) {
            return null;
        }

        return Plan::where('name', $restaurant->subscription_plan)->first();
    }
}
