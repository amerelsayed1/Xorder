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
}
