<?php

namespace App\Support;

use App\Enums\RoleEnum;
use Illuminate\Support\Facades\Auth;

/**
 * Resolves the "current restaurant" for tenant-scoped queries.
 *
 * Source of truth is the authenticated user's restaurant_id — NEVER the
 * request payload. A Super Admin has no tenant context (returns null), so the
 * global RestaurantScope does not constrain their queries; they address
 * restaurants explicitly by id through the admin endpoints.
 *
 * `overrideId()` allows trusted server-side code (e.g. the public menu
 * controller, which resolves a restaurant by slug) to pin the tenant for the
 * duration of a request without going through auth.
 */
class TenantContext
{
    protected static ?int $overrideId = null;

    public static function overrideId(?int $restaurantId): void
    {
        static::$overrideId = $restaurantId;
    }

    public static function clearOverride(): void
    {
        static::$overrideId = null;
    }

    public static function restaurantId(): ?int
    {
        if (static::$overrideId !== null) {
            return static::$overrideId;
        }

        $user = Auth::user();

        if ($user === null) {
            return null;
        }

        // Super Admins are not tenant-bound.
        if ($user->role === RoleEnum::SUPER_ADMIN) {
            return null;
        }

        return $user->restaurant_id;
    }
}
