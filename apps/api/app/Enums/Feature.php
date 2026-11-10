<?php

namespace App\Enums;

/**
 * Per-restaurant feature flags. The Super Admin toggles these when creating or
 * editing a client (client-creation wizard, Step 5); the restaurant dashboard
 * and public menu read them to gate table management, bill requests, reviews
 * and analytics.
 *
 * Availability may additionally be constrained by the subscription Plan — this
 * enum only models what a feature *is* and what it depends on, not who is
 * entitled to it.
 */
enum Feature: string
{
    case QR_MENU = 'qr_menu';
    case WHATSAPP_ORDERING = 'whatsapp_ordering';
    case SYSTEM_ORDERING = 'system_ordering';
    case CUSTOMER_TRACKING = 'customer_tracking';
    case TABLE_MANAGEMENT = 'table_management';
    case BILL_REQUESTS = 'bill_requests';
    case INTERNAL_REVIEWS = 'internal_reviews';
    case PRODUCT_ANALYTICS = 'product_analytics';
    case DINE_IN = 'dine_in';
    case PICKUP = 'pickup';
    case DELIVERY = 'delivery';
    case MULTI_BRANCH = 'multi_branch';

    /**
     * The POS surface (POS-BE-001). Gates every /api/pos terminal route and
     * the dashboard provisioning/money-config sections via `feature:pos`.
     * Deliberately absent from defaultSet() and from every existing plan's
     * feature_keys, so it resolves to FALSE for every existing tenant — it is
     * sold, not inherited.
     */
    case POS = 'pos';

    /**
     * Purchasing and inventory (CB-09): suppliers, units, and later purchase
     * orders, receiving, supplier invoices and stock. Gates the dashboard
     * purchasing routes via `feature:purchasing`.
     *
     * A STANDALONE feature: it deliberately does not require `pos`. A café, a
     * cloud kitchen or any other client may buy it with no till at all (owner
     * decision 2026-09-12). Like `pos`, it is sold, not inherited: absent from
     * defaultSet() and from every existing plan's feature_keys, so it resolves
     * to FALSE for every existing tenant.
     */
    case PURCHASING = 'purchasing';

    /**
     * Guest paging (docs/features/guest-paging): the diner's phone replaces
     * the counter pager. Gates the pickup board, the public tracking page and
     * the prep-time report via `feature:guest_paging`. Standalone — a café
     * with no till pages its QR orders, a till-only client pages its receipts.
     * Sold, not inherited: absent from defaultSet(), so it resolves to FALSE
     * for every existing tenant; a fresh install seeds it on Restaurant Pro.
     */
    case GUEST_PAGING = 'guest_paging';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(fn (self $f) => $f->value, self::cases());
    }

    /**
     * Feature-to-feature prerequisites (FR-FEATURES-005). Only flag-level
     * dependencies live here; non-flag prerequisites (a branch must support
     * dine-in for tables, a valid WhatsApp number for WhatsApp ordering) are
     * enforced where that data is validated, not in the flag graph.
     *
     * @return list<self>
     */
    public function requires(): array
    {
        return match ($this) {
            self::BILL_REQUESTS => [self::TABLE_MANAGEMENT],
            // Seating diners at tables implies dine-in ordering (FR-FEATURES-005).
            self::TABLE_MANAGEMENT => [self::DINE_IN],
            // Customers are captured on every ordering type (system orders and
            // WhatsApp checkout alike), so the directory has no prerequisite.
            default => [],
        };
    }

    /**
     * The default flags a brand-new client is created with when the caller does
     * not specify a set (e.g. self-serve signup): the capabilities XOrder
     * already ships today. The table-experience features stay off until the
     * Super Admin opts the client in.
     *
     * @return array<string,bool>
     */
    public static function defaultSet(): array
    {
        $on = [self::QR_MENU, self::WHATSAPP_ORDERING, self::PICKUP, self::DELIVERY];

        return array_reduce(
            self::cases(),
            fn (array $carry, self $f) => $carry + [$f->value => in_array($f, $on, true)],
            [],
        );
    }

    /**
     * Expand a requested flag map so that every enabled feature also enables the
     * features it requires (FR-FEATURES-006). Unknown keys are ignored; missing
     * keys default to disabled.
     *
     * @param  array<string,bool>  $requested
     * @return array<string,bool>
     */
    public static function resolve(array $requested): array
    {
        $resolved = [];
        foreach (self::cases() as $feature) {
            $resolved[$feature->value] = (bool) ($requested[$feature->value] ?? false);
        }

        // Enabling a dependent feature pulls in its prerequisites, transitively.
        $changed = true;
        while ($changed) {
            $changed = false;
            foreach (self::cases() as $feature) {
                if (! $resolved[$feature->value]) {
                    continue;
                }
                foreach ($feature->requires() as $parent) {
                    if (! $resolved[$parent->value]) {
                        $resolved[$parent->value] = true;
                        $changed = true;
                    }
                }
            }
        }

        return $resolved;
    }
}
