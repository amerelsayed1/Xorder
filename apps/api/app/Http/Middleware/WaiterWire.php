<?php

namespace App\Http\Middleware;

use App\Enums\RestaurantStatus;
use App\Enums\UserStatus;
use App\Exceptions\WaiterWireException;
use App\Models\PosWaiterDevice;
use App\Models\PosWaiterSession;
use App\Models\Restaurant;
use App\Models\User;
use App\Support\TenantContext;
use App\Support\WaiterToken;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * The waiter wire's gate (POS-BE-033), one middleware, three depths:
 *
 *   waiter:public   slug → restaurant, entitlement   (hello, sign-in)
 *   waiter:device   + a registered, unrevoked device (sign-out)
 *   waiter:session  + a signed-in waiter on that device (everything else)
 *
 * The tenant comes ONLY from the slug in the path, is pinned for the request
 * and released in `finally` (the public-path pattern). Device and session rows
 * are looked up with that restaurant_id, so a token of restaurant A is simply
 * unknown at restaurant B.
 *
 * Deliberately not under `feature:pos`: the cloud flavor is for restaurants
 * without a till, so the gate is table management.
 */
class WaiterWire
{
    public function handle(Request $request, Closure $next, string $depth = 'session'): Response
    {
        $restaurant = Restaurant::query()
            ->with('features')
            ->where('slug', (string) $request->route('slug'))
            ->first();

        if ($restaurant === null) {
            throw new WaiterWireException('NOT_FOUND', 404);
        }

        if (in_array($restaurant->status, [RestaurantStatus::SUSPENDED, RestaurantStatus::ARCHIVED], true)
            || ! $restaurant->hasFeature('table_management')) {
            throw new WaiterWireException('NOT_PERMITTED', 403, ['reason' => 'service_unavailable']);
        }

        $request->attributes->set('waiter_restaurant', $restaurant);

        TenantContext::overrideId($restaurant->id);

        try {
            if ($depth !== 'public') {
                $device = $this->device($request, $restaurant);
                $request->attributes->set('waiter_device', $device);

                if ($depth === 'session') {
                    $this->session($request, $restaurant, $device);
                }
            }

            return $next($request);
        } finally {
            TenantContext::clearOverride();
        }
    }

    /** The device named by `Authorization: Device <token>`, or null when none was sent. */
    public static function deviceFromHeader(Request $request, Restaurant $restaurant): ?PosWaiterDevice
    {
        $header = (string) $request->header('Authorization', '');

        if (! preg_match('/^Device\s+(\S+)$/i', $header, $m)) {
            return null;
        }

        $token = $m[1];

        if (! WaiterToken::looksValid($token, WaiterToken::DEVICE_PREFIX)) {
            throw new WaiterWireException('UNPAIRED', 401);
        }

        $device = PosWaiterDevice::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('token_hash', WaiterToken::hash($token))
            ->first();

        if ($device === null) {
            throw new WaiterWireException('UNPAIRED', 401);
        }

        if ($device->isRevoked()) {
            throw new WaiterWireException('DEVICE_REVOKED', 403);
        }

        return $device;
    }

    private function device(Request $request, Restaurant $restaurant): PosWaiterDevice
    {
        $device = self::deviceFromHeader($request, $restaurant);

        if ($device === null) {
            throw new WaiterWireException('UNPAIRED', 401);
        }

        if ($device->last_seen_at === null || $device->last_seen_at->lt(now()->subMinute())) {
            $device->forceFill(['last_seen_at' => now()])->save();
        }

        return $device;
    }

    private function session(Request $request, Restaurant $restaurant, PosWaiterDevice $device): void
    {
        $token = (string) $request->header('X-Waiter-Session', '');

        if (! WaiterToken::looksValid($token, WaiterToken::SESSION_PREFIX)) {
            throw new WaiterWireException('SIGN_IN_REQUIRED', 401);
        }

        $session = PosWaiterSession::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('device_id', $device->id)
            ->where('token_hash', WaiterToken::hash($token))
            ->where('last_seen_at', '>=', now()->subHours(PosWaiterSession::IDLE_HOURS))
            ->first();

        $user = $session === null ? null : User::query()
            ->with('tenantRole')
            ->where('restaurant_id', $restaurant->id)
            ->where('status', UserStatus::ACTIVE)
            ->find($session->user_id);

        if ($session === null || $user === null) {
            throw new WaiterWireException('SIGN_IN_REQUIRED', 401);
        }

        if ($session->last_seen_at->lt(now()->subMinute())) {
            $session->forceFill(['last_seen_at' => now()])->save();
        }

        $request->attributes->set('waiter_session', $session);
        $request->attributes->set('waiter_user', $user);
    }
}
