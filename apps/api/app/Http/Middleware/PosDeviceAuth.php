<?php

namespace App\Http\Middleware;

use App\Exceptions\PosApiException;
use App\Models\PosTerminal;
use App\Support\DeviceToken;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * The device credential (POS-BE-011, Option C), as the `pos.device` route
 * middleware.
 *
 * Deliberately NOT a Laravel auth guard: a PosTerminal is not an
 * Authenticatable, and TenantContext/EnsureFeatureEnabled read
 * $request->user()->role / ->restaurant — attributes a terminal does not have.
 * Instead this middleware resolves the terminal from the xdt_ bearer, pins
 * TenantContext for the request (released in finally, the public-path
 * pattern), and exposes the terminal via $request->attributes['pos_terminal'].
 *
 * Accepts the current token, or — for ROTATION_OVERLAP_HOURS after a rotation
 * — the previous one, so a till that crashed between receiving and persisting
 * a new token is not bricked.
 *
 * A REVOKED terminal is 403 TERMINAL_REVOKED, distinct from 401
 * DEVICE_TOKEN_INVALID, because the client reactions differ: re-pair vs tell
 * the manager. (BE-A04's "queued records still accepted for drain" applies to
 * the deferred bulk-sync endpoint; on the serial cloud path revocation stops
 * new writes.)
 *
 * The feature gate (`feature:pos` → POS_FEATURE_DISABLED) rides the `feature`
 * parameter so money routes enforce entitlement while the heartbeat stays
 * exempt — a lapsed feature must not silence the fleet view (POS-BE-022).
 */
class PosDeviceAuth
{
    public function handle(Request $request, Closure $next, string $feature = 'feature'): Response
    {
        $token = $request->bearerToken();

        if (! DeviceToken::looksValid($token)) {
            throw new PosApiException('DEVICE_TOKEN_INVALID', 401);
        }

        $hash = DeviceToken::hash($token);

        // No tenant context yet, so RestaurantScope is a no-op here — the token
        // hash is globally unique and IS the lookup key.
        // Eager-load what the feature check and the services read — strict
        // Eloquent mode (rightly) refuses a lazy restaurant load here.
        $terminal = PosTerminal::query()
            ->with('restaurant.features')
            ->where('device_token_hash', $hash)
            ->orWhere(function ($q) use ($hash) {
                $q->where('previous_token_hash', $hash)
                    ->where('device_token_rotated_at', '>=', now()->subHours(PosTerminal::ROTATION_OVERLAP_HOURS));
            })
            ->first();

        if ($terminal === null) {
            throw new PosApiException('DEVICE_TOKEN_INVALID', 401);
        }

        if ($terminal->isRevoked()) {
            throw new PosApiException('TERMINAL_REVOKED', 403);
        }

        if ($feature !== 'no-feature' && ! $terminal->restaurant->hasFeature('pos')) {
            throw new PosApiException('POS_FEATURE_DISABLED', 403);
        }

        $request->attributes->set('pos_terminal', $terminal);

        TenantContext::overrideId($terminal->restaurant_id);

        try {
            return $next($request);
        } finally {
            TenantContext::clearOverride();
        }
    }
}
