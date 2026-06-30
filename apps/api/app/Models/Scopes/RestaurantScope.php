<?php

namespace App\Models\Scopes;

use App\Enums\RoleEnum;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Global scope that constrains every query on a tenant-owned model to the
 * currently resolved restaurant. This makes cross-tenant data structurally
 * unreachable even if a controller forgets an explicit ownership check.
 *
 * The scope is a no-op for Super Admins (who operate across all restaurants
 * by explicit id) and when no tenant has been resolved (e.g. console, public
 * menu queries that scope manually by slug).
 */
class RestaurantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $restaurantId = TenantContext::restaurantId();

        if ($restaurantId === null) {
            return;
        }

        $builder->where($model->getTable() . '.restaurant_id', $restaurantId);
    }
}
