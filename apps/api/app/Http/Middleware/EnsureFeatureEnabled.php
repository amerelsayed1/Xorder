<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Per-restaurant feature gate. Usage: ->middleware('feature:table_management').
 * The flag is configured by the Super Admin at client creation (Step 5) and
 * stored in restaurant_features.
 */
class EnsureFeatureEnabled
{
    public function handle(Request $request, Closure $next, string $feature): Response
    {
        $restaurant = $request->user()?->restaurant;

        if ($restaurant === null || ! $restaurant->hasFeature($feature)) {
            abort(403, __('xorder.errors.feature_disabled'));
        }

        return $next($request);
    }
}
