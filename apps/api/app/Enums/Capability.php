<?php

namespace App\Enums;

/**
 * Fine-grained admin-panel capabilities. Each value is registered as a Laravel
 * Gate ability in AppServiceProvider and referenced by `can:<value>` route
 * middleware. RoleEnum::capabilities() maps roles → these; SUPER_ADMIN bypasses
 * via Gate::before.
 */
enum Capability: string
{
    case PLATFORM_USERS_MANAGE = 'platform_users.manage';
    case RESTAURANTS_VIEW = 'restaurants.view';
    case RESTAURANTS_MANAGE = 'restaurants.manage';
    case PLANS_MANAGE = 'plans.manage';
    case SUBSCRIPTIONS_MANAGE = 'subscriptions.manage';
    case LEADS_MANAGE = 'leads.manage';
    case LANDING_MANAGE = 'landing.manage';
    case AUDIT_VIEW = 'audit.view';
    case INSIGHTS_VIEW = 'insights.view';

    /**
     * Issue, renew and revoke POS licences (POS-BE-015).
     *
     * Deliberately granted to no staff role in RoleEnum::capabilities():
     * issuing commercial entitlement is not a reversible action, and the
     * capability is cheap to widen later. SUPER_ADMIN holds it through the
     * Gate::before bypass.
     */
    case LICENCES_MANAGE = 'licences.manage';

    /**
     * Cross-tenant POS fleet views (POS-BE-022): every terminal, across every
     * tenant, with heartbeat state. Like LICENCES_MANAGE it is granted to no
     * staff role by default — SUPER_ADMIN holds it via Gate::before, and
     * widening it to SUPPORT later is cheap.
     */
    case POS_FLEET_VIEW = 'pos_fleet.view';

    /**
     * Create terminals for a tenant from the platform side (owner decision,
     * 2026-09-05). Tenant creation mints a tenant and its licence and stops
     * there; every terminal after that is one deliberate act by whoever holds
     * this, which is why it is a capability of its own and not folded into
     * POS_FLEET_VIEW. Granted to no staff role — SUPER_ADMIN holds it via the
     * Gate::before bypass.
     */
    case POS_FLEET_MANAGE = 'pos_fleet.manage';
}
