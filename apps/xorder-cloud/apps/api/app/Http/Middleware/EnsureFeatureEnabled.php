<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Per-restaurant feature gate. Usage: ->middleware('feature:table_management').
 * The flag is configured by the Super Admin at client creation (Step 5) and
 * stored in restaurant_features.
 *
 * ANY-OF form: ->middleware('feature:system_ordering|pos') passes when the
 * restaurant holds at least one of the pipe-separated keys. It exists for the
 * routes that serve more than one plan feature at once — the order queue is
 * where online orders land, but it is also where a till's sales land, and a
 * restaurant that paid for the POS and not for online ordering was reading
 * "no orders yet" over a day with a sale on it (S2-1, 16 Oct 2026). The
 * single-key form is the any-of form with one key; nothing else changes.
 */
class EnsureFeatureEnabled
{
    public function handle(Request $request, Closure $next, string $features): Response
    {
        $restaurant = $request->user()?->restaurant;

        $keys = array_filter(array_map('trim', explode('|', $features)));

        $held = false;
        foreach ($keys as $key) {
            if ($restaurant?->hasFeature($key)) {
                $held = true;
                break;
            }
        }

        if (! $held) {
            abort(403, __('xorder.errors.feature_disabled'));
        }

        return $next($request);
    }
}
