<?php

namespace App\Services;

use App\Models\Plan;
use App\Models\Restaurant;

/**
 * Derives a restaurant's feature flags from its subscription plan. The plan
 * strictly decides which capabilities appear: whenever a restaurant is
 * provisioned or its plan changes, its restaurant_features are re-synced from
 * the plan's feature_keys (auto-expanding prerequisites via Feature::resolve
 * inside RestaurantFeatureService).
 *
 * Restaurants reference their plan by name (subscription_plan). A plan that is
 * unknown or predates the entitlement set (feature_keys IS NULL) is treated as
 * "no opinion" so features are left untouched rather than wiped — existing
 * tenants are never silently stripped of capabilities.
 */
class PlanEntitlementService
{
    public function __construct(
        private readonly RestaurantFeatureService $features,
    ) {}

    /**
     * Re-derive and persist a restaurant's feature flags from its current plan.
     * A no-op when the plan is unknown or has no entitlement set.
     */
    public function sync(Restaurant $restaurant): void
    {
        $plan = $this->planFor($restaurant);

        if ($plan === null || $plan->feature_keys === null) {
            return;
        }

        $this->features->apply($restaurant, $plan->featureMap());
    }

    /**
     * The feature map to apply for a restaurant, preferring the plan's
     * entitlement set and falling back to $fallback (e.g. Feature::defaultSet
     * for self-serve signup) when the plan carries no entitlements.
     *
     * @param  array<string,bool>  $fallback
     * @return array<string,bool>
     */
    public function resolvedMapFor(Restaurant $restaurant, array $fallback = []): array
    {
        $plan = $this->planFor($restaurant);

        if ($plan !== null && $plan->feature_keys !== null) {
            return $plan->featureMap();
        }

        return $fallback;
    }

    private function planFor(Restaurant $restaurant): ?Plan
    {
        if (! $restaurant->subscription_plan) {
            return null;
        }

        return Plan::where('name', $restaurant->subscription_plan)->first();
    }
}
