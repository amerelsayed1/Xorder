<?php

namespace App\Services;

use App\Enums\Feature;
use App\Models\Restaurant;
use Illuminate\Support\Facades\Auth;

class RestaurantFeatureService
{
    /**
     * Persist a restaurant's feature flags from a requested key => bool map,
     * auto-enabling any prerequisites (Feature::resolve). Idempotent: safe to
     * call on creation and again from the dashboard when toggling.
     *
     * `enabled_by` is stamped from the acting user when available (the Super
     * Admin in the wizard) and left null for unauthenticated flows (self-serve
     * signup).
     *
     * @param  array<string,bool>  $requested
     */
    public function apply(Restaurant $restaurant, array $requested): void
    {
        $resolved = Feature::resolve($requested);
        $actorId = Auth::id();

        foreach ($resolved as $key => $enabled) {
            $restaurant->features()->updateOrCreate(
                ['feature_key' => $key],
                [
                    'is_enabled' => $enabled,
                    'enabled_at' => $enabled ? now() : null,
                    'enabled_by' => $enabled ? $actorId : null,
                ],
            );
        }
    }
}
