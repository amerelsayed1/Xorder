<?php

namespace App\Http\Middleware;

use App\Enums\RestaurantStatus;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Blocks dashboard write operations when the restaurant is not in a writable
 * state — either suspended/archived, or (when enforcement is on) the
 * subscription does not allow writes (EXPIRED/SUSPENDED). Read requests pass.
 */
class EnsureSubscriptionAllowsWrites
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        $restaurant = $user?->restaurant;

        if ($restaurant === null) {
            abort(403, __('xorder.errors.no_restaurant_context'));
        }

        if ($restaurant->status === RestaurantStatus::ARCHIVED) {
            abort(403, __('xorder.errors.restaurant_archived'));
        }

        if ($restaurant->status === RestaurantStatus::SUSPENDED) {
            abort(403, __('xorder.errors.restaurant_suspended'));
        }

        if (config('platform.subscription.enforce_dashboard_writes')
            && ! $restaurant->subscription_status->allowsDashboardWrites()) {
            abort(403, __('xorder.errors.subscription_inactive'));
        }

        return $next($request);
    }
}
