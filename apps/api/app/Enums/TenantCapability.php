<?php

namespace App\Enums;

/**
 * Fine-grained capabilities inside a restaurant. Each value is registered as a
 * Laravel Gate ability in AppServiceProvider and referenced by `can:<value>`
 * middleware on the `/api/dashboard/*` routes.
 *
 * Unlike the platform-side {@see Capability}, these are NOT mapped from a static
 * role matrix: a restaurant builds its own roles (`roles` table) and picks the
 * capabilities each one grants. The owner account (RESTAURANT_ADMIN) implicitly
 * holds every capability — see User::holdsTenantCapability().
 *
 * Verbs are per-action rather than a blanket "manage", so a role can be allowed
 * to add and edit menu items without also being allowed to delete them. A
 * resource only declares the verbs its endpoints actually support: orders and
 * bills are never created or deleted from the dashboard (diners raise them and
 * they are settled by status change), so they carry view+update only. Inventing
 * `orders.create` would put a checkbox in the role editor that governs nothing.
 *
 * Values must not collide with Capability's: Gate abilities share one namespace.
 */
enum TenantCapability: string
{
    /**
     * The live board — the at-a-glance floor screen combining the order queue,
     * open bill requests and table occupancy.
     *
     * Its own capability rather than a side effect of tables.view, because
     * "works the live screen" and "administers the table layout" are different
     * jobs: a waiter needs the first without the second, and gating the board on
     * tables.view forced the Tables and Dining Areas sections into their sidebar
     * alongside it. Acting on what the board shows still needs the matching
     * verb (orders.update to advance an order, tables.update to close a visit).
     */
    case LIVE_VIEW = 'live.view';

    // Live order queue — raised by diners, progressed by staff.
    case ORDERS_VIEW = 'orders.view';
    case ORDERS_UPDATE = 'orders.update';

    // Menu: items, categories, combos and option groups.
    case MENU_VIEW = 'menu.view';
    case MENU_CREATE = 'menu.create';
    case MENU_UPDATE = 'menu.update';
    case MENU_DELETE = 'menu.delete';

    // Dining areas, tables and their QR codes.
    case TABLES_VIEW = 'tables.view';
    case TABLES_CREATE = 'tables.create';
    case TABLES_UPDATE = 'tables.update';
    case TABLES_DELETE = 'tables.delete';

    // Branches and their presence configuration.
    case BRANCHES_VIEW = 'branches.view';
    case BRANCHES_CREATE = 'branches.create';
    case BRANCHES_UPDATE = 'branches.update';
    case BRANCHES_DELETE = 'branches.delete';

    // Bill requests — raised at the table, settled by status change.
    case BILLS_VIEW = 'bills.view';
    case BILLS_UPDATE = 'bills.update';

    // Customer directory (read-only from the dashboard).
    case CUSTOMERS_VIEW = 'customers.view';

    // Internal reviews — moderated, never authored, by staff.
    case REVIEWS_VIEW = 'reviews.view';
    case REVIEWS_UPDATE = 'reviews.update';

    case ANALYTICS_VIEW = 'analytics.view';

    case REPORTS_VIEW = 'reports.view';

    // Restaurant profile, branding and QR.
    case SETTINGS_VIEW = 'settings.view';
    case SETTINGS_UPDATE = 'settings.update';

    // Staff accounts and the roles assigned to them.
    case STAFF_VIEW = 'staff.view';
    case STAFF_CREATE = 'staff.create';
    case STAFF_UPDATE = 'staff.update';
    case STAFF_DELETE = 'staff.delete';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(fn (self $c) => $c->value, self::cases());
    }

    /** The resource half of the value — "menu" for menu.create. */
    public function resource(): string
    {
        return strtok($this->value, '.');
    }

    /** The verb half — view|create|update|delete. */
    public function action(): string
    {
        return substr($this->value, strlen($this->resource()) + 1);
    }

    /**
     * UI grouping key for the role builder. Purely presentational — the server
     * gates on individual values.
     */
    public function group(): string
    {
        return match ($this->resource()) {
            'live', 'orders', 'bills' => 'operations',
            'menu' => 'menu',
            'tables', 'branches' => 'place',
            'customers', 'reviews' => 'engagement',
            'analytics', 'reports' => 'analytics',
            default => 'administration',
        };
    }

    /**
     * The "view" capability an action implies. Granting an action without its
     * view would let someone write a section they cannot open, so the role
     * service expands every verb → view on save.
     */
    public function implies(): ?self
    {
        if ($this->action() === 'view') {
            return null;
        }

        return self::tryFrom($this->resource().'.view');
    }

    /**
     * Expand a requested capability list: drop unknown values, add every implied
     * "view", and return a stable, de-duplicated list.
     *
     * @param  list<string>  $requested
     * @return list<string>
     */
    public static function expand(array $requested): array
    {
        $out = [];

        foreach (self::translateLegacy(array_map('strval', $requested)) as $value) {
            $cap = self::tryFrom($value);

            if ($cap === null) {
                continue;
            }

            $out[$cap->value] = true;

            if ($implied = $cap->implies()) {
                $out[$implied->value] = true;
            }
        }

        // Keep enum declaration order so stored JSON is deterministic.
        return array_values(array_filter(self::values(), fn (string $v) => isset($out[$v])));
    }

    /**
     * How a pre-split "manage" value maps onto the new verbs.
     *
     * Roles saved before the split still carry `menu.manage` and friends; this
     * is the single definition of what those meant, used by the migration and
     * by {@see expand()} so an old value arriving from a stale client is
     * translated rather than silently dropped.
     *
     * @return array<string, list<string>>
     */
    public static function legacyManageMap(): array
    {
        return [
            'orders.manage' => [self::ORDERS_UPDATE->value],
            'menu.manage' => [self::MENU_CREATE->value, self::MENU_UPDATE->value, self::MENU_DELETE->value],
            'tables.manage' => [self::TABLES_CREATE->value, self::TABLES_UPDATE->value, self::TABLES_DELETE->value],
            'branches.manage' => [self::BRANCHES_CREATE->value, self::BRANCHES_UPDATE->value, self::BRANCHES_DELETE->value],
            'bills.manage' => [self::BILLS_UPDATE->value],
            'reviews.manage' => [self::REVIEWS_UPDATE->value],
            'settings.manage' => [self::SETTINGS_VIEW->value, self::SETTINGS_UPDATE->value],
            'staff.manage' => [
                self::STAFF_VIEW->value, self::STAFF_CREATE->value,
                self::STAFF_UPDATE->value, self::STAFF_DELETE->value,
            ],
        ];
    }

    /**
     * Translate any legacy "manage" values in a list into their verb equivalents,
     * leaving already-current values untouched.
     *
     * @param  list<string>  $values
     * @return list<string>
     */
    public static function translateLegacy(array $values): array
    {
        $map = self::legacyManageMap();
        $out = [];

        foreach ($values as $value) {
            foreach ($map[$value] ?? [$value] as $translated) {
                $out[] = $translated;
            }
        }

        return array_values(array_unique($out));
    }
}
