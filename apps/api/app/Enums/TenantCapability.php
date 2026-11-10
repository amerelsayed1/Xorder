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

    /*
    | POS verbs (POS-BE-002). Final strings agreed in BACKEND_TO_POS.md A1:
    | single-dot only — resource() is strtok on '.', so a two-dot name would
    | parse to the wrong resource and implies() would hunt a capability that
    | does not exist. pos.operate is the view-equivalent for the pos resource:
    | every other pos verb implies it (see implies()).
    */
    case POS_OPERATE = 'pos.operate';
    case POS_DISCOUNT = 'pos.discount';
    case POS_PRICE_OVERRIDE = 'pos.price_override';
    case POS_VOID = 'pos.void';
    case POS_REFUND = 'pos.refund';
    case POS_SHIFT_OPEN = 'pos.shift_open';
    case POS_SHIFT_CLOSE = 'pos.shift_close';
    case POS_CASH_MOVEMENT = 'pos.cash_movement';
    case POS_REPRINT = 'pos.reprint';

    // Dashboard-side POS provisioning: create terminals, issue pairing codes,
    // revoke (POS-BE-023). Path B registration accepts any staff holding this.
    case POS_PROVISION = 'pos.provision';

    // The first write verb on customers (POS-BE-014). customers.view stays the
    // dashboard's read; the till creates through /api/pos/customers.
    case CUSTOMERS_CREATE = 'customers.create';

    /*
    | Purchasing and inventory (CB-09). ONE capability, not five, and it gates
    | reads as well as writes: who a business buys from and what it pays is
    | its commercial position, not something every account should browse
    | (till doc 16 §6, owner decision 2026-09-12). It is the till's own string
    | (xorder-pos permissions.dart).
    |
    | NOTE: this `.manage` is a LIVE single verb. Elsewhere in this enum
    | `.manage` means "pre-split legacy value" (legacyManageMap). This one must
    | never join legacyManageMap, or every role holding it would be rewritten
    | into verbs that don't exist. It has no `.view`, so implies() is null.
    */
    case PURCHASE_MANAGE = 'purchase.manage';

    /*
    | Which order types a branch offers (XORD-002). The spelling is the
    | owner's; it has more dots than the rest of this enum, which is fine:
    | resource() is strtok on the FIRST dot ("pos"), so it groups with the POS
    | verbs and implies pos.operate like them, and action() is the remainder.
    | Owners hold it by default (RESTAURANT_ADMIN bypass); a role gets it only
    | by being given it. Not in legacyManageMap, which is keyed on exact values.
    */
    case POS_ORDER_TYPES_MANAGE = 'pos.settings.order_types.manage';

    /*
    | The business's money accounts and where each payment method pays into
    | (XORD-015). ONE live verb, deliberately not `settings.update`: a person
    | who may rename a payment method must not also be able to redirect the
    | money. It has no `.view` of its own: reading the account list rides on
    | settings.view (the payment-method editor already needs it) and
    | implies() returns SETTINGS_VIEW, because the accounts live in Settings.
    | It must never join legacyManageMap. It is the
    | till's own string (xorder-pos permissions.dart `finance.accounts`).
    | Owners hold it by default; a role gets it only by being given it.
    */
    case FINANCE_ACCOUNTS = 'finance.accounts';

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
            'pos' => 'pos',
            'menu' => 'menu',
            'tables', 'branches' => 'place',
            'customers', 'reviews' => 'engagement',
            'analytics', 'reports' => 'analytics',
            'purchase' => 'buying',
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

        // The pos resource has no `.view`: pos.operate IS its view-equivalent
        // (agreed as A1). Every other pos verb implies it; it implies nothing.
        if ($this->resource() === 'pos') {
            return $this === self::POS_OPERATE ? null : self::POS_OPERATE;
        }

        // finance.accounts has no `.view` of its own; the accounts live in
        // Settings, so managing them implies being able to open Settings.
        if ($this === self::FINANCE_ACCOUNTS) {
            return self::SETTINGS_VIEW;
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
