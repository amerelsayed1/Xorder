<?php

namespace App\Models\Concerns;

use App\Models\Restaurant;
use App\Models\Scopes\RestaurantScope;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Applied to tenant-owned models (Category, MenuItem). Adds the global
 * RestaurantScope to every query and auto-stamps restaurant_id on insert from
 * the resolved tenant context, so callers never set it from request input.
 */
trait BelongsToRestaurant
{
    public static function bootBelongsToRestaurant(): void
    {
        static::addGlobalScope(new RestaurantScope);

        static::creating(function ($model): void {
            if ($model->restaurant_id === null) {
                $model->restaurant_id = TenantContext::restaurantId();
            }
        });
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }
}
