<?php

namespace App\Enums;

enum RoleEnum: string
{
    // Platform-level roles (restaurant_id = null). SUPER_ADMIN is the owner
    // account; ADMIN/MODERATOR/SALES/SUPPORT are staff roles assignable from the
    // Super-Admin panel, each gated to a subset of capabilities (see below).
    case SUPER_ADMIN = 'SUPER_ADMIN';
    case ADMIN = 'ADMIN';
    case MODERATOR = 'MODERATOR';
    case SALES = 'SALES';
    case SUPPORT = 'SUPPORT';

    // Tenant-level role (restaurant_id set). Managed per-restaurant, not here.
    case RESTAURANT_ADMIN = 'RESTAURANT_ADMIN';

    public function isSuperAdmin(): bool
    {
        return $this === self::SUPER_ADMIN;
    }

    public function isRestaurantAdmin(): bool
    {
        return $this === self::RESTAURANT_ADMIN;
    }

    /**
     * Any platform-level role (lives on the admin subdomain, restaurant_id null).
     */
    public function isPlatformRole(): bool
    {
        return $this !== self::RESTAURANT_ADMIN;
    }

    /**
     * The capability strings this role grants. SUPER_ADMIN is intentionally
     * omitted here — it is granted everything via a Gate::before bypass in
     * AppServiceProvider, so its capabilities are implicit.
     *
     * Keep this matrix in sync with ROLE_CAPS in packages/api-client/src/auth.js
     * (the frontend copy is UX-only; these server gates are authoritative).
     *
     * @return list<string>
     */
    public function capabilities(): array
    {
        return match ($this) {
            self::SUPER_ADMIN => array_map(fn (Capability $c) => $c->value, Capability::cases()),
            self::ADMIN => [
                Capability::RESTAURANTS_VIEW->value,
                Capability::RESTAURANTS_MANAGE->value,
                Capability::PLANS_MANAGE->value,
                Capability::SUBSCRIPTIONS_MANAGE->value,
                Capability::LEADS_MANAGE->value,
                Capability::LANDING_MANAGE->value,
                Capability::AUDIT_VIEW->value,
                Capability::INSIGHTS_VIEW->value,
            ],
            self::MODERATOR => [
                Capability::RESTAURANTS_VIEW->value,
                Capability::RESTAURANTS_MANAGE->value,
                Capability::LANDING_MANAGE->value,
                Capability::INSIGHTS_VIEW->value,
            ],
            self::SALES => [
                Capability::RESTAURANTS_VIEW->value,
                Capability::PLANS_MANAGE->value,
                Capability::SUBSCRIPTIONS_MANAGE->value,
                Capability::LEADS_MANAGE->value,
                Capability::INSIGHTS_VIEW->value,
            ],
            self::SUPPORT => [
                Capability::RESTAURANTS_VIEW->value,
                Capability::AUDIT_VIEW->value,
                Capability::INSIGHTS_VIEW->value,
            ],
            self::RESTAURANT_ADMIN => [],
        };
    }

    /**
     * Roles the Super-Admin UI may assign to a platform user. SUPER_ADMIN (owner)
     * and RESTAURANT_ADMIN (provisioned with a restaurant) are deliberately not
     * assignable here.
     *
     * @return list<string>
     */
    public static function assignable(): array
    {
        return [
            self::ADMIN->value,
            self::MODERATOR->value,
            self::SALES->value,
            self::SUPPORT->value,
        ];
    }

    /**
     * Every platform-level role value — used to gate the admin route group.
     *
     * @return list<string>
     */
    public static function platformRoles(): array
    {
        return [
            self::SUPER_ADMIN->value,
            self::ADMIN->value,
            self::MODERATOR->value,
            self::SALES->value,
            self::SUPPORT->value,
        ];
    }
}
